import SwiftUI
import AppKit

@main
struct EasyScreenRecordApp: App {
    @StateObject private var viewModel = RecorderViewModel()
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Request Accessibility permission on app launch
        requestAccessibilityPermission()
    }

    private func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)

        #if DEBUG
        print("[Accessibility] Permission status: \(accessEnabled ? "granted" : "not granted")")
        #endif
    }

    var body: some Scene {
        // Settings Window
        Window("Settings", id: "settings") {
            SettingsWindowView(viewModel: viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        // Menu Bar
        MenuBarExtra {
            MenuBarContentView(viewModel: viewModel, openWindow: openWindow)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: viewModel.isRecording ? "record.circle.fill" : "video.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(viewModel.isRecording ? .red : .primary)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - menu bar only app
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Menu Bar Content View
struct MenuBarContentView: View {
    @ObservedObject var viewModel: RecorderViewModel
    let openWindow: OpenWindowAction

    var body: some View {
        // Status
        if viewModel.isRecording {
            HStack {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text("Recording...")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }

        // Record/Stop Button
        Button {
            if viewModel.isRecording {
                viewModel.toggleRecording()
            } else {
                viewModel.startSelection()
            }
        } label: {
            Label(
                viewModel.isRecording ? "Stop Recording" : "Start Recording",
                systemImage: viewModel.isRecording ? "stop.fill" : "record.circle"
            )
        }
        .keyboardShortcut("r", modifiers: .command)

        if !viewModel.isRecording {
            Button {
                viewModel.setFullScreen()
                viewModel.toggleRecording()
            } label: {
                Label("Record Full Screen", systemImage: "macwindow")
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }

        Divider()

        // Zoom Scale
        Menu {
            ForEach([1.5, 2.0, 2.5, 3.0, 4.0], id: \.self) { scale in
                Button {
                    viewModel.zoomScale = scale
                } label: {
                    HStack {
                        Text(String(format: "%.1fx", scale))
                        if viewModel.zoomScale == scale {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("Zoom: \(String(format: "%.1fx", viewModel.zoomScale))", systemImage: "plus.magnifyingglass")
        }

        // Presets
        Menu {
            Button("Smooth") {
                applyPreset(.smooth, to: viewModel.recorder.zoomSettings)
            }
            Button("Default") {
                applyPreset(.default, to: viewModel.recorder.zoomSettings)
            }
            Button("Fast") {
                applyPreset(.responsive, to: viewModel.recorder.zoomSettings)
            }
        } label: {
            Label("Presets", systemImage: "slider.horizontal.3")
        }

        Divider()

        // Settings
        Button {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        } label: {
            Label("Settings...", systemImage: "gearshape")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit EasyRecord") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func applyPreset(_ preset: ZoomSettings, to settings: ZoomSettings) {
        settings.scaleSmoothing = preset.scaleSmoothing
        settings.positionSmoothing = preset.positionSmoothing
        settings.edgeMarginRatio = preset.edgeMarginRatio
        settings.zoomHoldDuration = preset.zoomHoldDuration
        settings.positionHoldDuration = preset.positionHoldDuration
    }
}

// MARK: - Settings Window View
struct SettingsWindowView: View {
    @ObservedObject var viewModel: RecorderViewModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(.secondary)
                Text("EASY RECORD SETTINGS")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    dismissWindow(id: "settings")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color.black.opacity(0.1))

            // Settings Content
            ScrollView {
                ZoomSettingsView(settings: viewModel.recorder.zoomSettings)
                    .padding()
            }
        }
        .frame(width: 340, height: 480)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).ignoresSafeArea())
    }
}
