import Foundation
import Combine

/// Settings for zoom behavior during screen recording
class ZoomSettings: ObservableObject {
    // MARK: - Zoom Mode
    /// Zoom mode: scale (倍率) or frameSize (フレームサイズ)
    enum ZoomMode: Int {
        case scale = 0       // Specify zoom by magnification (e.g., 2x)
        case frameSize = 1   // Specify zoom by frame dimensions (e.g., 800x600)
    }

    @Published var zoomMode: ZoomMode = .scale

    // MARK: - Zoom Settings (Scale Mode)
    /// Zoom magnification level (e.g., 2.0 = 2x zoom)
    @Published var zoomScale: CGFloat = 2.0

    /// Minimum zoom scale
    @Published var minZoomScale: CGFloat = 1.5

    /// Maximum zoom scale
    @Published var maxZoomScale: CGFloat = 5.0

    // MARK: - Zoom Settings (Frame Size Mode)
    /// Frame width when zoomed (in pixels)
    @Published var zoomFrameWidth: CGFloat = 800

    /// Frame height when zoomed (in pixels)
    @Published var zoomFrameHeight: CGFloat = 600

    /// How quickly the zoom level changes (0.01 = very slow, 0.2 = fast)
    @Published var scaleSmoothing: CGFloat = 0.05

    /// How quickly the position follows the cursor (0.01 = very slow, 0.2 = fast)
    @Published var positionSmoothing: CGFloat = 0.08

    // MARK: - Follow Behavior
    /// Edge margin ratio (0.0-0.5) - cursor must be within this margin from edge to trigger reposition
    @Published var edgeMarginRatio: CGFloat = 0.1

    /// Time (in seconds) to hold zoom after typing stops before zooming out
    @Published var zoomHoldDuration: TimeInterval = 1.5

    /// Time (in seconds) to hold position after cursor moves before following
    @Published var positionHoldDuration: TimeInterval = 0.3

    /// Center point offset ratio (-0.5 to 0.5)
    /// Positive X = cursor appears on left (good for typing)
    @Published var centerOffsetX: CGFloat = 0.25
    @Published var centerOffsetY: CGFloat = 0.0

    // MARK: - Overlay Settings
    /// Whether to show the zoom indicator overlay (corner brackets)
    @Published var showOverlay: Bool = true

    /// Whether to show the safe zone indicator
    @Published var showSafeZone: Bool = true

    /// Safe zone border color (RGB values 0-1)
    @Published var safeZoneColorR: CGFloat = 0.0
    @Published var safeZoneColorG: CGFloat = 1.0
    @Published var safeZoneColorB: CGFloat = 0.0
    @Published var safeZoneOpacity: CGFloat = 0.5

    /// Whether to show the dimming effect outside the zoom area
    @Published var showDimming: Bool = true

    /// Dimming opacity (0.0 = transparent, 1.0 = opaque)
    @Published var dimmingOpacity: CGFloat = 0.3

    // MARK: - Recording Settings
    /// Frame rate for recording (15, 30, 60)
    @Published var frameRate: Int = 30

    /// Show cursor in recording
    @Published var showCursor: Bool = true

    /// Output video quality (0.0 = lowest, 1.0 = highest)
    @Published var videoQuality: CGFloat = 0.8

    /// Output directory for recordings (nil = system temp directory)
    @Published var outputDirectory: URL? = nil

