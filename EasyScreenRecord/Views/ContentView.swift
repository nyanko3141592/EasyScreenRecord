import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: RecorderViewModel
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 28) {
            // Header
            VStack(spacing: 4) {
                HStack {
                    Image(systemName: "record.circle.fill")
                        .foregroundStyle(.blue.gradient)
                        .font(.title3)
                    Text("EASY RECORD")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .kerning(1.2)
                    Spacer()
                    Button(action: openOutputFolder) {
                        Image(systemName: "folder")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("保存先フォルダを開く")
                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("設定")
                    Circle()
                        .fill(viewModel.isRecording ? Color.red : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                        .shadow(color: viewModel.isRecording ? .red.opacity(0.6) : .clear, radius: 5)
                }
                HStack {
                    Text("ZOOM ON FOCUS TOOL")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .kerning(1.0)
                    Spacer()
                }
            }
            .padding(.horizontal, 4)
            
            // Preview/Status Area
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.black.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                
                if viewModel.isRecording {
                    VStack(spacing: 12) {
                        Image(systemName: "dot.circle.and.cursorarrow")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.red)
                            .symbolEffect(.pulse, options: .repeating)
                        Text("RECORDING ACTIVE")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.red.opacity(0.8))
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.secondary.opacity(0.4))
                        Text("AWAITING START")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 140)

            // Zoom Control
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.caption)
                    Text("DYNAMIC ZOOM")
                        .font(.system(size: 10, weight: .heavy))
                    Spacer()
                    Text(String(format: "%.1fX", viewModel.zoomScale))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.blue)
                }
                Slider(value: $viewModel.zoomScale, in: 1.0...4.0, step: 0.1)
                    .tint(.blue)
            }
            .padding(.horizontal, 8)
            
            // Region Selection
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "scope")
                        .font(.caption)
                    Text("CAPTURE AREA")
                        .font(.system(size: 10, weight: .heavy))
                    Spacer()
                }
                
                HStack(spacing: 12) {
                    AreaButton(
                        icon: "macwindow",
                        title: "FULL SCREEN",
                        isSelected: viewModel.recorder.baseRegion == nil,
                        action: { viewModel.setFullScreen() }
                    )
                    
                    AreaButton(
                        icon: "viewfinder",
                        title: "CUSTOM REGION",
                        isSelected: viewModel.recorder.baseRegion != nil,
                        action: { viewModel.startSelection() }
                    )
                }
            }
            .padding(.horizontal, 4)
            .disabled(viewModel.isRecording)
            
            // Quick toggles (only when not recording)
            if !viewModel.isRecording {
                HStack(spacing: 16) {
                    // Smart Zoom toggle
                    Toggle(isOn: Binding(
                        get: { viewModel.recorder.zoomSettings.smartZoomEnabled },
                        set: { viewModel.recorder.zoomSettings.smartZoomEnabled = $0 }
                    )) {
                        Label("Zoom", systemImage: "plus.magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .tint(viewModel.recorder.zoomSettings.smartZoomEnabled ? .blue : .gray)

                    // Subtitles toggle
                    Toggle(isOn: Binding(
                        get: { viewModel.recorder.zoomSettings.subtitlesEnabled },
                        set: { viewModel.recorder.zoomSettings.subtitlesEnabled = $0 }
                    )) {
                        Label("字幕", systemImage: "captions.bubble")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .tint(viewModel.recorder.zoomSettings.subtitlesEnabled ? .blue : .gray)
                }
                .padding(.horizontal, 4)
            }

            // Primary Controls
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    viewModel.toggleRecording()
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: viewModel.isRecording ? "stop.fill" : "record.circle.fill")
                        .font(.title2)
                    Text(viewModel.isRecording ? "STOP RECORDING" : "START RECORDING")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    ZStack {
                        if viewModel.isRecording {
                            Color.red.opacity(0.8)
                        } else {
                            LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: (viewModel.isRecording ? Color.red : Color.blue).opacity(0.3), radius: 15, y: 8)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.recorder.isBusy)
            .opacity(viewModel.recorder.isBusy ? 0.6 : 1.0)

            // Settings Panel (collapsible)
            if showSettings {
                ZoomSettingsView(settings: viewModel.recorder.zoomSettings)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(32)
        .frame(width: 360)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).ignoresSafeArea())
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showSettings)
    }

    private func openOutputFolder() {
        let url = viewModel.recorder.zoomSettings.effectiveOutputDirectory
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Zoom Settings View (macOS Native Style)
struct ZoomSettingsView: View {
    @ObservedObject var settings: ZoomSettings
    @State private var showAdvanced = false

    var body: some View {
        Form {
            // 一般
            Section {
                Toggle("Smart Zoom", isOn: $settings.smartZoomEnabled)

                if settings.smartZoomEnabled {
                    LabeledContent("ズーム方式") {
                        Picker("", selection: Binding(
                            get: { settings.zoomMode.rawValue },
                            set: { settings.zoomMode = ZoomSettings.ZoomMode(rawValue: $0) ?? .scale }
                        )) {
                            Text("倍率").tag(0)
                            Text("サイズ").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                    }

                    if settings.zoomMode == .scale {
                        LabeledContent("ズーム倍率") {
                            HStack {
                                Text(String(format: "%.1fx", settings.zoomScale))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Stepper("", value: $settings.zoomScale, in: 1.5...5.0, step: 0.5)
                                    .labelsHidden()
                            }
                        }
                    } else {
                        LabeledContent("フレーム幅") {
                            HStack {
                                Text("\(Int(settings.zoomFrameWidth))px")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, alignment: .trailing)
                                Stepper("", value: $settings.zoomFrameWidth, in: 200...1920, step: 100)
                                    .labelsHidden()
                            }
                        }

                        LabeledContent("フレーム高さ") {
                            HStack {
                                Text("\(Int(settings.zoomFrameHeight))px")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, alignment: .trailing)
                                Stepper("", value: $settings.zoomFrameHeight, in: 200...1080, step: 100)
                                    .labelsHidden()
                            }
                        }
                    }

                    LabeledContent("プリセット") {
                        Picker("", selection: Binding(
                            get: { presetName },
                            set: { applyPresetByName($0) }
                        )) {
                            Text("滑らか").tag("smooth")
                            Text("標準").tag("default")
                            Text("高速").tag("responsive")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }

                    // Zoom Triggers
                    Divider()

                    Toggle("タイピング時", isOn: $settings.zoomOnTyping)
                    Toggle("ダブルクリック時", isOn: $settings.zoomOnDoubleClick)
                    Toggle("テキスト選択時", isOn: $settings.zoomOnTextSelection)
                }
            } header: {
                Text("一般")
            } footer: {
                if settings.smartZoomEnabled {
                    Text("ズームするタイミングを選択できます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // モザイク
            Section {
                Toggle("モザイクを有効にする", isOn: $settings.mosaicEnabled)

                LabeledContent("スタイル") {
                    Picker("", selection: $settings.mosaicStyle) {
                        ForEach(MosaicStyle.allCases, id: \.self) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                if settings.mosaicStyle != .fill {
                    LabeledContent("粗さ") {
                        HStack {
                            Slider(value: $settings.mosaicBlockSize, in: 6...48, step: 2)
                                .frame(width: 100)
                            Text("\(Int(settings.mosaicBlockSize))pt")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }

                LabeledContent("範囲") {
                    HStack {
                        Text("\(settings.mosaicRegions.count)件")
                            .foregroundStyle(.secondary)
                        Button("すべて削除") {
                            settings.mosaicRegions.removeAll()
                        }
                        .disabled(settings.mosaicRegions.isEmpty)
                    }
                }
            } header: {
                Text("モザイク")
            } footer: {
                Text("範囲はメニューの「モザイク範囲を設定...」または録画範囲の選択画面で指定します。モザイクは録画ファイルにのみ焼き込まれ、画面上では枠だけが表示されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 録画
            Section {
                LabeledContent("保存先") {
                    HStack {
                        Text(settings.outputDirectory?.lastPathComponent ?? "ムービー")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Button("変更...") {
                            selectOutputDirectory()
                        }
                    }
                }

                LabeledContent("フレームレート") {
                    Picker("", selection: $settings.frameRate) {
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }

                Toggle("カーソルを表示", isOn: $settings.showCursor)
            } header: {
                Text("録画")
            }

            // 字幕
            Section {
                Toggle("自動字幕", isOn: $settings.subtitlesEnabled)

                if settings.subtitlesEnabled {
                    LabeledContent("フォントサイズ") {
                        HStack {
                            Text("\(Int(settings.subtitleFontSize))pt")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Stepper("", value: $settings.subtitleFontSize, in: 16...48, step: 4)
                                .labelsHidden()
                        }
                    }

                    LabeledContent("表示位置") {
                        Picker("", selection: $settings.subtitlePosition) {
                            Text("下").tag(0)
                            Text("上").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 80)
                    }

                    LabeledContent("表示時間") {
                        HStack {
                            Text(String(format: "%.1f秒", settings.subtitleDisplayDuration))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Stepper("", value: $settings.subtitleDisplayDuration, in: 1.0...5.0, step: 0.5)
                                .labelsHidden()
                        }
                    }

                    Toggle("修飾キーを表示", isOn: $settings.showModifierKeys)
                }
            } header: {
                Text("字幕")
            } footer: {
                Text("入力中のテキストを自動で字幕表示します。修飾キーを有効にすると [⌘C] のようにショートカットも表示されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 高度な設定
            Section(isExpanded: $showAdvanced) {
                if settings.smartZoomEnabled {
                    // 追従
                    LabeledContent("セーフゾーン") {
                        HStack {
                            Text("\(Int(settings.edgeMarginRatio * 100))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                            Slider(value: $settings.edgeMarginRatio, in: 0.05...0.4, step: 0.05)
                                .frame(width: 100)
                        }
                    }

                    LabeledContent("ズーム維持時間") {
                        HStack {
                            Text(String(format: "%.1f秒", settings.zoomHoldDuration))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Stepper("", value: $settings.zoomHoldDuration, in: 0.5...5.0, step: 0.5)
                                .labelsHidden()
                        }
                    }

                    LabeledContent("追従の滑らかさ") {
                        HStack {
                            Text("滑らか")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: $settings.positionSmoothing, in: 0.01...0.2, step: 0.01)
                                .frame(width: 80)
                            Text("速い")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // オーバーレイ
                    Toggle("録画範囲の枠を表示", isOn: $settings.showOverlay)
                    Toggle("セーフゾーンを表示", isOn: $settings.showSafeZone)
                    Toggle("範囲外を暗くする", isOn: $settings.showDimming)
                }

                LabeledContent("ビデオ品質") {
                    HStack {
                        Text("\(Int(settings.videoQuality * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                        Slider(value: $settings.videoQuality, in: 0.5...1.0, step: 0.1)
                            .frame(width: 100)
                    }
                }

                Button("すべての設定をリセット") {
                    settings.resetToDefaults()
                }
                .foregroundStyle(.red)
            } header: {
                Text("詳細")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxHeight: 480)
    }

    private var presetName: String {
        if settings.positionSmoothing < 0.06 { return "smooth" }
        if settings.positionSmoothing > 0.12 { return "responsive" }
        return "default"
    }

    private func applyPresetByName(_ name: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            switch name {
            case "smooth":
                applyPreset(.smooth)
            case "responsive":
                applyPreset(.responsive)
            default:
                applyPreset(.default)
            }
        }
    }

    private func applyPreset(_ preset: ZoomSettings) {
        settings.scaleSmoothing = preset.scaleSmoothing
        settings.positionSmoothing = preset.positionSmoothing
        settings.edgeMarginRatio = preset.edgeMarginRatio
        settings.zoomHoldDuration = preset.zoomHoldDuration
        settings.positionHoldDuration = preset.positionHoldDuration
    }

    private func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "選択"
        panel.message = "録画ファイルの保存先を選択してください"

        if panel.runModal() == .OK {
            settings.outputDirectory = panel.url
        }
    }
}

struct AreaButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.system(size: 9, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSelected ? Color.blue.opacity(0.15) : Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.white.opacity(0.1), lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

#Preview {
    ContentView(viewModel: RecorderViewModel())
}
