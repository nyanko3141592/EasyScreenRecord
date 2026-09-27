import Foundation
import Combine
import SwiftUI
import AppKit

@MainActor
class RecorderViewModel: ObservableObject {
    @Published var recorder = ScreenRecorder()
    @Published var isRecording = false
    @Published var isSelectingRegion = false
    @Published var zoomScale: CGFloat = 2.0 {
        didSet {
            recorder.setZoomScale(zoomScale)
            recorder.zoomSettings.zoomScale = zoomScale
        }
    }

    private var selectionWindow: NSWindow?
    private var selectionController: RegionSelectorController?
    private var mosaicEditorWindow: NSWindow?
    private var keyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Sync recorder state to isRecording
        recorder.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                // Map state to boolean for UI
                if case .recording = state {
                    self?.isRecording = true
                } else if case .stopping = state {
                    self?.isRecording = true
                } else {
                    self?.isRecording = false
                }
            }
            .store(in: &cancellables)

        // Forward nested changes (recorder / settings) so menu bar items stay current
        recorder.objectWillChange
            .merge(with: recorder.zoomSettings.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Sync ZoomSettings.zoomScale back to viewModel
        recorder.zoomSettings.$zoomScale
            .receive(on: DispatchQueue.main)
            .sink { [weak self] scale in
                if self?.zoomScale != scale {
                    self?.zoomScale = scale
                }
            }
            .store(in: &cancellables)
    }

    func startSelection() {
        if isRecording { return }
        isSelectingRegion = true

        closeMosaicEditor()
        guard let screen = NSScreen.main else { return }

        // Create full-screen window for selection
        let window = makeFullScreenWindow(for: screen)

        // Create controller for selection logic
        let controller = RegionSelectorController()
        controller.zoomSettings = recorder.zoomSettings  // Pass settings for toggles
        controller.onConfirm = { [weak self] rect in
            self?.confirmSelectionWithRect(rect)
        }
        controller.onCancel = { [weak self] in
            self?.cancelSelection()
        }
        self.selectionController = controller
        installKeyMonitor(
            onEscape: { [weak controller] in controller?.handleEscape() },
            onReturn: { [weak controller] in controller?.handleReturn() }
        )

        let hostingView = NSHostingView(rootView: RegionSelectorOverlay(controller: controller))
        hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)
        window.contentView = hostingView

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)  // Ensure app is frontmost
        self.selectionWindow = window
    }

    func setFullScreen() {
        if isRecording { return }
        recorder.setBaseRegion(nil)
        cancelSelection()
    }

    func cancelSelection() {
        removeKeyMonitor()
        isSelectingRegion = false
        selectionWindow?.close()
        selectionWindow = nil
        selectionController = nil
    }

    private func confirmSelectionWithRect(_ rect: CGRect) {
        guard let screen = NSScreen.main else { return }

        // Convert from SwiftUI coordinates (top-left origin within window)
        // to NSWindow coordinates (bottom-left origin)
        // Note: baseRegion should be in screen-local coordinates (not global)
        let screenHeight = screen.frame.height

        // SwiftUI Y is from top, NSWindow Y is from bottom
        let convertedRect = CGRect(
            x: rect.origin.x,
            y: screenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )

        recorder.setBaseRegion(convertedRect)

        // Close selection window
        removeKeyMonitor()
        isSelectingRegion = false
        selectionWindow?.close()
        selectionWindow = nil
        selectionController = nil

        // Start recording automatically
        Task {
            await recorder.startCapture()
        }
    }

    // MARK: - Mosaic Editor (standalone, from the menu bar)

    func editMosaicRegions() {
        if isRecording || isSelectingRegion { return }
        closeMosaicEditor()
        guard let screen = NSScreen.main else { return }

        let window = makeFullScreenWindow(for: screen)
        let settings = recorder.zoomSettings
        let editor = MosaicEditorLayer(settings: settings, dimBackground: true) { [weak self] in
            self?.closeMosaicEditor()
        }
        let hostingView = NSHostingView(rootView: editor)
        hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)
        window.contentView = hostingView

        installKeyMonitor(
            onEscape: { [weak self] in self?.closeMosaicEditor() },
            onReturn: { [weak self] in self?.closeMosaicEditor() }
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mosaicEditorWindow = window
    }

    func closeMosaicEditor() {
        guard let window = mosaicEditorWindow else { return }
        removeKeyMonitor()
        window.close()
        mosaicEditorWindow = nil
    }

    // MARK: - Window helpers

    private func makeFullScreenWindow(for screen: NSScreen) -> NSWindow {
        let window = KeyableWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .screenSaver  // Above everything
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.ignoresMouseEvents = false  // Important: accept mouse events
        return window
    }

    /// ESC / Return handling that works regardless of which view has focus
    private func installKeyMonitor(onEscape: @escaping () -> Void, onReturn: @escaping () -> Void) {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 53: onEscape(); return nil        // Escape
            case 36, 76: onReturn(); return nil    // Return / Enter
            default: return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    func toggleRecording() {
        if isRecording {
            Task {
                await recorder.stopCapture()
            }
        } else {
            Task {
                await recorder.startCapture()
            }
        }
    }
}
