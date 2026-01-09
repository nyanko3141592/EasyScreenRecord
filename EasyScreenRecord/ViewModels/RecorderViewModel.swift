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

        guard let screen = NSScreen.main else { return }

        // Create full-screen window for selection
        let window = NSWindow(
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
        isSelectingRegion = false
        selectionWindow?.close()
        selectionWindow = nil
        selectionController = nil

        // Start recording automatically
        Task {
            await recorder.startCapture()
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
