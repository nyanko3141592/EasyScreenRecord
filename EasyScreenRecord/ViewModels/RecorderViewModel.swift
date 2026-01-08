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
        
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        let width: CGFloat = 800
        let height: CGFloat = 600
        
        let window = NSWindow(
            contentRect: NSRect(x: (screen.width - width) / 2, y: (screen.height - height) / 2, width: width, height: height),
            styleMask: [.titled, .resizable, .closable, .borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "Select Recording Area"
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        
        let contentView = NSHostingView(rootView: RegionSelectorView(viewModel: self))
        window.contentView = contentView
        
        window.makeKeyAndOrderFront(nil)
        self.selectionWindow = window
    }
    
    func setFullScreen() {
        if isRecording { return }
        recorder.setBaseRegion(nil)
        isSelectingRegion = false
        selectionWindow?.close()
        selectionWindow = nil
    }
    
    func confirmSelection() {
        guard let window = selectionWindow else { return }

        // Capture frame BEFORE closing
        let frame = window.frame

        // Convert screen coordinates (bottom-left) to display coordinates if needed.
        // ScreenCaptureKit uses top-left origin for sourceRect.
        // However, we handle the conversion in ScreenRecorder.updateZoom()

        recorder.setBaseRegion(frame)

        // Close window asynchronously to avoid issues with the button being inside the window
        self.selectionWindow = nil
        self.isSelectingRegion = false
        window.close()

        // Start recording automatically after confirming region selection
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
            // Already handled by startCapture if needed, 
            // but let's ensure we don't double call
            Task {
                await recorder.startCapture()
            }
        }
    }
}
