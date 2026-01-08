import SwiftUI

struct RecordingOverlayView: View {
    let scale: CGFloat
    let edgeMargin: CGFloat
    @State private var rotation: Double = 0

    init(scale: CGFloat, edgeMargin: CGFloat = 0.1) {
        self.scale = scale
        self.edgeMargin = edgeMargin
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Edge margin zones (subtle indicator)
                EdgeZoneOverlay(margin: edgeMargin)

                // High-tech scanner lines
                ViewfinderFrame()
                    .stroke(
                        LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2
                    )

                // Safe zone label at bottom
                VStack {
                    Spacer()
                    Text("SAFE ZONE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(.bottom, 8)
                }
            }
        }
        .padding(2) // Small inset for the border
        .onAppear {
            rotation = 360
        }
    }
}

// Edge zone overlay showing where repositioning triggers
struct EdgeZoneOverlay: View {
    let margin: CGFloat

    var body: some View {
        GeometryReader { geo in
            let marginW = geo.size.width * margin
            let marginH = geo.size.height * margin

            ZStack {
                // Left edge zone
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.red.opacity(0.15), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: marginW)
                    .position(x: marginW / 2, y: geo.size.height / 2)

                // Right edge zone
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .red.opacity(0.15)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: marginW)
                    .position(x: geo.size.width - marginW / 2, y: geo.size.height / 2)

                // Top edge zone
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.red.opacity(0.15), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: geo.size.width - marginW * 2, height: marginH)
                    .position(x: geo.size.width / 2, y: marginH / 2)

                // Bottom edge zone
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .red.opacity(0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: geo.size.width - marginW * 2, height: marginH)
                    .position(x: geo.size.width / 2, y: geo.size.height - marginH / 2)

                // Center safe zone border (dashed)
                RoundedRectangle(cornerRadius: 4)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.green.opacity(0.3))
                    .frame(
                        width: geo.size.width - marginW * 2,
                        height: geo.size.height - marginH * 2
                    )
            }
        }
    }
}

struct ViewfinderFrame: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let size: CGFloat = 20
        let thickness: CGFloat = 2
        
        // Top Left
        path.move(to: CGPoint(x: 0, y: size))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: size, y: 0))
        
        // Top Right
        path.move(to: CGPoint(x: rect.width - size, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: size))
        
        // Bottom Right
        path.move(to: CGPoint(x: rect.width, y: rect.height - size))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width - size, y: rect.height))
        
        // Bottom Left
        path.move(to: CGPoint(x: size, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height - size))
        
        return path
    }
}
