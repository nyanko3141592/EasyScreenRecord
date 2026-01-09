import Foundation
import ScreenCaptureKit
import AVFoundation
import Combine
import AppKit
import SwiftUI

class ScreenRecorder: NSObject, ObservableObject, SCStreamOutput {
    enum RecordingState {
        case idle
        case starting
        case recording
        case stopping
        case error(Error)
    }

    @Published var state: RecordingState = .idle
    @Published var availableContent: SCShareableContent?
    
    // UI Helpers
    var isRecording: Bool {
        if case .recording = state { return true }
        if case .stopping = state { return true }
        return false
    }
    
    var isBusy: Bool {
        if case .starting = state { return true }
        if case .stopping = state { return true }
        return false
    }
    
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    // Zoom & Region settings
    private(set) var zoomScale: CGFloat = 2.0
    private(set) var baseRegion: CGRect? // nil means full screen
    var zoomSettings = ZoomSettings()

    // Zoom Logic Internals
    private var lastTargetPosition: CGPoint = .zero
    private var lockedTargetPosition: CGPoint = .zero  // Position that zoom is locked to
    private var currentSourceRect: CGRect = .zero
    private var displaySize: CGSize = .zero
    private var displayOrigin: CGPoint = .zero  // Display origin in global coordinates
    private var currentSmoothScale: CGFloat = 1.0
    private var isTypingDetected = false
    private var lastTypingDetectedTime: Date = .distantPast
    private var lastPositionChangeTime: Date = .distantPast
    private var isZoomActive = false  // Whether zoom is currently engaged

    // Timers & Windows
    private var timer: Timer?
    private var overlayWindow: NSWindow?
    private var overlayViewModel: OverlayViewModel?
    private var dimmingWindow: NSWindow?
    private var dimmingViewModel: DimmingViewModel?
    private var subtitleWindow: NSWindow?
    private var subtitleViewModel: SubtitleViewModel?
    private var lastUpdateTimestamp: Date = .distantPast
    private var lastSubtitleText: String = ""
    private var lastSubtitleUpdateTime: Date = .distantPast

    // Serial queue for writing to ensure safety
    private let writingQueue = DispatchQueue(label: "com.nya3neko2.EasyScreenRecord.writingQueue", qos: .userInitiated)
    private var isWritingSessionStarted = false
    private var isStopping = false // Flag to prevent new writes during stop

    func setZoomScale(_ scale: CGFloat) {
        self.zoomScale = scale
        DispatchQueue.main.async {
            self.updateOverlaySize()
        }
    }

    func setBaseRegion(_ region: CGRect?) {
        self.baseRegion = region
    }

