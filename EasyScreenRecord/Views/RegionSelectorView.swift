import SwiftUI
import AppKit
import Observation

// MARK: - Region Selector Window Controller
@Observable
class RegionSelectorController {
    var selectionRect: CGRect = .zero
    var isDragging = false
    var isAdjusting = false  // After initial drag, allow adjustments
    var activeHandle: ResizeHandle? = nil
    /// Mosaic region editing mode (drawn on top of the selection)
    var isEditingMosaic = false

    // Settings reference for toggles
    var zoomSettings: ZoomSettings?

    var onConfirm: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var dragStart: CGPoint = .zero
    private var initialRect: CGRect = .zero

    enum ResizeHandle {
        case topLeft, top, topRight
        case left, right
        case bottomLeft, bottom, bottomRight
        case move
    }

    func startDrag(at point: CGPoint) {
        if isAdjusting {
            // Check if clicking on a handle or inside the rect
            activeHandle = hitTest(point: point)
            if activeHandle != nil {
                dragStart = point
                initialRect = selectionRect
            }
        } else {
            // Initial selection drag
            isDragging = true
            dragStart = point
            selectionRect = CGRect(origin: point, size: .zero)
        }
    }

    func continueDrag(to point: CGPoint) {
        if isAdjusting, let handle = activeHandle {
            // Resize or move the selection
            let deltaX = point.x - dragStart.x
            let deltaY = point.y - dragStart.y

            var newRect = initialRect

            switch handle {
            case .move:
                newRect.origin.x += deltaX
                newRect.origin.y += deltaY
            case .topLeft:
                newRect.origin.x += deltaX
                newRect.origin.y += deltaY
                newRect.size.width -= deltaX
                newRect.size.height -= deltaY
            case .top:
                newRect.origin.y += deltaY
                newRect.size.height -= deltaY
            case .topRight:
                newRect.origin.y += deltaY
                newRect.size.width += deltaX
                newRect.size.height -= deltaY
            case .left:
                newRect.origin.x += deltaX
                newRect.size.width -= deltaX
            case .right:
                newRect.size.width += deltaX
            case .bottomLeft:
                newRect.origin.x += deltaX
                newRect.size.width -= deltaX
                newRect.size.height += deltaY
            case .bottom:
                newRect.size.height += deltaY
            case .bottomRight:
                newRect.size.width += deltaX
                newRect.size.height += deltaY
            }

            // Ensure minimum size
            if newRect.width >= 100 && newRect.height >= 100 {
                selectionRect = newRect
            }
        } else if isDragging {
            // Initial selection - create rect from drag start to current point
            let minX = min(dragStart.x, point.x)
            let minY = min(dragStart.y, point.y)
            let maxX = max(dragStart.x, point.x)
            let maxY = max(dragStart.y, point.y)
            selectionRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    func endDrag() {
        if isDragging {
            isDragging = false
            // If selection is big enough, switch to adjustment mode
            if selectionRect.width >= 50 && selectionRect.height >= 50 {
                isAdjusting = true
            } else {
                selectionRect = .zero
            }
        }
        activeHandle = nil
    }

    func hitTest(point: CGPoint) -> ResizeHandle? {
        let handleSize: CGFloat = 20
        let rect = selectionRect

        // Corner handles
        if CGRect(x: rect.minX - handleSize/2, y: rect.minY - handleSize/2, width: handleSize, height: handleSize).contains(point) {
            return .topLeft
        }
        if CGRect(x: rect.maxX - handleSize/2, y: rect.minY - handleSize/2, width: handleSize, height: handleSize).contains(point) {
            return .topRight
        }
        if CGRect(x: rect.minX - handleSize/2, y: rect.maxY - handleSize/2, width: handleSize, height: handleSize).contains(point) {
            return .bottomLeft
        }
        if CGRect(x: rect.maxX - handleSize/2, y: rect.maxY - handleSize/2, width: handleSize, height: handleSize).contains(point) {
            return .bottomRight
        }

        // Edge handles
        if CGRect(x: rect.midX - handleSize/2, y: rect.minY - handleSize/2, width: handleSize, height: handleSize).contains(point) {
            return .top
        }
        if CGRect(x: rect.midX - handleSize/2, y: rect.maxY - handleSize/2, width: handleSize, height: handleSize).contains(point) {
            return .bottom
        }
        if CGRect(x: rect.minX - handleSize/2, y: rect.midY - handleSize/2, width: handleSize, height: handleSize).contains(point) {
            return .left
        }
        if CGRect(x: rect.maxX - handleSize/2, y: rect.midY - handleSize/2, width: handleSize, height: handleSize).contains(point) {
            return .right
        }

        // Inside rect = move
        if rect.contains(point) {
            return .move
        }

        return nil
    }

    func confirm() {
        guard selectionRect.width >= 50 && selectionRect.height >= 50 else { return }
        onConfirm?(selectionRect)
    }

    func cancel() {
        onCancel?()
    }

    /// Keyboard routing (called from the selection window's key monitor)
    func handleEscape() {
        if isEditingMosaic {
            isEditingMosaic = false
        } else {
            cancel()
        }
    }

    func handleReturn() {
        if isEditingMosaic {
            isEditingMosaic = false
        } else if isAdjusting {
            confirm()
        }
    }
}

// MARK: - Full Screen Overlay View
struct RegionSelectorOverlay: View {
    var controller: RegionSelectorController
    @State private var selectionRect: CGRect = .zero
    @State private var isDragging = false
    @State private var isAdjusting = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dimmed background with hole for selection
                SelectionMaskView(rect: selectionRect, screenSize: geo.size)
                    .allowsHitTesting(false)

                // Registered mosaic regions (read-only preview)
                if let settings = controller.zoomSettings, !controller.isEditingMosaic {
                    MosaicRegionsPreview(settings: settings)
                }

                // Selection rectangle during dragging
                if selectionRect.width > 0 && selectionRect.height > 0 && !controller.isEditingMosaic {
                    if isAdjusting, let settings = controller.zoomSettings {
                        // Full SelectionRectView with buttons (clickable)
                        SelectionRectView(
                            rect: selectionRect,
                            isAdjusting: isAdjusting,
                            controller: controller,
                            settings: settings
                        )
                    } else {
                        // Simple selection rect during initial drag
                        Rectangle()
                            .stroke(Color.blue, lineWidth: 2)
                            .frame(width: selectionRect.width, height: selectionRect.height)
                            .position(x: selectionRect.midX, y: selectionRect.midY)
                            .allowsHitTesting(false)

                        // Size label
                        Text("\(Int(selectionRect.width)) x \(Int(selectionRect.height))")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .position(x: selectionRect.midX, y: selectionRect.minY - 20)
                            .allowsHitTesting(false)
                    }
                }

                // Instructions
                if !controller.isEditingMosaic {
                VStack {
                    if !isAdjusting && !isDragging {
                        InstructionBadge(text: "ドラッグで範囲を選択 (ESCでキャンセル)", icon: "rectangle.dashed")
                    } else if isDragging {
                        InstructionBadge(text: "離して範囲を確定", icon: "hand.draw")
                    } else if isAdjusting {
                        InstructionBadge(text: "Enterで録画開始 / ESCでキャンセル", icon: "keyboard")
                    }
                    Spacer()
                }
                .padding(.top, 60)
                .allowsHitTesting(false)
                }

                // Cancel button (always visible)
                Button(action: { controller.cancel() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .position(x: geo.size.width - 40, y: 40)

                // Mouse event handling layer - only active when NOT in adjustment mode
                if !isAdjusting {
                    MouseTrackingView(
                        onDragStart: { point in
                            controller.startDrag(at: point)
                            isDragging = true
                        },
                        onDragUpdate: { point in
                            if isDragging {
                                controller.continueDrag(to: point)
                                selectionRect = controller.selectionRect
                            }
                        },
                        onDragEnd: {
                            if isDragging {
                                controller.endDrag()
                                isDragging = false
                                isAdjusting = controller.isAdjusting
                                selectionRect = controller.selectionRect
                            }
                        },
                        onCancel: {
                            controller.cancel()
                        },
                        onConfirm: {
                            // Not used when not adjusting
                        }
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                }

                // Mosaic editor (on top of everything)
                if controller.isEditingMosaic, let settings = controller.zoomSettings {
                    MosaicEditorLayer(settings: settings, dimBackground: false) {
                        controller.isEditingMosaic = false
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onKeyPress(.escape) {
            controller.handleEscape()
            return .handled
        }
        .onKeyPress(.return) {
            controller.handleReturn()
            return .handled
        }
        .focusable()
        .focusEffectDisabled()
    }
}

// MARK: - Mouse Tracking View (AppKit-based)
struct MouseTrackingView: NSViewRepresentable {
    let onDragStart: (CGPoint) -> Void
    let onDragUpdate: (CGPoint) -> Void
    let onDragEnd: () -> Void
    let onCancel: () -> Void
    let onConfirm: () -> Void

    func makeNSView(context: Context) -> MouseTrackingNSView {
        let view = MouseTrackingNSView()
        view.onDragStart = onDragStart
        view.onDragUpdate = onDragUpdate
        view.onDragEnd = onDragEnd
        view.onCancel = onCancel
        view.onConfirm = onConfirm
        return view
    }

    func updateNSView(_ nsView: MouseTrackingNSView, context: Context) {
        nsView.onDragStart = onDragStart
        nsView.onDragUpdate = onDragUpdate
        nsView.onDragEnd = onDragEnd
        nsView.onCancel = onCancel
        nsView.onConfirm = onConfirm
    }
}

class MouseTrackingNSView: NSView {
    var onDragStart: ((CGPoint) -> Void)?
    var onDragUpdate: ((CGPoint) -> Void)?
    var onDragEnd: (() -> Void)?
    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?

    private var isDragging = false
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }  // Use top-left origin like SwiftUI

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        if let ta = trackingArea {
            addTrackingArea(ta)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        updateTrackingAreas()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        isDragging = true
        onDragStart?(point)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        onDragUpdate?(point)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        onDragEnd?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        } else if event.keyCode == 36 { // Return
            onConfirm?()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Selection Mask (darkens outside the selection)
struct SelectionMaskView: View {
    let rect: CGRect
    let screenSize: CGSize

    var body: some View {
        ZStack {
            // Full screen dark overlay
            Color.black.opacity(0.5)

            // Clear hole for selection (if any)
            if rect.width > 0 && rect.height > 0 {
                Rectangle()
                    .fill(Color.black)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
        .allowsHitTesting(false)  // Don't block mouse events
    }
}

// MARK: - Selection Rectangle with handles
struct SelectionRectView: View {
    let rect: CGRect
    let isAdjusting: Bool
    var controller: RegionSelectorController
    @ObservedObject var settings: ZoomSettings

    var body: some View {
        ZStack {
            // Main border
            Rectangle()
                .stroke(
                    LinearGradient(
                        colors: [.blue, .cyan, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            // Size label
            Text("\(Int(rect.width)) x \(Int(rect.height))")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .position(x: rect.midX, y: rect.minY - 20)

            if isAdjusting {
                // Resize handles
                Group {
                    // Corners
                    HandleView(position: CGPoint(x: rect.minX, y: rect.minY))
                    HandleView(position: CGPoint(x: rect.maxX, y: rect.minY))
                    HandleView(position: CGPoint(x: rect.minX, y: rect.maxY))
                    HandleView(position: CGPoint(x: rect.maxX, y: rect.maxY))

                    // Edges
                    HandleView(position: CGPoint(x: rect.midX, y: rect.minY), isEdge: true)
                    HandleView(position: CGPoint(x: rect.midX, y: rect.maxY), isEdge: true)
                    HandleView(position: CGPoint(x: rect.minX, y: rect.midY), isEdge: true)
                    HandleView(position: CGPoint(x: rect.maxX, y: rect.midY), isEdge: true)
                }

                // Settings panel and Confirm button (inside the selection)
                VStack(spacing: 16) {
                    // Recording options panel
                    VStack(spacing: 12) {
                        // Smart Zoom section
                        VStack(spacing: 8) {
                            // Header with main toggle
                            HStack {
                                Image(systemName: "plus.magnifyingglass")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("スマートズーム")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { settings.smartZoomEnabled },
                                    set: { settings.smartZoomEnabled = $0 }
                                ))
                                .toggleStyle(.switch)
                                .scaleEffect(0.7)
                                .labelsHidden()
                            }

                            // Zoom triggers (when enabled)
                            if settings.smartZoomEnabled {
                                HStack(spacing: 8) {
                                    ZoomTriggerChip(
                                        icon: "keyboard",
                                        label: "タイピング",
                                        isOn: settings.zoomOnTyping,
                                        action: { settings.zoomOnTyping.toggle() }
                                    )
                                    ZoomTriggerChip(
                                        icon: "cursorarrow.click.2",
                                        label: "Wクリック",
                                        isOn: settings.zoomOnDoubleClick,
                                        action: { settings.zoomOnDoubleClick.toggle() }
                                    )
                                    ZoomTriggerChip(
                                        icon: "text.cursor",
                                        label: "選択",
                                        isOn: settings.zoomOnTextSelection,
                                        action: { settings.zoomOnTextSelection.toggle() }
                                    )
                                }
                            }
                        }

                        Divider()
                            .background(Color.white.opacity(0.2))

                        // Mosaic section
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "square.grid.3x3.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("モザイク")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { settings.mosaicEnabled },
                                    set: { settings.mosaicEnabled = $0 }
                                ))
                                .toggleStyle(.switch)
                                .scaleEffect(0.7)
                                .labelsHidden()
                            }

                            HStack(spacing: 8) {
                                Text(settings.mosaicRegions.isEmpty
                                     ? "範囲が未設定です"
                                     : "\(settings.mosaicRegions.count)件の範囲 ・ \(settings.mosaicStyle.label)")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.7))
                                Spacer()
                                Button(action: { controller.isEditingMosaic = true }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus.rectangle.on.rectangle")
                                            .font(.system(size: 10))
                                        Text("範囲を指定")
                                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Divider()
                            .background(Color.white.opacity(0.2))

                        // Subtitle toggle
                        HStack {
                            Image(systemName: "captions.bubble")
                                .font(.system(size: 12, weight: .semibold))
                            Text("自動字幕")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { settings.subtitlesEnabled },
                                set: { settings.subtitlesEnabled = $0 }
                            ))
                            .toggleStyle(.switch)
                            .scaleEffect(0.7)
                            .labelsHidden()
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                    )
                    .frame(width: 280)

                    // Confirm button
                    Button(action: { controller.confirm() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 18))
                            Text("録画開始")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 32)
                        .background(
                            LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(Capsule())
                        .shadow(color: .red.opacity(0.5), radius: 12, y: 6)
                    }
                    .buttonStyle(.plain)
                }
                .position(x: rect.midX, y: rect.midY)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if controller.activeHandle == nil {
                        controller.startDrag(at: value.startLocation)
                    }
                    controller.continueDrag(to: value.location)
                }
                .onEnded { _ in
                    controller.endDrag()
                }
        )
    }
}

// MARK: - Handle View
struct HandleView: View {
    let position: CGPoint
    var isEdge: Bool = false

    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: isEdge ? 10 : 12, height: isEdge ? 10 : 12)
            .overlay(
                Circle()
                    .stroke(Color.blue, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .position(position)
    }
}

// MARK: - Instruction Badge
struct InstructionBadge: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
            Text(text)
                .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
    }
}

// MARK: - Zoom Trigger Chip
struct ZoomTriggerChip: View {
    let icon: String
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
            .foregroundColor(isOn ? .white : .white.opacity(0.5))
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isOn ? Color.blue : Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isOn ? Color.blue : Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Legacy view (for compatibility)
struct RegionSelectorView: View {
    @ObservedObject var viewModel: RecorderViewModel

    var body: some View {
        Text("Use new region selector")
    }
}
