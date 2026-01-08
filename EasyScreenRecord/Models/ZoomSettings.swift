import Foundation
import Combine

/// Settings for zoom behavior during screen recording
class ZoomSettings: ObservableObject {
    /// Zoom magnification level (e.g., 2.0 = 2x zoom)
    @Published var zoomScale: CGFloat = 2.0

    /// How quickly the zoom level changes (0.01 = very slow, 0.2 = fast)
    @Published var scaleSmoothing: CGFloat = 0.05

    /// How quickly the position follows the cursor (0.01 = very slow, 0.2 = fast)
    @Published var positionSmoothing: CGFloat = 0.08

    /// Minimum cursor movement (in points) required to trigger position update
    /// Prevents jittery movement from small cursor shifts during typing
    @Published var movementThreshold: CGFloat = 50.0

    /// Edge margin ratio (0.0-0.5) - cursor must be within this margin from edge to trigger reposition
    /// 0.1 means 10% from edge triggers reposition
    @Published var edgeMarginRatio: CGFloat = 0.1

    /// Time (in seconds) to hold zoom after typing stops before zooming out
    @Published var zoomHoldDuration: TimeInterval = 1.5

    /// Time (in seconds) to hold position after cursor moves before following
    /// Prevents constant position changes while actively typing
    @Published var positionHoldDuration: TimeInterval = 0.3

    /// Whether to show the zoom indicator overlay
    @Published var showOverlay: Bool = true

    /// Whether to show the dimming effect outside the zoom area
    @Published var showDimming: Bool = true

    /// Dimming opacity (0.0 = transparent, 1.0 = opaque)
    @Published var dimmingOpacity: CGFloat = 0.3

    /// Center point offset ratio (-0.5 to 0.5)
    /// 0.0 = center, negative = left/top, positive = right/bottom
    @Published var centerOffsetX: CGFloat = 0.0
    @Published var centerOffsetY: CGFloat = 0.0

    // Presets
    static let smooth: ZoomSettings = {
        let settings = ZoomSettings()
        settings.scaleSmoothing = 0.03
        settings.positionSmoothing = 0.05
        settings.movementThreshold = 80.0
        settings.edgeMarginRatio = 0.15
        settings.zoomHoldDuration = 2.5
        settings.positionHoldDuration = 0.8
        return settings
    }()

    static let responsive: ZoomSettings = {
        let settings = ZoomSettings()
        settings.scaleSmoothing = 0.1
        settings.positionSmoothing = 0.15
        settings.movementThreshold = 30.0
        settings.edgeMarginRatio = 0.08
        settings.zoomHoldDuration = 1.0
        settings.positionHoldDuration = 0.2
        return settings
    }()

    static let `default`: ZoomSettings = {
        let settings = ZoomSettings()
        settings.movementThreshold = 50.0
        settings.edgeMarginRatio = 0.1
        settings.positionHoldDuration = 0.5
        return settings
    }()
}
