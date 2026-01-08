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
}

// MARK: - Full Screen Overlay View
struct RegionSelectorOverlay: View {
    var controller: RegionSelectorController

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dimmed background with hole for selection
                SelectionMaskView(rect: controller.selectionRect, screenSize: geo.size)

                // Selection rectangle
                if controller.selectionRect.width > 0 && controller.selectionRect.height > 0 {
                    SelectionRectView(
                        rect: controller.selectionRect,
                        isAdjusting: controller.isAdjusting,
                        controller: controller
                    )
                }

                // Instructions
                VStack {
                    if !controller.isAdjusting && !controller.isDragging {
                        InstructionBadge(text: "ドラッグで範囲を選択 (ESCでキャンセル)", icon: "rectangle.dashed")
                    } else if controller.isDragging {
                        InstructionBadge(text: "離して範囲を確定", icon: "hand.draw")
                    } else if controller.isAdjusting {
                        InstructionBadge(text: "Enterで録画開始 / ESCでキャンセル", icon: "keyboard")
                    }
                    Spacer()
                }
                .padding(.top, 60)

                // Cancel button (top right)
                VStack {
                    HStack {
                        Spacer()
                        Button(action: { controller.cancel() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.escape, modifiers: [])
                        .padding(20)
                    }
                    Spacer()
                }
            }
            .background(Color.clear)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if controller.activeHandle == nil && !controller.isDragging && !controller.isAdjusting {
                            controller.startDrag(at: value.startLocation)
                        }
                        controller.continueDrag(to: value.location)
                    }
                    .onEnded { _ in
                        controller.endDrag()
                    }
            )
            .onTapGesture { location in
                if controller.isAdjusting {
                    controller.startDrag(at: location)
                }
            }
        }
        .ignoresSafeArea()
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
    }
}

// MARK: - Selection Rectangle with handles
struct SelectionRectView: View {
    let rect: CGRect
    let isAdjusting: Bool
    var controller: RegionSelectorController

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

                // Confirm button (inside the selection)
                Button(action: { controller.confirm() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 16))
                        Text("録画開始")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(
                        LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                    .shadow(color: .red.opacity(0.5), radius: 10, y: 5)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
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

// MARK: - Legacy view (for compatibility)
struct RegionSelectorView: View {
    @ObservedObject var viewModel: RecorderViewModel

    var body: some View {
        Text("Use new region selector")
    }
}
