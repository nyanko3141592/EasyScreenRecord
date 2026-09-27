import SwiftUI
import AppKit

// MARK: - Keyable borderless window

/// Borderless windows can't become key by default, which silently drops ESC / Return.
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Mosaic pattern (visual stand-in for the real mosaic)

struct MosaicPatternView: View {
    var cell: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            let cols = Int(ceil(size.width / cell))
            let rows = Int(ceil(size.height / cell))
            for row in 0..<rows {
                for col in 0..<cols {
                    // Deterministic pseudo-random grey per cell
                    let seed = (row &* 73856093) ^ (col &* 19349663)
                    let shade = 0.35 + Double(abs(seed) % 40) / 100.0
                    let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(Color(white: shade)))
                }
            }
        }
    }
}

/// A single mosaic region drawn in screen space.
struct MosaicRegionShape: View {
    let rect: CGRect
    var index: Int? = nil
    var opacity: Double = 0.85
    var onDelete: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MosaicPatternView(cell: 10)
                .opacity(opacity)
                .overlay(
                    Rectangle()
                        .strokeBorder(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                )
                .overlay(alignment: .topLeading) {
                    if let index {
                        Text("モザイク \(index + 1)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(4)
                    }
                }
                .allowsHitTesting(false)

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                        .shadow(radius: 2)
                }
                .buttonStyle(.plain)
                .help("この範囲を削除")
                .offset(x: 10, y: -10)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }
}

/// Read-only preview of all registered mosaic regions.
struct MosaicRegionsPreview: View {
    @ObservedObject var settings: ZoomSettings

    var body: some View {
        ZStack {
            if settings.mosaicEnabled {
                ForEach(Array(settings.mosaicRegions.enumerated()), id: \.element.id) { index, region in
                    MosaicRegionShape(rect: region.rect, index: index)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

// MARK: - Mosaic Editor

/// Full-screen layer where the user drags out rectangles to be masked in the recording.
struct MosaicEditorLayer: View {
    @ObservedObject var settings: ZoomSettings
    /// Darken the screen (used when the editor is shown on its own)
    var dimBackground: Bool = true
    let onDone: () -> Void

    @State private var dragStart: CGPoint = .zero
    @State private var draftRect: CGRect?

    private let minimumSize: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if dimBackground {
                    Color.black.opacity(0.35).allowsHitTesting(false)
                }

                // Drag-to-create layer (AppKit, handles ESC / Return too)
                MouseTrackingView(
                    onDragStart: { point in
                        dragStart = point
                        draftRect = CGRect(origin: point, size: .zero)
                    },
                    onDragUpdate: { point in
                        let clamped = CGPoint(
                            x: min(max(point.x, 0), geo.size.width),
                            y: min(max(point.y, 0), geo.size.height)
                        )
                        draftRect = CGRect(
                            x: min(dragStart.x, clamped.x),
                            y: min(dragStart.y, clamped.y),
                            width: abs(clamped.x - dragStart.x),
                            height: abs(clamped.y - dragStart.y)
                        )
                    },
                    onDragEnd: {
                        if let rect = draftRect, rect.width >= minimumSize, rect.height >= minimumSize {
                            settings.mosaicRegions.append(MosaicRegion(rect: rect.integral))
                            settings.mosaicEnabled = true
                        }
                        draftRect = nil
                    },
                    onCancel: onDone,
                    onConfirm: onDone
                )
                .frame(width: geo.size.width, height: geo.size.height)

                ForEach(Array(settings.mosaicRegions.enumerated()), id: \.element.id) { index, region in
                    MosaicRegionShape(rect: region.rect, index: index, onDelete: {
                        settings.mosaicRegions.removeAll { $0.id == region.id }
                    })
                }

                if let draftRect, draftRect.width > 0, draftRect.height > 0 {
                    MosaicRegionShape(rect: draftRect, opacity: 0.6)
                    Text("\(Int(draftRect.width)) x \(Int(draftRect.height))")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .position(x: draftRect.midX, y: max(12, draftRect.minY - 20))
                        .allowsHitTesting(false)
                }

                VStack {
                    MosaicToolbar(settings: settings, onDone: onDone)
                        .padding(.top, 60)
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Floating toolbar for the mosaic editor.
struct MosaicToolbar: View {
    @ObservedObject var settings: ZoomSettings
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("ドラッグでモザイク範囲を追加 ・ ✕で削除 ・ Enter/ESCで完了")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }

            HStack(spacing: 14) {
                Picker("", selection: $settings.mosaicStyle) {
                    ForEach(MosaicStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)

                HStack(spacing: 6) {
                    Text("粗さ")
                        .font(.system(size: 12, weight: .medium))
                    Slider(value: $settings.mosaicBlockSize, in: 6...48, step: 2)
                        .frame(width: 100)
                    Text("\(Int(settings.mosaicBlockSize))")
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 22, alignment: .trailing)
                }
                .disabled(settings.mosaicStyle == .fill)

                Button("すべて削除") {
                    settings.mosaicRegions.removeAll()
                }
                .disabled(settings.mosaicRegions.isEmpty)

                Button(action: onDone) {
                    Text("完了 (\(settings.mosaicRegions.count)件)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
    }
}

// MARK: - Recording-time outline

/// Dashed outlines of mosaic regions shown on screen while recording.
/// The window hosting this is excluded from capture, so it never appears in the video.
struct MosaicOutlineView: View {
    @ObservedObject var settings: ZoomSettings

    var body: some View {
        ZStack {
            ForEach(settings.mosaicRegions) { region in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .strokeBorder(Color.orange.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(3)
                }
                .frame(width: region.rect.width, height: region.rect.height)
                .position(x: region.rect.midX, y: region.rect.midY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