    @MainActor
    func startCapture() async {
        guard case .idle = state else { return }
        state = .starting

        do {
            // Setup overlay windows FIRST and show them (before getting content, so we can exclude them)
            setupOverlayWindow()
            setupDimmingWindow()

            // Show windows immediately so they appear in SCShareableContent
            overlayWindow?.orderFrontRegardless()
            dimmingWindow?.orderFrontRegardless()

            // Delay to ensure windows are registered in the window server
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 second

            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            self.availableContent = content

            guard let display = content.displays.first else {
                throw NSError(domain: "ScreenRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
            }

            displaySize = CGSize(width: CGFloat(display.width), height: CGFloat(display.height))

            // Get display origin for coordinate conversion (Accessibility uses global coordinates)
            // SCDisplay doesn't expose frame directly, so get it from NSScreen
            let targetScreen = getTargetScreen()
            // NSScreen uses bottom-left origin; convert to top-left for Accessibility coordinates
            let primaryHeight = NSScreen.screens.first?.frame.height ?? displaySize.height
            displayOrigin = CGPoint(
                x: targetScreen.frame.origin.x,
                y: primaryHeight - targetScreen.frame.origin.y - targetScreen.frame.height
            )

            let config = SCStreamConfiguration()
            config.width = Int(displaySize.width) * 2
            config.height = Int(displaySize.height) * 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(zoomSettings.frameRate))
            config.queueDepth = 8
            config.showsCursor = zoomSettings.showCursor

            // Exclude ALL windows from our own app (overlay, dimming, settings, etc.)
            let myBundleID = Bundle.main.bundleIdentifier ?? ""
            let myPID = ProcessInfo.processInfo.processIdentifier

            var windowsToExclude: [SCWindow] = []
            for scWindow in content.windows {
                // Exclude by matching our process ID or bundle identifier
                if let owningApp = scWindow.owningApplication {
                    if owningApp.processID == myPID || owningApp.bundleIdentifier == myBundleID {
                        windowsToExclude.append(scWindow)
                    }
                }
            }

            #if DEBUG
            print("[Capture] Excluding \(windowsToExclude.count) windows from our app (PID: \(myPID), Bundle: \(myBundleID))")
            for w in windowsToExclude {
                print("  - Window: \(w.windowID) - \(w.title ?? "untitled")")
            }
            #endif

            let filter = SCContentFilter(display: display, excludingWindows: windowsToExclude)

            // Reset Session State
            isWritingSessionStarted = false
            isStopping = false

            // Reset Zoom State
            currentSmoothScale = 1.0
            isTypingDetected = false
            isZoomActive = false
            lastTypingDetectedTime = .distantPast
            lastPositionChangeTime = .distantPast
            currentSourceRect = CGRect(origin: .zero, size: displaySize)

            // Initialize lastTargetPosition based on baseRegion or screen center (in local coordinates)
            let initialPosition: CGPoint
            if let region = baseRegion {
                // baseRegion is in NSWindow global coordinates (bottom-left origin)
                // Convert to display-local top-left origin
                let localX = region.midX - displayOrigin.x
                let localY = displaySize.height - (region.midY - displayOrigin.y)
                initialPosition = CGPoint(x: localX, y: localY)
            } else {
                initialPosition = CGPoint(x: displaySize.width / 2, y: displaySize.height / 2)
            }
            lastTargetPosition = initialPosition
            lockedTargetPosition = initialPosition

            // Setup Asset Writer
            try setupAssetWriter(width: config.width, height: config.height)

            // Setup Stream
            let newStream = SCStream(filter: filter, configuration: config, delegate: self)
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: writingQueue)
            self.stream = newStream

            try await newStream.startCapture()

            // Start keyboard monitoring for typing detection
            KeyboardMonitor.shared.showModifierKeys = zoomSettings.showModifierKeys
            KeyboardMonitor.shared.startMonitoring()

            // Initialize dimming hole rect based on baseRegion or full screen
            // Note: targetScreen was already obtained above for displayOrigin
            if let viewModel = dimmingViewModel {
                let screenHeight = targetScreen.frame.height
                let screenOrigin = targetScreen.frame.origin
                if let region = baseRegion {
                    // baseRegion is in global NSWindow coordinates (bottom-left origin)
                    // Convert to window-local coordinates (top-left origin for SwiftUI)
                    let localX = region.origin.x - screenOrigin.x
                    let localY = screenHeight - (region.origin.y - screenOrigin.y) - region.height
                    viewModel.holeRect = CGRect(x: localX, y: localY, width: region.width, height: region.height)
                } else {
                    // Full screen - no dimming (hole covers entire window)
                    viewModel.holeRect = CGRect(origin: .zero, size: targetScreen.frame.size)
                }
            }

            // Windows already shown at start, just ensure they're on top
            self.overlayWindow?.orderFrontRegardless()
            self.dimmingWindow?.orderFrontRegardless()

            // Setup subtitle window AFTER stream starts (so it IS captured in recording)
            if zoomSettings.subtitlesEnabled {
                setupSubtitleWindow()
                updateSubtitlePosition()
                subtitleWindow?.orderFrontRegardless()
            }

            startZoomTimer()
            
            withAnimation {
                state = .recording
            }
            print("Recording started.")
            
        } catch {
            print("Failed to start capture: \(error)")
            state = .error(error)
            cleanupWindows()
            stopZoomTimer()
            
            // Allow user to see error briefly or just reset
            try? await Task.sleep(nanoseconds: 1 * 1_000_000_000)
            state = .idle
        }
    }
    
    @MainActor
    func stopCapture() async {
        guard case .recording = state else { return }

        // Change state immediately to block new start requests
        state = .stopping
        stopZoomTimer()
        KeyboardMonitor.shared.stopMonitoring()
        cleanupWindows() // Hide windows immediately for better UX

        let activeStream = self.stream
        self.stream = nil // Detach stream reference

        // Capture references before queue operation
        let writer = self.assetWriter
        let input = self.videoInput
        let outputURL = writer?.outputURL

        do {
            if let s = activeStream {
                try await s.stopCapture()
            }

            // Close writer on queue
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                writingQueue.async { [weak self] in
                    defer {
                        continuation.resume()
                    }

                    // Set stopping flag first
                    self?.isStopping = true

                    guard let writer = writer else { return }

                    if writer.status == .writing {
                        input?.markAsFinished()
                        let semaphore = DispatchSemaphore(value: 0)
                        writer.finishWriting {
                            semaphore.signal()
                        }
                        _ = semaphore.wait(timeout: .now() + 5.0)
                    } else if writer.status != .completed {
                        // If we never started writing or errored, cancel
                        writer.cancelWriting()
                    }
                }
            }

            // Cleanup references on main thread
            self.assetWriter = nil
            self.videoInput = nil
            self.pixelBufferAdaptor = nil
            self.isWritingSessionStarted = false
            self.isStopping = false

            withAnimation {
                state = .idle
            }

            if let url = outputURL {
                print("Recording finished: \(url.path)")
            }

        } catch {
            print("Failed to stop capture: \(error)")
            // Cleanup on error too
            self.assetWriter = nil
            self.videoInput = nil
            self.pixelBufferAdaptor = nil
            self.isWritingSessionStarted = false
            self.isStopping = false
            state = .error(error)
        }
    }
    
    // MARK: - Internal
    
    private func setupAssetWriter(width: Int, height: Int) throws {
        let evenWidth = (width >> 1) << 1
        let evenHeight = (height >> 1) << 1

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let fileName = "Recording_\(timestamp).mov"
        let fileURL = zoomSettings.effectiveOutputDirectory.appendingPathComponent(fileName)

        let writer = try AVAssetWriter(outputURL: fileURL, fileType: .mov)

        // Calculate bitrate based on quality (0.5 = 2x, 0.8 = 4x, 1.0 = 6x of base)
        let baseBitrate = evenWidth * evenHeight
        let qualityMultiplier = 2.0 + (zoomSettings.videoQuality * 4.0) // 2x to 6x
        let bitrate = Int(Double(baseBitrate) * qualityMultiplier)
        let frameRate = zoomSettings.frameRate

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: evenWidth,
            AVVideoHeightKey: evenHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoMaxKeyFrameIntervalKey: frameRate
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        // Create pixel buffer adaptor for handling CVPixelBuffer from ScreenCaptureKit
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: evenWidth,
            kCVPixelBufferHeightKey as String: evenHeight
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        if writer.canAdd(input) {
            writer.add(input)
        } else {
            throw NSError(domain: "app", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cant add input"])
        }

        // Start writing immediately to transition state to 'writing'
        // Session will be started when first frame arrives
        if !writer.startWriting() {
            throw writer.error ?? NSError(domain: "app", code: -1, userInfo: [NSLocalizedDescriptionKey: "Start writing failed"])
        }

        self.assetWriter = writer
        self.videoInput = input
        self.pixelBufferAdaptor = adaptor
    }
    
    /// Create a transparent overlay window with standard configuration
    private func createOverlayWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        return window
    }

    private func setupOverlayWindow() {
        let window = createOverlayWindow(frame: NSRect(x: 0, y: 0, width: 100, height: 100))

        let viewModel = OverlayViewModel()
        viewModel.edgeMargin = zoomSettings.edgeMarginRatio
        viewModel.showSafeZone = zoomSettings.showSafeZone
        self.overlayViewModel = viewModel

        window.contentView = NSHostingView(rootView: DynamicRecordingOverlayView(viewModel: viewModel))
        self.overlayWindow = window
    }

    /// Get the screen containing the recording region
    private func getTargetScreen() -> NSScreen {
        if let region = baseRegion {
            let regionCenter = CGPoint(x: region.midX, y: region.midY)
            for screen in NSScreen.screens {
                if screen.frame.contains(regionCenter) {
                    return screen
                }
            }
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    private func setupDimmingWindow() {
        let screen = getTargetScreen()
        let window = createOverlayWindow(frame: screen.frame)

        let viewModel = DimmingViewModel()
        viewModel.holeRect = CGRect(origin: .zero, size: screen.frame.size)
        viewModel.screenOrigin = screen.frame.origin
        self.dimmingViewModel = viewModel

        window.contentView = NSHostingView(rootView: DimmingView(viewModel: viewModel))
        self.dimmingWindow = window
    }

    private func setupSubtitleWindow() {
        let targetScreen = getTargetScreen()
        let regionFrame = baseRegion ?? targetScreen.frame

        let window = createOverlayWindow(frame: CGRect(
            x: regionFrame.origin.x,
            y: regionFrame.origin.y,
            width: regionFrame.width,
            height: 80
        ))

        let viewModel = SubtitleViewModel()
        viewModel.fontSize = zoomSettings.subtitleFontSize
        viewModel.backgroundOpacity = zoomSettings.subtitleBackgroundOpacity
        self.subtitleViewModel = viewModel

        window.contentView = NSHostingView(rootView: SubtitleView(viewModel: viewModel))
        self.subtitleWindow = window
    }

    private func updateSubtitlePosition() {
        guard let window = subtitleWindow else { return }
        let targetScreen = getTargetScreen()

        // Use baseRegion if set, otherwise use full screen
        let regionFrame: CGRect
        if let region = baseRegion {
            regionFrame = region
        } else {
            regionFrame = targetScreen.frame
        }

        // Position at bottom or top of recording region
        let subtitleHeight: CGFloat = 80
        let margin: CGFloat = 20
        let yPosition: CGFloat
        if zoomSettings.subtitlePosition == 0 {
            // Bottom of recording region
            yPosition = regionFrame.origin.y + margin
        } else {
            // Top of recording region
            yPosition = regionFrame.origin.y + regionFrame.height - subtitleHeight - margin
        }

        window.setFrame(CGRect(x: regionFrame.origin.x,
                               y: yPosition,
                               width: regionFrame.width,
                               height: subtitleHeight), display: true)
    }

    private func cleanupWindows() {
        overlayWindow?.close()
        overlayWindow = nil
        overlayViewModel = nil
        dimmingWindow?.close()
        dimmingWindow = nil
        dimmingViewModel = nil
        subtitleWindow?.close()
        subtitleWindow = nil
        subtitleViewModel = nil
    }
    
    private func updateOverlaySize() {
        guard let window = overlayWindow else { return }
        let zoomWidth = displaySize.width / zoomScale
        let zoomHeight = displaySize.height / zoomScale
        window.setContentSize(NSSize(width: zoomWidth, height: zoomHeight))
    }
    
    // MARK: - Zoom Logic

    // MARK: Zoom Helper Types

    private struct ZoomTriggerResult {
        var isTriggered: Bool = false
        var position: CGPoint? = nil
        var source: String = ""
    }

    private struct ZoomParameters {
        var targetScale: CGFloat
        var targetPosition: CGPoint
        var zoomWidth: CGFloat
        var zoomHeight: CGFloat
        var shouldZoom: Bool
    }

    // MARK: Zoom Helper Methods

    /// Calculate the default center position (in display-local top-left origin coordinates)
    private func calculateDefaultCenter() -> CGPoint {
        if let region = baseRegion {
            let localX = region.midX - displayOrigin.x
            let localY = displaySize.height - (region.midY - displayOrigin.y)
            return CGPoint(x: localX, y: localY)
        }
        return CGPoint(x: displaySize.width / 2, y: displaySize.height / 2)
    }

    /// Check if a position is within the recording region
    private func isPositionInRegion(_ globalPos: CGPoint) -> (isInRegion: Bool, localPos: CGPoint) {
        let localPos = CGPoint(
            x: globalPos.x - displayOrigin.x,
            y: globalPos.y - displayOrigin.y
        )

        let displayBounds = CGRect(origin: .zero, size: displaySize)
        let isInDisplay = displayBounds.contains(localPos)

        let isInRegion: Bool
        if let region = baseRegion {
            let regionTopLeft = CGRect(
                x: region.origin.x - displayOrigin.x,
                y: displaySize.height - (region.origin.y - displayOrigin.y) - region.height,
                width: region.width,
                height: region.height
            )
            isInRegion = regionTopLeft.contains(localPos)
        } else {
            isInRegion = isInDisplay
        }

        return (isInRegion, localPos)
    }

    /// Detect zoom triggers (typing, double-click, text selection)
    private func detectZoomTrigger(settings: ZoomSettings) -> ZoomTriggerResult {
        var result = ZoomTriggerResult()

        // 1. Check typing trigger
        if settings.zoomOnTyping {
            if let typingPos = AccessibilityUtils.getTypingCursorPosition() {
                let (isInRegion, localPos) = isPositionInRegion(typingPos)
                if isInRegion {
                    result = ZoomTriggerResult(isTriggered: true, position: localPos, source: "typing")
                    return result
                }
            }
        }

        // 2. Check double-click trigger
        if settings.zoomOnDoubleClick {
            if InputMonitor.shared.isDoubleClickActive(within: settings.zoomHoldDuration) {
                if let doubleClickPos = InputMonitor.shared.getDoubleClickPosition() {
                    let (isInRegion, localPos) = isPositionInRegion(doubleClickPos)
                    if isInRegion {
                        result = ZoomTriggerResult(isTriggered: true, position: localPos, source: "doubleClick")
                        return result
                    }
                }
            }
        }

        // 3. Check text selection trigger
        if settings.zoomOnTextSelection {
            if InputMonitor.shared.isTextSelectionActive(within: settings.zoomHoldDuration) {
                if let selectionPos = AccessibilityUtils.getFocusedElementPosition() {
                    let (isInRegion, localPos) = isPositionInRegion(selectionPos)
                    if isInRegion {
                        result = ZoomTriggerResult(isTriggered: true, position: localPos, source: "textSelection")
                        return result
                    }
                }
            }
        }

        return result
    }

    /// Calculate zoom parameters based on current state
    private func calculateZoomParameters(
        settings: ZoomSettings,
        shouldZoom: Bool,
        defaultCenter: CGPoint
    ) -> ZoomParameters {
        let baseWidth = baseRegion?.width ?? displaySize.width
        let baseHeight = baseRegion?.height ?? displaySize.height

        let targetScale: CGFloat
        let targetZoomWidth: CGFloat
        let targetZoomHeight: CGFloat
        var targetPosition: CGPoint

        if shouldZoom {
            switch settings.zoomMode {
            case .scale:
                targetScale = max(settings.minZoomScale, min(settings.maxZoomScale, settings.zoomScale))
                targetZoomWidth = baseWidth / targetScale
                targetZoomHeight = baseHeight / targetScale

            case .frameSize:
                targetZoomWidth = min(settings.zoomFrameWidth, baseWidth)
                targetZoomHeight = min(settings.zoomFrameHeight, baseHeight)
                targetScale = baseWidth / targetZoomWidth
            }

            let offsetX = targetZoomWidth * settings.centerOffsetX
            let offsetY = targetZoomHeight * settings.centerOffsetY
            targetPosition = CGPoint(
                x: lockedTargetPosition.x + offsetX,
                y: lockedTargetPosition.y + offsetY
            )
        } else {
            targetScale = 1.0
            targetZoomWidth = baseWidth
            targetZoomHeight = baseHeight
            targetPosition = defaultCenter
        }

        return ZoomParameters(
            targetScale: targetScale,
            targetPosition: targetPosition,
            zoomWidth: targetZoomWidth,
            zoomHeight: targetZoomHeight,
            shouldZoom: shouldZoom
        )
    }

    /// Update overlay and dimming windows
    private func updateOverlayAndDimming(
        sourceRect: CGRect,
        isZoomActive: Bool,
        settings: ZoomSettings
    ) {
        let targetScreen = getTargetScreen()
        let screenHeight = targetScreen.frame.height
        let screenOrigin = targetScreen.frame.origin

        let windowY = screenOrigin.y + screenHeight - sourceRect.origin.y - sourceRect.height

        // Update overlay window
        if let window = self.overlayWindow {
            window.setFrame(NSRect(
                x: sourceRect.origin.x,
                y: windowY,
                width: sourceRect.width,
                height: sourceRect.height
            ), display: true)
            window.alphaValue = (settings.showOverlay && isZoomActive) ? 1.0 : 0.0
        }

        // Update overlay view model
        if let viewModel = self.overlayViewModel {
            viewModel.edgeMargin = settings.edgeMarginRatio
            viewModel.showSafeZone = settings.showSafeZone
        }

        // Update dimming
        if let viewModel = self.dimmingViewModel {
            if settings.showDimming && isZoomActive {
                viewModel.holeRect = sourceRect
            } else if settings.showDimming {
                if let region = baseRegion {
                    let localX = region.origin.x - screenOrigin.x
                    let localY = screenHeight - (region.origin.y - screenOrigin.y) - region.height
                    viewModel.holeRect = CGRect(x: localX, y: localY, width: region.width, height: region.height)
                } else {
                    viewModel.holeRect = CGRect(origin: .zero, size: targetScreen.frame.size)
                }
            } else {
                viewModel.holeRect = CGRect(origin: .zero, size: targetScreen.frame.size)
            }
        }
    }

    /// Update stream configuration
    private func updateStreamConfig(sourceRect: CGRect, showCursor: Bool) {
        guard let stream = stream else { return }

        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = Int(displaySize.width) * 2
        config.height = Int(displaySize.height) * 2
        config.showsCursor = showCursor

        stream.updateConfiguration(config) { error in
            if let error = error {
                print("Failed to update stream configuration: \(error.localizedDescription)")
            }
        }
    }

    /// Update subtitle display
    private func updateSubtitleDisplay(settings: ZoomSettings, sourceRect: CGRect, now: Date) {
        guard settings.subtitlesEnabled, let viewModel = subtitleViewModel else { return }

        if let typedText = InputMonitor.shared.getTypedBuffer() {
            if typedText != lastSubtitleText {
                lastSubtitleText = typedText
                viewModel.text = typedText
            }
            lastSubtitleUpdateTime = now
            viewModel.isVisible = true
        }

        let timeSinceLastUpdate = now.timeIntervalSince(lastSubtitleUpdateTime)
        if timeSinceLastUpdate > settings.subtitleDisplayDuration && viewModel.isVisible {
            viewModel.isVisible = false
            lastSubtitleText = ""
            InputMonitor.shared.clearTypedBuffer()
        }

        viewModel.fontSize = settings.subtitleFontSize
        viewModel.backgroundOpacity = settings.subtitleBackgroundOpacity

        // Update subtitle window position
        if let window = subtitleWindow {
            let targetScreen = getTargetScreen()
            let screenHeight = targetScreen.frame.height
            let screenOrigin = targetScreen.frame.origin
            let subtitleHeight: CGFloat = 80
            let margin: CGFloat = 10

            let subtitleY: CGFloat
            if settings.subtitlePosition == 0 {
                subtitleY = screenOrigin.y + screenHeight - sourceRect.origin.y - sourceRect.height + margin
            } else {
                subtitleY = screenOrigin.y + screenHeight - sourceRect.origin.y - subtitleHeight - margin
            }

            window.setFrame(CGRect(
                x: screenOrigin.x + sourceRect.origin.x,
                y: subtitleY,
                width: sourceRect.width,
                height: subtitleHeight
            ), display: false)
        }
    }

    private func startZoomTimer() {
        // Ensure timer runs on main thread for UI updates
        DispatchQueue.main.async { [weak self] in
            self?.timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
                self?.updateZoom()
            }
            // Add to common run loop mode to ensure it runs during tracking
            if let timer = self?.timer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }
    
    private func stopZoomTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private var lastLogTime: Date = .distantPast

    private func updateZoom() {
        let now = Date()
        let settings = zoomSettings
        let defaultCenter = calculateDefaultCenter()

        // Handle smart zoom disabled case
        if !settings.smartZoomEnabled {
            if now.timeIntervalSince(lastUpdateTimestamp) > 0.033 {
                updateStreamConfig(sourceRect: CGRect(origin: .zero, size: displaySize), showCursor: settings.showCursor)
                lastUpdateTimestamp = now
            }
            overlayWindow?.alphaValue = 0.0
            updateOverlayAndDimming(
                sourceRect: CGRect(origin: .zero, size: displaySize),
                isZoomActive: false,
                settings: settings
            )
            return
        }

        // Detect zoom triggers
        let trigger = detectZoomTrigger(settings: settings)

        #if DEBUG
        if trigger.isTriggered && now.timeIntervalSince(lastLogTime) > 1.0 {
            print("[Zoom] Trigger: \(trigger.source), position: \(trigger.position ?? .zero)")
            lastLogTime = now
        }
        #endif

        // Update trigger timestamp
        if trigger.isTriggered {
            lastTypingDetectedTime = now
        }

        // Determine if zoom should be active
        let timeSinceLastTrigger = now.timeIntervalSince(lastTypingDetectedTime)
        let shouldZoom = trigger.isTriggered || (timeSinceLastTrigger < settings.zoomHoldDuration && isZoomActive)

        // Update zoom active state
        if trigger.isTriggered && !isZoomActive {
            isZoomActive = true
            if let pos = trigger.position {
                lockedTargetPosition = pos
                lastPositionChangeTime = now
            }
        } else if !shouldZoom && isZoomActive {
            isZoomActive = false
        }

        // Calculate zoom parameters
        let params = calculateZoomParameters(settings: settings, shouldZoom: shouldZoom, defaultCenter: defaultCenter)
        isTypingDetected = shouldZoom

        // Smooth interpolation
        currentSmoothScale += (params.targetScale - currentSmoothScale) * settings.scaleSmoothing
        lastTargetPosition.x += (params.targetPosition.x - lastTargetPosition.x) * settings.positionSmoothing
        lastTargetPosition.y += (params.targetPosition.y - lastTargetPosition.y) * settings.positionSmoothing

        // Calculate active zoom dimensions
        let baseWidth = baseRegion?.width ?? displaySize.width
        let baseHeight = baseRegion?.height ?? displaySize.height
        let activeZoomWidth: CGFloat
        let activeZoomHeight: CGFloat

        switch settings.zoomMode {
        case .scale:
            activeZoomWidth = baseWidth / currentSmoothScale
            activeZoomHeight = baseHeight / currentSmoothScale
        case .frameSize:
            let targetW = shouldZoom ? min(settings.zoomFrameWidth, baseWidth) : baseWidth
            let targetH = shouldZoom ? min(settings.zoomFrameHeight, baseHeight) : baseHeight
            let progress = (currentSmoothScale - 1.0) / (params.targetScale - 1.0 + 0.001)
            let clampedProgress = max(0, min(1, progress))
            activeZoomWidth = baseWidth + (targetW - baseWidth) * clampedProgress
            activeZoomHeight = baseHeight + (targetH - baseHeight) * clampedProgress
        }

        // Calculate source rect
        var sourceX = lastTargetPosition.x - activeZoomWidth / 2
        var sourceY = lastTargetPosition.y - activeZoomHeight / 2
        sourceX = max(0, min(sourceX, displaySize.width - activeZoomWidth))
        sourceY = max(0, min(sourceY, displaySize.height - activeZoomHeight))

        let newSourceRect = CGRect(x: sourceX, y: sourceY, width: activeZoomWidth, height: activeZoomHeight)
        currentSourceRect = newSourceRect

        // Handle edge margin repositioning
        if let pos = trigger.position, isZoomActive {
            let timeSinceLastMove = now.timeIntervalSince(lastPositionChangeTime)
            let marginX = activeZoomWidth * settings.edgeMarginRatio
            let marginY = activeZoomHeight * settings.edgeMarginRatio

            let safeLeft = sourceX + marginX
            let safeRight = sourceX + activeZoomWidth - marginX
            let safeTop = sourceY + marginY
            let safeBottom = sourceY + activeZoomHeight - marginY

            let isOutsideSafeZone = pos.x < safeLeft || pos.x > safeRight || pos.y < safeTop || pos.y > safeBottom

            #if DEBUG
            if now.timeIntervalSince(lastLogTime) > 0.5 {
                print("[Edge] cursor=(\(Int(pos.x)),\(Int(pos.y))) | outside=\(isOutsideSafeZone)")
                lastLogTime = now
            }
            #endif

            if isOutsideSafeZone && timeSinceLastMove > settings.positionHoldDuration {
                #if DEBUG
                print("[Edge] REPOSITION triggered!")
                #endif
                lockedTargetPosition = pos
                lastPositionChangeTime = now
            }
        }

        // Update UI
        updateOverlayAndDimming(sourceRect: newSourceRect, isZoomActive: isZoomActive, settings: settings)

        // Update stream (throttled)
        if now.timeIntervalSince(lastUpdateTimestamp) > 0.033 {
            updateStreamConfig(sourceRect: currentSourceRect, showCursor: settings.showCursor)
            lastUpdateTimestamp = now
        }

        // Update subtitles
        updateSubtitleDisplay(settings: settings, sourceRect: newSourceRect, now: now)
    }

    // MARK: - Output
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }

        // Pass to writing queue
        writingQueue.async { [weak self] in
            guard let self = self else { return }

            // 1. Check stopping flag first
            if self.isStopping { return }

            // 2. Check writer state
            guard let writer = self.assetWriter,
                  let input = self.videoInput,
                  let adaptor = self.pixelBufferAdaptor else { return }

            if writer.status == .failed {
                if let error = writer.error as NSError? {
                    print("Writer failed: \(error.localizedDescription), code: \(error.code), domain: \(error.domain)")
                } else {
                    print("Writer failed: unknown error")
                }
                return
            }

            if writer.status == .completed || writer.status == .cancelled {
                return
            }

            // 3. Validate Buffer and get pixel buffer
            guard CMSampleBufferDataIsReady(sampleBuffer), CMSampleBufferIsValid(sampleBuffer) else { return }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            // 4. Start Session if needed (startWriting already called in setupAssetWriter)
            if !self.isWritingSessionStarted && writer.status == .writing {
                writer.startSession(atSourceTime: presentationTime)
                self.isWritingSessionStarted = true
                print("AVAssetWriter session started at \(presentationTime.seconds)")
            }

            // 5. Append using pixel buffer adaptor
            if self.isWritingSessionStarted && input.isReadyForMoreMediaData {
                if !adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                    if let error = writer.error as NSError? {
                        print("Failed to append buffer: \(error.localizedDescription), code: \(error.code)")
                    }
                }
            }
        }
    }
}

