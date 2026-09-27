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

        // Record/Stop Button (at top)
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

            Divider()

            // Recording options
            Button {
                viewModel.recorder.zoomSettings.smartZoomEnabled.toggle()
            } label: {
                HStack {
                    Label("Smart Zoom", systemImage: "plus.magnifyingglass")
                    Spacer()
                    if viewModel.recorder.zoomSettings.smartZoomEnabled {
                        Image(systemName: "checkmark")
                    }
                }
            }

            // Mosaic
            Button {
                viewModel.recorder.zoomSettings.mosaicEnabled.toggle()
            } label: {
                HStack {
                    Label("モザイク (\(viewModel.recorder.zoomSettings.mosaicRegions.count)件)", systemImage: "square.grid.3x3.fill")
                    Spacer()
                    if viewModel.recorder.zoomSettings.mosaicEnabled {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Button {
                viewModel.editMosaicRegions()
            } label: {
                Label("モザイク範囲を設定...", systemImage: "plus.rectangle.on.rectangle")
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Button {
                viewModel.recorder.zoomSettings.subtitlesEnabled.toggle()
            } label: {
                HStack {
                    Label("自動字幕", systemImage: "captions.bubble")
                    Spacer()
                    if viewModel.recorder.zoomSettings.subtitlesEnabled {
                        Image(systemName: "checkmark")
                    }
                }
            }

            // Zoom settings (only if smart zoom is enabled)
            if viewModel.recorder.zoomSettings.smartZoomEnabled {
                Menu {
                    // Zoom mode selection
                    Button {
                        viewModel.recorder.zoomSettings.zoomMode = .scale
                    } label: {
                        HStack {
                            Text("倍率で指定")
                            if viewModel.recorder.zoomSettings.zoomMode == .scale {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Button {
                        viewModel.recorder.zoomSettings.zoomMode = .frameSize
                    } label: {
                        HStack {
                            Text("フレームサイズで指定")
                            if viewModel.recorder.zoomSettings.zoomMode == .frameSize {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()

                    if viewModel.recorder.zoomSettings.zoomMode == .scale {
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
                    } else {
                        ForEach([(400, 300), (640, 480), (800, 600), (1024, 768), (1280, 720)], id: \.0) { size in
                            Button {
                                viewModel.recorder.zoomSettings.zoomFrameWidth = CGFloat(size.0)
                                viewModel.recorder.zoomSettings.zoomFrameHeight = CGFloat(size.1)
                            } label: {
                                HStack {
                                    Text("\(size.0)×\(size.1)")
                                    if Int(viewModel.recorder.zoomSettings.zoomFrameWidth) == size.0 &&
                                       Int(viewModel.recorder.zoomSettings.zoomFrameHeight) == size.1 {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    if viewModel.recorder.zoomSettings.zoomMode == .scale {
                        Label("Zoom: \(String(format: "%.1fx", viewModel.zoomScale))", systemImage: "arrow.up.left.and.arrow.down.right")
                    } else {
                        Label("Zoom: \(Int(viewModel.recorder.zoomSettings.zoomFrameWidth))×\(Int(viewModel.recorder.zoomSettings.zoomFrameHeight))", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                }

                // Zoom Triggers submenu
                Menu {
                    Toggle("タイピング時", isOn: Binding(
                        get: { viewModel.recorder.zoomSettings.zoomOnTyping },
                        set: { viewModel.recorder.zoomSettings.zoomOnTyping = $0 }
                    ))
                    Toggle("ダブルクリック時", isOn: Binding(
                        get: { viewModel.recorder.zoomSettings.zoomOnDoubleClick },
                        set: { viewModel.recorder.zoomSettings.zoomOnDoubleClick = $0 }
                    ))
                    Toggle("テキスト選択時", isOn: Binding(
                        get: { viewModel.recorder.zoomSettings.zoomOnTextSelection },
                        set: { viewModel.recorder.zoomSettings.zoomOnTextSelection = $0 }
                    ))
                } label: {
                    Label("ズームトリガー", systemImage: "cursorarrow.click")
                }
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
        }

        // Reveal last recording
        if let lastURL = viewModel.recorder.lastRecordingURL {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([lastURL])
            } label: {
                Label("直前の録画を表示", systemImage: "film")
            }
        }

        // Open Output Folder (always available)
        Button {
            let url = viewModel.recorder.zoomSettings.effectiveOutputDirectory
            NSWorkspace.shared.open(url)
        } label: {
            Label("Open Output Folder", systemImage: "folder")
        }

        Divider()

        Button("Quit EasyScreenRecord") {
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
        .frame(width: 360, height: 560)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).ignoresSafeArea())
    }
}