    /// Get the actual output directory (defaults to Movies folder)
    var effectiveOutputDirectory: URL {
        if let dir = outputDirectory {
            return dir
        }
        // Default to Movies folder
        return FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    // MARK: - Smart Zoom Toggle
    /// Enable/disable smart zoom entirely
    @Published var smartZoomEnabled: Bool = true

    // MARK: - Zoom Triggers
    /// Zoom on keyboard input (typing)
    @Published var zoomOnTyping: Bool = true

    /// Zoom on double-click
    @Published var zoomOnDoubleClick: Bool = false

    /// Zoom on text selection
    @Published var zoomOnTextSelection: Bool = false

    // MARK: - Subtitle Settings
    /// Enable/disable automatic subtitles for typed text
    @Published var subtitlesEnabled: Bool = false

    /// Show modifier keys in subtitles (e.g., ⌘+C, ⇧+⌘+Z)
    @Published var showModifierKeys: Bool = true

    /// Subtitle font size
    @Published var subtitleFontSize: CGFloat = 24

    /// Subtitle position (0 = bottom, 1 = top)
    @Published var subtitlePosition: Int = 0

    /// Subtitle background opacity
    @Published var subtitleBackgroundOpacity: CGFloat = 0.7

    /// How long to show subtitle after typing stops (seconds)
    @Published var subtitleDisplayDuration: TimeInterval = 2.0

    // MARK: - Mosaic Settings
    /// Apply mosaic to the registered regions while recording
    @Published var mosaicEnabled: Bool = true { didSet { saveMosaic() } }

    /// Screen areas to mask (display-local points, top-left origin)
    @Published var mosaicRegions: [MosaicRegion] = [] { didSet { saveMosaic() } }

    /// Mosaic block size in screen points
    @Published var mosaicBlockSize: CGFloat = 16 { didSet { saveMosaic() } }

    @Published var mosaicStyle: MosaicStyle = .pixelate { didSet { saveMosaic() } }

    /// Whether mosaic will actually be applied to the next recording
    var isMosaicActive: Bool { mosaicEnabled && !mosaicRegions.isEmpty }

    private enum MosaicKeys {
        static let enabled = "mosaic.enabled"
        static let regions = "mosaic.regions"
        static let blockSize = "mosaic.blockSize"
        static let style = "mosaic.style"
    }

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: MosaicKeys.enabled) != nil {
            mosaicEnabled = defaults.bool(forKey: MosaicKeys.enabled)
        }
        if let data = defaults.data(forKey: MosaicKeys.regions),
           let regions = try? JSONDecoder().decode([MosaicRegion].self, from: data) {
            mosaicRegions = regions
        }
        let block = defaults.double(forKey: MosaicKeys.blockSize)
        if block > 0 { mosaicBlockSize = block }
        if let style = MosaicStyle(rawValue: defaults.integer(forKey: MosaicKeys.style)) {
            mosaicStyle = style
        }
    }

    private func saveMosaic() {
        let defaults = UserDefaults.standard
        defaults.set(mosaicEnabled, forKey: MosaicKeys.enabled)
        defaults.set(try? JSONEncoder().encode(mosaicRegions), forKey: MosaicKeys.regions)
        defaults.set(Double(mosaicBlockSize), forKey: MosaicKeys.blockSize)
        defaults.set(mosaicStyle.rawValue, forKey: MosaicKeys.style)
    }

    // MARK: - Reset
    func resetToDefaults() {
        zoomMode = .scale
        zoomScale = 2.0
        minZoomScale = 1.5
        maxZoomScale = 5.0
        zoomFrameWidth = 800
        zoomFrameHeight = 600
        scaleSmoothing = 0.05
        positionSmoothing = 0.08
        edgeMarginRatio = 0.1
        zoomHoldDuration = 1.5
        positionHoldDuration = 0.3
        centerOffsetX = 0.25
        centerOffsetY = 0.0
        showOverlay = true
        showSafeZone = true
        showDimming = true
        dimmingOpacity = 0.3
        frameRate = 30
        showCursor = true
        videoQuality = 0.8
        smartZoomEnabled = true
        zoomOnTyping = true
        zoomOnDoubleClick = false
        zoomOnTextSelection = false
        subtitlesEnabled = false
        showModifierKeys = true
        subtitleFontSize = 24
        subtitlePosition = 0
        subtitleBackgroundOpacity = 0.7
        subtitleDisplayDuration = 2.0
        mosaicEnabled = true
        mosaicBlockSize = 16
        mosaicStyle = .pixelate
        // outputDirectory and mosaicRegions are not reset (user data)
        // outputDirectory is not reset (user preference)
    }

    // Presets
    static let smooth: ZoomSettings = {
        let settings = ZoomSettings()
        settings.scaleSmoothing = 0.03
        settings.positionSmoothing = 0.05
        settings.edgeMarginRatio = 0.15
        settings.zoomHoldDuration = 2.5
        settings.positionHoldDuration = 0.8
        return settings
    }()

    static let responsive: ZoomSettings = {
        let settings = ZoomSettings()
        settings.scaleSmoothing = 0.1
        settings.positionSmoothing = 0.15
        settings.edgeMarginRatio = 0.08
        settings.zoomHoldDuration = 1.0
        settings.positionHoldDuration = 0.2
        return settings
    }()

    static let `default`: ZoomSettings = {
        let settings = ZoomSettings()
        settings.edgeMarginRatio = 0.1
        settings.positionHoldDuration = 0.5
        return settings
    }()
}