extension ScreenRecorder: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Stream stop error: \(error)")
    }
}

// MARK: - Overlay View Model
class OverlayViewModel: ObservableObject {
    @Published var edgeMargin: CGFloat = 0.1
    @Published var showSafeZone: Bool = true
}

// MARK: - Dynamic Recording Overlay View
struct DynamicRecordingOverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        RecordingOverlayView(scale: 1.0, edgeMargin: viewModel.edgeMargin, showSafeZone: viewModel.showSafeZone)
    }
}

// MARK: - Dimming View Model
class DimmingViewModel: ObservableObject {
    @Published var holeRect: CGRect = .zero
    var screenOrigin: CGPoint = .zero // For coordinate conversion
}

// MARK: - Dimming View
struct DimmingView: View {
    @ObservedObject var viewModel: DimmingViewModel

    var body: some View {
        Canvas { context, size in
            // Draw semi-transparent black over everything
            let fullRect = CGRect(origin: .zero, size: size)

            // Create a path with a hole
            var path = Path(fullRect)
            path.addRect(viewModel.holeRect)

            context.fill(path, with: .color(.black.opacity(0.3)), style: FillStyle(eoFill: true))
        }
        .edgesIgnoringSafeArea(.all)
    }
}

// MARK: - Subtitle View Model
class SubtitleViewModel: ObservableObject {
    @Published var text: String = ""
    @Published var isVisible: Bool = false
    @Published var fontSize: CGFloat = 24
    @Published var backgroundOpacity: CGFloat = 0.7
}

// MARK: - Subtitle View
struct SubtitleView: View {
    @ObservedObject var viewModel: SubtitleViewModel

    var body: some View {
        HStack {
            Spacer()
            if viewModel.isVisible && !viewModel.text.isEmpty {
                Text(viewModel.text)
                    .font(.system(size: viewModel.fontSize, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(viewModel.backgroundOpacity))
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .animation(.easeInOut(duration: 0.2), value: viewModel.text)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isVisible)
    }
}

