import Foundation
import CoreGraphics

/// A screen area that is masked in the recorded video.
/// `rect` is in display-local points with a top-left origin (same space as the region selector).
struct MosaicRegion: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var rect: CGRect
}

/// How a mosaic region is rendered in the output video.
enum MosaicStyle: Int, CaseIterable, Codable, Sendable {
    case pixelate = 0   // モザイク
    case blur = 1       // ぼかし
    case fill = 2       // 塗りつぶし

    var label: String {
        switch self {
        case .pixelate: return "モザイク"
        case .blur: return "ぼかし"
        case .fill: return "塗りつぶし"
        }
    }
}
