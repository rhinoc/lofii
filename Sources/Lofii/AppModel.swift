import Foundation
import OSLog
import SwiftUI

enum VisualMode: String, CaseIterable, Identifiable, Sendable {
    case cinematic
    case gif

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cinematic: return "Cinematic"
        case .gif:       return "lofii GIF"
        }
    }

    var glyph: PixelGlyph {
        switch self {
        case .cinematic: return .movie
        case .gif:       return .gif
        }
    }
}

/// Three preset sizes for the readout (waveform + station name + track
/// title + artists) that lives at the bottom of the widget by default.
/// Exposed via the right-click context menu so users can tune the
/// information density to taste.
///
/// `scale` is the multiplier we apply to every text/glyph size in
/// `TrackBadge`. The defaults stay at 1.0 (= what shipped before this
/// menu existed) so users who never touch the menu see no visual change.
enum BadgeSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small:  return "Small"
        case .medium: return "Medium"
        case .large:  return "Large"
        }
    }

    /// Linear scale applied to every text/glyph dimension inside the
    /// badge. `medium` matches the original (pre-menu) sizing.
    var scale: CGFloat {
        switch self {
        case .small:  return 0.78
        case .medium: return 1.0
        case .large:  return 1.28
        }
    }
}

/// One of nine anchor points the readout badge can snap to inside the
/// widget. Mirrors the standard 3×3 grid used by NSAlignmentRect /
/// `Alignment` so users get the canonical "9 zones" picker rather than
/// a slider with no semantic meaning.
enum BadgePosition: String, CaseIterable, Identifiable, Sendable {
    case topLeading
    case top
    case topTrailing
    case leading
    case center
    case trailing
    case bottomLeading
    case bottom
    case bottomTrailing

    var id: String { rawValue }

    /// SwiftUI alignment used by the badge's outer wrapper. Each anchor
    /// pulls the badge into one of the nine corners/edges/center of the
    /// widget's content area.
    var alignment: Alignment {
        switch self {
        case .topLeading:     return .topLeading
        case .top:            return .top
        case .topTrailing:    return .topTrailing
        case .leading:        return .leading
        case .center:         return .center
        case .trailing:       return .trailing
        case .bottomLeading:  return .bottomLeading
        case .bottom:         return .bottom
        case .bottomTrailing: return .bottomTrailing
        }
    }

    /// Short human label for the right-click menu.
    var label: String {
        switch self {
        case .topLeading:     return "Top Left"
        case .top:            return "Top"
        case .topTrailing:    return "Top Right"
        case .leading:        return "Left"
        case .center:         return "Center"
        case .trailing:       return "Right"
        case .bottomLeading:  return "Bottom Left"
        case .bottom:         return "Bottom"
        case .bottomTrailing: return "Bottom Right"
        }
    }
}

enum ScanlineOpacity: String, CaseIterable, Identifiable, Codable, Sendable {
    case subtle
    case balanced
    case strong

    var id: String { rawValue }

    var label: String {
        switch self {
        case .subtle: return "Low"
        case .balanced: return "Medium"
        case .strong: return "High"
        }
    }

    func resolvedOpacity(for mode: VisualMode) -> Double {
        let base = mode == .cinematic ? 0.18 : 0.30
        let multiplier: Double
        switch self {
        case .subtle:   multiplier = 0.65
        case .balanced: multiplier = 1.0
        case .strong:   multiplier = 1.35
        }
        return min(0.9, base * multiplier)
    }
}

enum ScanlineDensity: String, CaseIterable, Identifiable, Codable, Sendable {
    case sparse
    case balanced
    case dense

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sparse: return "Sparse"
        case .balanced: return "Medium"
        case .dense: return "Dense"
        }
    }

    var pitch: Double {
        switch self {
        case .sparse: return 5
        case .balanced: return 3
        case .dense: return 2
        }
    }
}

enum MotionBlurStrength: String, CaseIterable, Identifiable, Codable, Sendable {
    case subtle
    case balanced
    case strong

    var id: String { rawValue }

    var label: String {
        switch self {
        case .subtle: return "Low"
        case .balanced: return "Medium"
        case .strong: return "High"
        }
    }

    var resolvedStrength: Double {
        switch self {
        case .subtle: return 0.18
        case .balanced: return 0.34
        case .strong: return 0.55
        }
    }
}

enum ChromaticAberrationStrength: String, CaseIterable, Identifiable, Codable, Sendable {
    case subtle
    case balanced
    case strong

    var id: String { rawValue }

    var label: String {
        switch self {
        case .subtle: return "Low"
        case .balanced: return "Medium"
        case .strong: return "High"
        }
    }

    var resolvedStrength: Double {
        switch self {
        case .subtle: return 0.55
        case .balanced: return 1.0
        case .strong: return 1.7
        }
    }
}

enum CurvationStrength: String, CaseIterable, Identifiable, Codable, Sendable {
    case subtle
    case balanced
    case strong

    var id: String { rawValue }

    var label: String {
        switch self {
        case .subtle: return "Low"
        case .balanced: return "Medium"
        case .strong: return "High"
        }
    }

    var resolvedCurvationFactor: Double {
        switch self {
        case .subtle: return 0.08
        case .balanced: return 0.14
        case .strong: return 0.20
        }
    }

    var resolvedOverscan: Double {
        switch self {
        case .subtle: return 1.09
        case .balanced: return 1.15
        case .strong: return 1.22
        }
    }

    var resolvedBorderSize: Double {
        switch self {
        case .subtle: return 0.006
        case .balanced: return 0.01
        case .strong: return 0.014
        }
    }
}

enum VignetteStrength: String, CaseIterable, Identifiable, Codable, Sendable {
    case subtle
    case balanced
    case strong

    var id: String { rawValue }

    var label: String {
        switch self {
        case .subtle: return "Low"
        case .balanced: return "Medium"
        case .strong: return "High"
        }
    }

    var resolvedVignetteAlpha: Double {
        switch self {
        case .subtle: return 0.38
        case .balanced: return 0.60
        case .strong: return 0.88
        }
    }
}

enum ShatteredGlassStrength: String, CaseIterable, Identifiable, Codable, Sendable {
    case subtle
    case balanced
    case strong

    var id: String { rawValue }

    var label: String {
        switch self {
        case .subtle: return "Low"
        case .balanced: return "Medium"
        case .strong: return "High"
        }
    }

    var resolvedOpacity: Double {
        switch self {
        case .subtle: return 0.42
        case .balanced: return 0.68
        case .strong: return 0.95
        }
    }

    var resolvedRefraction: Double {
        switch self {
        case .subtle: return 10
        case .balanced: return 18
        case .strong: return 28
        }
    }

    var resolvedHighlight: Double {
        switch self {
        case .subtle: return 0.28
        case .balanced: return 0.46
        case .strong: return 0.68
        }
    }
}

enum ShatteredGlassPlacement: String, CaseIterable, Identifiable, Codable, Sendable {
    case left
    case right

    var id: String { rawValue }

    var label: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        }
    }

    var resolvedFlipX: Double {
        switch self {
        case .left: return 0
        case .right: return 1
        }
    }
}

struct CRTSettings: Codable, Equatable, Sendable {
    var enabled: Bool = true
    var curvation: Bool = true
    var curvationStrength: CurvationStrength = .balanced
    var vignette: Bool = true
    var vignetteStrength: VignetteStrength = .balanced
    var chromaticAberration: Bool = true
    var scanlines: Bool = true
    var motionBlur: Bool = true
    var scanlineOpacity: ScanlineOpacity = .balanced
    var scanlineDensity: ScanlineDensity = .balanced
    var motionBlurStrength: MotionBlurStrength = .balanced
    var chromaticAberrationStrength: ChromaticAberrationStrength = .balanced
}

struct ShatteredGlassSettings: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var strength: ShatteredGlassStrength = .balanced
    var placement: ShatteredGlassPlacement = .left

    init(
        enabled: Bool = false,
        strength: ShatteredGlassStrength = .balanced,
        placement: ShatteredGlassPlacement = .left
    ) {
        self.enabled = enabled
        self.strength = strength
        self.placement = placement
    }
}

extension ShatteredGlassSettings {
    var resolvedOpacity: Double {
        enabled ? strength.resolvedOpacity : 0
    }

    var resolvedRefraction: Double {
        enabled ? strength.resolvedRefraction : 0
    }

    var resolvedHighlight: Double {
        enabled ? strength.resolvedHighlight : 0
    }

    var resolvedFlipX: Double {
        placement.resolvedFlipX
    }

    /// When the CRT master switch is off, glass must not draw (it is grouped under CRT in the UI).
    func resolvedForDisplayPipeline(crtMasterEnabled: Bool) -> (opacity: Double, refraction: Double, highlight: Double) {
        guard crtMasterEnabled else { return (0, 0, 0) }
        return (resolvedOpacity, resolvedRefraction, resolvedHighlight)
    }
}

extension CRTSettings {
    /// Tube-curvature uniforms when the CRT stack and curvation toggle are active.
    func resolvedCurvationUniforms(active: Bool) -> (factor: Double, overscan: Double, border: Double) {
        guard active else { return (0, 1, 0) }
        let s = curvationStrength
        return (s.resolvedCurvationFactor, s.resolvedOverscan, s.resolvedBorderSize)
    }

    /// Vignette alpha passed to the Metal shader when the CRT stack and vignette toggle are active.
    func resolvedVignetteAlpha(active: Bool) -> Double {
        guard active else { return 0 }
        return vignetteStrength.resolvedVignetteAlpha
    }

    /// Logical inset (points) from the widget edge when the Bongo stage anchor pins to that side.
    ///
    /// Stays close to the historical fixed ~10pt so the stage does not “float” into a large gutter on
    /// small widgets, and does **not** scale up with fullscreen size (that amplified CRT edge darkening
    /// and looked like a giant black frame). Curvation / vignette only add a few points via presets.
    func resolvedBongoStageEdgeInset(containerSize: CGSize) -> CGFloat {
        let w = max(containerSize.width, 1)
        let h = max(containerSize.height, 1)
        let s = min(w, h)

        let baseline: CGFloat = 10

        guard enabled else { return baseline }

        var bump: CGFloat = 0
        if curvation {
            switch curvationStrength {
            case .subtle: bump += 1
            case .balanced: bump += 2
            case .strong: bump += 3
            }
        }
        if vignette {
            switch vignetteStrength {
            case .subtle: bump += 0.5
            case .balanced: bump += 1
            case .strong: bump += 1.5
            }
        }

        // Tiny widgets: shrink bump so we do not reveal a wide band of backdrop / mask mismatch.
        if s < 400 {
            bump *= 0.6
        }

        return baseline + bump
    }
}

enum ReadoutFontWeight: String, CaseIterable, Identifiable, Codable, Sendable {
    case light
    case medium
    case bold
    case heavy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "Light"
        case .medium: return "Medium"
        case .bold: return "Bold"
        case .heavy: return "Heavy"
        }
    }

    /// Doto `wght` axis (100–900).
    var axisValue: Double {
        switch self {
        case .light: return 320
        case .medium: return 520
        case .bold: return 700
        case .heavy: return 860
        }
    }
}

enum ReadoutFontElementShape: String, CaseIterable, Identifiable, Codable, Sendable {
    case square
    case balanced
    case round

    var id: String { rawValue }

    var label: String {
        switch self {
        case .square: return "Square"
        case .balanced: return "Balanced"
        case .round: return "Round"
        }
    }

    /// Doto `ROND` axis (0–100).
    var axisValue: Double {
        switch self {
        case .square: return 0
        case .balanced: return 45
        case .round: return 100
        }
    }
}

enum ReadoutFontSlant: String, CaseIterable, Identifiable, Codable, Sendable {
    case upright
    case tilted
    case italic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .upright: return "Upright"
        case .tilted: return "Tilted"
        case .italic: return "Italic"
        }
    }
}

struct ReadoutFontSettings: Codable, Equatable, Sendable {
    var weight: ReadoutFontWeight = .medium
    var elementShape: ReadoutFontElementShape = .square
    var slant: ReadoutFontSlant = .upright
    /// Mini spectrum above the station name (Readout menu).
    var waveform: Bool = true
    /// Black drop shadow under readout glyphs; independent of Readout ▸ Text Glow.
    var textShadow: Bool = true
    /// Colored bloom on readout text and waveform.
    var textGlow: Bool = true
}

/// Desktop fill under the Bongo cut line (native mask polygon).
enum BongoDesktopMaskTint: String, CaseIterable, Codable, Sendable {
    case black
    case ink
    case dynamic
    case modelDynamic
    /// No fill below the cut line — the GIF shows through the whole widget.
    case hidden

    static var colorCases: [BongoDesktopMaskTint] {
        allCases.filter { $0 != .hidden }
    }

    var menuLabel: String {
        switch self {
        case .black: return "Black"
        case .ink: return "White"
        case .dynamic: return "Media Auto"
        case .modelDynamic: return "Model Auto"
        case .hidden: return "Off"
        }
    }

    /// Fill for the desk area under the cut line.
    var cssHex: String {
        switch self {
        case .black: return "#050505"
        case .ink: return "#ffffff"
        case .dynamic: return "#050505"
        case .modelDynamic: return "#050505"
        case .hidden: return "#00000000"
        }
    }

    /// SwiftUI Color counterpart of `cssHex`, used by the native desktop overlay.
    var swiftUIColor: Color {
        switch self {
        case .black: return Color(red: 5.0 / 255.0, green: 5.0 / 255.0, blue: 5.0 / 255.0)
        case .ink: return Color(red: 255.0 / 255.0, green: 255.0 / 255.0, blue: 255.0 / 255.0)
        case .dynamic: return Color(red: 5.0 / 255.0, green: 5.0 / 255.0, blue: 5.0 / 255.0)
        case .modelDynamic: return Color(red: 5.0 / 255.0, green: 5.0 / 255.0, blue: 5.0 / 255.0)
        case .hidden: return .clear
        }
    }
}

/// Bundled Live2D pack for the native Bongo overlay (`BongoCat/<folder>/…`).
enum BongoCatModelKind: String, CaseIterable, Codable, Sendable {
    case wendi
    /// Default preset (`standard`) from [ayangweb/BongoCat](https://github.com/ayangweb/BongoCat).
    case standard
    case bangboo

    /// Bundled model when preferences are absent or not recognized.
    static let bundledDefault: BongoCatModelKind = .bangboo

    var menuLabel: String {
        switch self {
        case .wendi: return "Wendi"
        case .standard: return "BongoCat"
        case .bangboo: return "Bangboo"
        }
    }

    /// Subfolder under `BongoCat/` in the module resource bundle.
    var bundleFolderName: String {
        switch self {
        case .wendi: return "wendi"
        case .standard: return "standard"
        case .bangboo: return "bangboo"
        }
    }

    /// MOC filename stem (without `.moc3`) for native bootstrap diagnostics.
    var mocStem: String {
        switch self {
        case .wendi: return "demomodel"
        case .standard: return "demomodel"
        case .bangboo: return "demomodel"
        }
    }

    static let modelSettingFileName = "cat.model3.json"

    var resourcesSubdirectory: String {
        "BongoCat/\(bundleFolderName)/resources"
    }

    var leftKeysSubdirectory: String {
        "\(resourcesSubdirectory)/left-keys"
    }

    /// Maximum stage size in logical points. Source Bongo assets are pixel-sized;
    /// halving keeps their intended physical size on Retina displays.
    var maxLogicalStageSize: CGSize {
        switch self {
        case .wendi: return CGSize(width: 979 / 2.0, height: 566 / 2.0)
        case .standard: return CGSize(width: 612 / 2.0, height: 354 / 2.0)
        case .bangboo: return CGSize(width: 800 / 2.0, height: 660 / 2.0)
        }
    }
}

/// Where the fitted Bongo stage sits inside the widget (middle + bottom row).
/// Independent from `BadgePosition` so the two prefs never collide in
/// UserDefaults or mental model.
enum BongoStageAnchor: String, CaseIterable, Identifiable, Codable, Sendable {
    case leading
    case center
    case trailing
    case bottomLeading
    case bottom
    case bottomTrailing

    var id: String { rawValue }

    /// Human-readable anchor name (menus); matches `BadgePosition.label` wording.
    var label: String {
        switch self {
        case .leading: return "Left"
        case .center: return "Center"
        case .trailing: return "Right"
        case .bottomLeading: return "Bottom Left"
        case .bottom: return "Bottom"
        case .bottomTrailing: return "Bottom Right"
        }
    }
}

/// User scale for the Bongo Live2D stage (logical points cap before fitting).
enum BongoStageScaleTier: String, CaseIterable, Identifiable, Codable, Sendable {
    case small
    case medium
    case large

    var id: String { rawValue }

    /// Multiplier applied to `BongoCatModelKind.maxLogicalStageSize`.
    var scale: CGFloat {
        switch self {
        case .small: return 0.5
        case .medium: return 0.75
        case .large: return 1.0
        }
    }

    var menuLabel: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    /// Fitted Live2D stage height never exceeds this × widget height (keeps Bongo from dominating a tiny window).
    var maxFittedStageHeightFractionOfContainer: CGFloat { scale }
}

/// Poll rate for Bongo global mouse position, mouse-button reconciliation, and
/// batched Live2D parameters (`BongoCoordinator` input timer).
enum BongoInputTickRate: String, CaseIterable, Identifiable, Codable, Sendable {
    case hz15
    case hz30
    case hz60

    var id: String { rawValue }

    var menuLabel: String {
        switch self {
        case .hz15: return "15 fps"
        case .hz30: return "30 fps"
        case .hz60: return "60 fps"
        }
    }

    var timeInterval: TimeInterval {
        1.0 / hz
    }

    var framesPerSecond: Int {
        Int(hz)
    }

    private var hz: Double {
        switch self {
        case .hz15: return 15
        case .hz30: return 30
        case .hz60: return 60
        }
    }
}

extension BongoCatModelKind {
    /// `maxLogicalStageSize` scaled by the user’s size tier (aspect ratio unchanged).
    func maxLogicalStageSize(scaledBy tier: BongoStageScaleTier) -> CGSize {
        let base = maxLogicalStageSize
        let s = tier.scale
        return CGSize(width: base.width * s, height: base.height * s)
    }
}

@MainActor
final class AppModel: ObservableObject {
    private static let chillhopCrossfadeDuration: TimeInterval = 2.8
    private static let chillhopQueueLowWatermark = 3

    @Published private(set) var presets = LofiiPreset.presets
    @Published private(set) var gifAssets = GifSceneCatalog.animated
    @Published var selectedIndex = 0 {
        didSet {
            guard selectedIndex != oldValue else { return }
            UserDefaults.standard.set(currentPreset.id, forKey: Self.selectedPresetIDKey)
            currentVariant = currentPreset.defaultVariant
            cancelPlaybackRecovery()
            resetChillhopPlaybackState()
            currentTrack = nil
            lastPlaybackWatchdogSample = nil
            stalledPlaybackWatchdogTicks = 0
            streamStatus = "Connecting…"
            refreshSystemMediaControls()
            Task {
                await loadLiveTrack(replacingCurrentItem: true)
            }
        }
    }
    @Published var currentVariant: SceneVariant = LofiiPreset.presets[0].defaultVariant {
        didSet {
            refreshSystemMediaControls()
        }
    }
    @Published var visualMode: VisualMode = AppModel.loadVisualMode() {
        didSet {
            guard visualMode != oldValue else { return }
            UserDefaults.standard.set(visualMode.rawValue, forKey: Self.visualModeKey)
            if visualMode == .gif {
                Task { await GifCache.shared.prefetchStatics() }
                resetVisualStageLoadingGate(updateBongoLayer: false)
            } else if visualMode == .cinematic {
                resetVisualStageLoadingGate(updateBongoLayer: false)
            }
        }
    }

    /// Live2D Bongo overlay on top of the current visual background. Toggled from the right-click menu.
    @Published var bongoOverlayVisible: Bool = AppModel.loadBongoOverlayVisible() {
        didSet {
            guard bongoOverlayVisible != oldValue else { return }
            UserDefaults.standard.set(bongoOverlayVisible, forKey: Self.bongoOverlayVisibleKey)
            if bongoOverlayVisible {
                markBongoLive2DPending()
                resetVisualStageLoadingGate(updateBongoLayer: false)
            } else {
                markBongoLive2DReady()
            }
        }
    }

    /// Global: extra diagnostics and editor-style overlays where a view opts in.
    /// Also stretches readout title/artist lines so the marquee path is easy to test.
    @Published var debugModeEnabled: Bool = AppModel.loadDebugModeEnabled() {
        didSet {
            guard debugModeEnabled != oldValue else { return }
            UserDefaults.standard.set(debugModeEnabled, forKey: Self.debugModeEnabledKey)
        }
    }
    @Published var currentGifIndex: Int = 0 {
        didSet {
            guard currentGifIndex != oldValue else { return }
            // Swapping the GIF index only invalidates primary media — Live2D
            // stays mounted, so we must not reset the Bongo layer gate.
            resetVisualStageLoadingGate(updateBongoLayer: false)
        }
    }

    // MARK: - Visual stage loading (global snow gate)

    /// True when every **tracked** contributor for the current layout is ready
    /// so the global loading snow can hide. Tracking is active in GIF mode or
    /// whenever Bongo is on (then primary media is the Bongo background and
    /// Bongo adds a Live2D dependency). Cinematic without Bongo does not use
    /// this gate (scene video handles its own transition).
    @Published private(set) var visualStageReady: Bool = true

    /// GIF / scene media used by `GifSceneView` or the Bongo unified stage.
    private var primaryVisualMediaReady: Bool = false
    /// Live2D runtime for Bongo; ignored when `bongoOverlayVisible` is false.
    private var bongoLive2DReady: Bool = true

    private func refreshVisualStageReady() {
        let tracksLoading = bongoOverlayVisible || visualMode == .gif
        let nextReady: Bool
        if !tracksLoading {
            nextReady = true
        } else {
            let bongoSatisfied = !bongoOverlayVisible || bongoLive2DReady
            nextReady = primaryVisualMediaReady && bongoSatisfied
        }
        guard nextReady != visualStageReady else { return }
        visualStageReady = nextReady
    }

    func markPrimaryVisualMediaReady() {
        primaryVisualMediaReady = true
        refreshVisualStageReady()
    }

    func markBongoLive2DReady() {
        bongoLive2DReady = true
        refreshVisualStageReady()
    }

    func markBongoLive2DPending() {
        bongoLive2DReady = false
        refreshVisualStageReady()
    }

    /// Clears primary media readiness and optionally resets the Bongo Live2D gate.
    /// - Parameter updateBongoLayer: `true` after a full Bongo teardown; `false`
    ///   when only the background asset changes while Live2D stays resident.
    func resetVisualStageLoadingGate(updateBongoLayer: Bool = true) {
        primaryVisualMediaReady = false
        if updateBongoLayer {
            bongoLive2DReady = !bongoOverlayVisible
        }
        refreshVisualStageReady()
    }

    @Published var isPlaying = true {
        didSet {
            syncPlayback()
            refreshSystemMediaControls()
        }
    }
    @Published var volume = 0.58 {
        didSet {
            audioEngine.setVolume(volume)
        }
    }
    @Published var alwaysOnTop = AppModel.loadAlwaysOnTop() {
        didSet {
            UserDefaults.standard.set(alwaysOnTop, forKey: Self.alwaysOnTopKey)
        }
    }

    var widgetWindowContentCornerRadius: CGFloat { WidgetChromeMetrics.contentCornerRadius }

    @Published var currentTrack: LiveTrack? {
        didSet {
            refreshSystemMediaControls()
        }
    }
    @Published var streamStatus = "Connecting…"
    /// True while the user has asked us to play but the network/AVPlayer
    /// pipeline is still spinning up (initial connect or mid-stream rebuffer).
    /// Drives the spinner overlay on the play/pause button.
    @Published private(set) var isBuffering = false
    /// UI-level visibility gate for high-frequency visual rendering work.
    /// When false (widget hidden via menubar), scene/gif playback and
    /// animated overlays pause to reduce CPU/GPU usage.
    @Published private(set) var isWidgetVisible = true

    /// Single gate for MTK-backed stages and media decode: pauses when transport is stopped
    /// or the widget is off-screen (`isWidgetVisible` false).
    var shouldRenderStageMotion: Bool { isPlaying && isWidgetVisible }

    // MARK: Display preferences (right-click menu)
    //
    // Right-click display preferences are mirrored into UserDefaults so the
    // choice survives a relaunch — no separate preferences window.

    @Published var badgeSize: BadgeSize = AppModel.loadBadgeSize() {
        didSet {
            UserDefaults.standard.set(badgeSize.rawValue, forKey: Self.badgeSizeKey)
        }
    }
    @Published var isReadoutVisible: Bool = AppModel.loadReadoutVisibility() {
        didSet {
            UserDefaults.standard.set(isReadoutVisible, forKey: Self.readoutVisibleKey)
        }
    }
    @Published var badgePosition: BadgePosition = AppModel.loadBadgePosition() {
        didSet {
            UserDefaults.standard.set(badgePosition.rawValue, forKey: Self.badgePositionKey)
        }
    }
    @Published var crt: CRTSettings = AppModel.loadCRTSettings() {
        didSet {
            if let data = try? JSONEncoder().encode(crt) {
                UserDefaults.standard.set(data, forKey: Self.crtSettingsKey)
            }
        }
    }
    @Published var shatteredGlass: ShatteredGlassSettings = AppModel.loadShatteredGlassSettings() {
        didSet {
            if let data = try? JSONEncoder().encode(shatteredGlass) {
                UserDefaults.standard.set(data, forKey: Self.shatteredGlassSettingsKey)
            }
        }
    }
    @Published var readoutFontSettings: ReadoutFontSettings = AppModel.loadReadoutFontSettings() {
        didSet {
            if let data = try? JSONEncoder().encode(readoutFontSettings) {
                UserDefaults.standard.set(data, forKey: Self.readoutFontSettingsKey)
            }
        }
    }

    @Published var bongoDesktopMaskTint: BongoDesktopMaskTint = AppModel.loadBongoDesktopMaskTint() {
        didSet {
            guard bongoDesktopMaskTint != oldValue else { return }
            UserDefaults.standard.set(bongoDesktopMaskTint.rawValue, forKey: Self.bongoDesktopMaskTintKey)
        }
    }

    @Published var bongoCatPack: BongoCatPack = AppModel.loadBongoCatPack() {
        didSet {
            guard bongoCatPack != oldValue else { return }
            UserDefaults.standard.set(bongoCatPack.persistenceValue, forKey: Self.bongoCatPackSelectionKey)
            if case .bundled(let kind) = bongoCatPack {
                UserDefaults.standard.set(kind.rawValue, forKey: Self.bongoCatModelKindKey)
            }
            if bongoOverlayVisible {
                markBongoLive2DPending()
            }
        }
    }

    /// Names of valid packs under `~/.lofii/bongo/<name>/` (see `BongoCatPack.listImportedFolderNames()`).
    @Published private(set) var bongoImportedModelFolderNames: [String] = BongoCatPack.listImportedFolderNames()

    /// Bumped on `reloadBongoModelsFromDisk()` so `BongoView` tears down Live2D / Metal state and reloads from disk.
    @Published private(set) var bongoPackReloadToken: UInt = 0

    @Published var bongoStageAnchor: BongoStageAnchor = AppModel.loadBongoStageAnchor() {
        didSet {
            guard bongoStageAnchor != oldValue else { return }
            UserDefaults.standard.set(bongoStageAnchor.rawValue, forKey: Self.bongoStageAnchorKey)
        }
    }

    @Published var bongoStageScaleTier: BongoStageScaleTier = AppModel.loadBongoStageScaleTier() {
        didSet {
            guard bongoStageScaleTier != oldValue else { return }
            UserDefaults.standard.set(bongoStageScaleTier.rawValue, forKey: Self.bongoStageScaleTierKey)
        }
    }

    @Published var bongoInputTickRate: BongoInputTickRate = AppModel.loadBongoInputTickRate() {
        didSet {
            guard bongoInputTickRate != oldValue else { return }
            UserDefaults.standard.set(bongoInputTickRate.rawValue, forKey: Self.bongoInputTickRateKey)
        }
    }

    private static let badgeSizeKey = "lofii.badgeSize"
    private static let readoutVisibleKey = "lofii.readoutVisible"
    private static let badgePositionKey = "lofii.badgePosition"
    private static let crtSettingsKey = "lofii.crtSettings"
    private static let shatteredGlassSettingsKey = "lofii.shatteredGlassSettings"
    private static let readoutFontSettingsKey = "lofii.readoutFontSettings"
    private static let visualModeKey = "lofii.visualMode"
    private static let bongoOverlayVisibleKey = "lofii.bongoOverlayVisible"
    private static let debugModeEnabledKey = "lofii.debugModeEnabled"
    private static let bongoDesktopMaskTintKey = "lofii.bongoDesktopMaskTint"
    private static let bongoCatModelKindKey = "lofii.bongoCatModelKind"
    private static let bongoCatPackSelectionKey = "lofii.bongoCatPackSelection"
    private static let bongoStageAnchorKey = "lofii.bongoStageAnchor"
    private static let bongoStageScaleTierKey = "lofii.bongoStageScaleTier"
    private static let bongoInputTickRateKey = "lofii.bongoInputTickRate"
    private static let selectedPresetIDKey = "lofii.selectedPresetID"
    private static let alwaysOnTopKey = "lofii.alwaysOnTop"

    private static func loadBadgeSize() -> BadgeSize {
        guard let raw = UserDefaults.standard.string(forKey: badgeSizeKey),
              let value = BadgeSize(rawValue: raw)
        else { return .medium }
        return value
    }

    private static func loadReadoutVisibility() -> Bool {
        if UserDefaults.standard.object(forKey: readoutVisibleKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: readoutVisibleKey)
    }

    private static func loadBadgePosition() -> BadgePosition {
        guard let raw = UserDefaults.standard.string(forKey: badgePositionKey),
              let value = BadgePosition(rawValue: raw)
        else { return .topLeading }
        return value
    }

    private static func loadDecodedJSON<T: Codable>(
        _: T.Type,
        key: String,
        default defaultValue: T
    ) -> T {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return defaultValue
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            UserDefaults.standard.removeObject(forKey: key)
            return defaultValue
        }
    }

    private static func loadCRTSettings() -> CRTSettings {
        loadDecodedJSON(CRTSettings.self, key: crtSettingsKey, default: CRTSettings())
    }

    private static func loadShatteredGlassSettings() -> ShatteredGlassSettings {
        loadDecodedJSON(ShatteredGlassSettings.self, key: shatteredGlassSettingsKey, default: ShatteredGlassSettings())
    }

    private static func loadReadoutFontSettings() -> ReadoutFontSettings {
        loadDecodedJSON(ReadoutFontSettings.self, key: readoutFontSettingsKey, default: ReadoutFontSettings())
    }

    private static func loadVisualMode() -> VisualMode {
        guard let raw = UserDefaults.standard.string(forKey: visualModeKey) else {
            return .cinematic
        }
        return VisualMode(rawValue: raw) ?? .cinematic
    }

    private static func loadBongoOverlayVisible() -> Bool {
        if UserDefaults.standard.object(forKey: bongoOverlayVisibleKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: bongoOverlayVisibleKey)
    }

    private static func loadDebugModeEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: debugModeEnabledKey)
    }

    private static func loadBongoDesktopMaskTint() -> BongoDesktopMaskTint {
        guard let raw = UserDefaults.standard.string(forKey: bongoDesktopMaskTintKey),
              let value = BongoDesktopMaskTint(rawValue: raw)
        else { return .modelDynamic }
        return value
    }

    private static func loadBongoCatModelKind() -> BongoCatModelKind {
        guard let raw = UserDefaults.standard.string(forKey: bongoCatModelKindKey),
              let value = BongoCatModelKind(rawValue: raw)
        else {
            return BongoCatModelKind.bundledDefault
        }
        return value
    }

    private static func loadBongoCatPack() -> BongoCatPack {
        if let raw = UserDefaults.standard.string(forKey: bongoCatPackSelectionKey),
           let pack = BongoCatPack.decode(persistence: raw)
        {
            let resolved = pack.resolvedIfPackFolderMissing()
            if resolved.persistenceValue != raw {
                UserDefaults.standard.set(resolved.persistenceValue, forKey: bongoCatPackSelectionKey)
            }
            return resolved
        }
        return .bundled(loadBongoCatModelKind())
    }

    private static func loadBongoStageAnchor() -> BongoStageAnchor {
        guard let raw = UserDefaults.standard.string(forKey: bongoStageAnchorKey),
              let value = BongoStageAnchor(rawValue: raw)
        else { return .bottom }
        return value
    }

    private static func loadBongoStageScaleTier() -> BongoStageScaleTier {
        guard let raw = UserDefaults.standard.string(forKey: bongoStageScaleTierKey),
              let value = BongoStageScaleTier(rawValue: raw)
        else { return .medium }
        return value
    }

    private static func loadBongoInputTickRate() -> BongoInputTickRate {
        guard let raw = UserDefaults.standard.string(forKey: bongoInputTickRateKey),
              let value = BongoInputTickRate(rawValue: raw)
        else { return .hz30 }
        return value
    }

    private static func loadSelectedPresetIndex(from presets: [LofiiPreset]) -> Int {
        guard let presetID = UserDefaults.standard.string(forKey: selectedPresetIDKey),
              let index = presets.firstIndex(where: { $0.id == presetID })
        else { return 0 }
        return index
    }

    private static func loadAlwaysOnTop() -> Bool {
        if UserDefaults.standard.object(forKey: alwaysOnTopKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: alwaysOnTopKey)
    }

    private let audioEngine = StreamingAudioEngine()
    private let systemMediaControls = SystemMediaControls()
    private let chillhopService = ChillhopService()
    private let radioCoService = RadioCoService()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "lofii",
        category: "audio.flow"
    )
    private var streamRefreshTimer: Timer?
    private var playbackWatchdogTimer: Timer?
    private var lastPlaybackWatchdogSample: StreamingAudioEngine.PlaybackSample?
    private var stalledPlaybackWatchdogTicks = 0
    private var chillhopQueue: [LiveTrack] = []
    private var chillhopTransitionTimer: Timer?
    private var chillhopTransitionFireDate: Date?
    private var chillhopTransitionRemaining: TimeInterval?
    private var playbackRecoveryTask: Task<Void, Never>?
    private var pendingPlaybackRecovery: PlaybackRecoveryStep?

    private enum PlaybackRecoveryStep: Equatable {
        case softResume
        case hardReload

        var delay: TimeInterval {
            switch self {
            case .softResume:
                return 1.2
            case .hardReload:
                return 4
            }
        }
    }

    init() {
        selectedIndex = Self.loadSelectedPresetIndex(from: presets)
        currentVariant = presets[selectedIndex].defaultVariant
        audioEngine.setVolume(volume)
        systemMediaControls.install(
            play: { [weak self] in
                guard let self, !self.isPlaying else { return }
                self.isPlaying = true
            },
            pause: { [weak self] in
                guard let self, self.isPlaying else { return }
                self.isPlaying = false
            },
            togglePlayPause: { [weak self] in
                self?.togglePlayback()
            },
            nextTrack: { [weak self] in
                self?.nextStation()
            },
            previousTrack: { [weak self] in
                self?.previousStation()
            }
        )
        refreshSystemMediaControls()
        // Mirror AVPlayer's transport status into a published flag. We only
        // surface "buffering" while the user actually wants playback —
        // otherwise a freshly-initialized .paused player would briefly read
        // as "loading" before they ever press play.
        audioEngine.onPlaybackStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .buffering:
                self.isBuffering = self.isPlaying
                self.schedulePlaybackRecovery(.hardReload)
            case .playing, .stopped:
                self.isBuffering = false
                if state == .playing {
                    self.cancelPlaybackRecovery()
                } else {
                    self.schedulePlaybackRecovery(.softResume)
                }
            }
        }
        audioEngine.onPlaybackStallDetected = { [weak self] reason in
            guard let self else { return }
            self.logger.info("Playback stall signal reason=\(reason, privacy: .public)")
            self.isBuffering = self.isPlaying
            self.schedulePlaybackRecovery(.hardReload)
        }

        syncPlayback()

        currentGifIndex = Int.random(in: 0..<max(gifAssets.count, 1))

        Task {
            await loadLiveTrack(replacingCurrentItem: true)
        }
        Task.detached(priority: .background) {
            await GifCache.shared.prefetchStatics()
        }

        refreshBongoImportedModels()
        if bongoOverlayVisible {
            markBongoLive2DPending()
            resetVisualStageLoadingGate(updateBongoLayer: false)
        }
        refreshVisualStageReady()
    }

    func refreshBongoImportedModels() {
        bongoImportedModelFolderNames = BongoCatPack.listImportedFolderNames()
    }

    /// Rescans `~/.lofii/bongo/`, invalidates missing user packs to the default bundled model, then remounts the Bongo Live2D stage.
    func reloadBongoModelsFromDisk() {
        refreshBongoImportedModels()
        if case .imported(let folderName) = bongoCatPack {
            let root = BongoCatPack.importedPackRoot(folderName: folderName)
            if !BongoCatPack.isValidImportedPackRoot(root) {
                bongoCatPack = .bundled(BongoCatModelKind.bundledDefault)
            }
        }
        bongoPackReloadToken &+= 1
        if bongoOverlayVisible {
            markBongoLive2DPending()
        }
    }

    var currentGif: GifAsset? {
        guard !gifAssets.isEmpty else { return nil }
        let idx = ((currentGifIndex % gifAssets.count) + gifAssets.count) % gifAssets.count
        return gifAssets[idx]
    }

    var currentPreset: LofiiPreset {
        presets[selectedIndex]
    }

    var currentScene: SceneAsset {
        currentPreset.scene
    }

    var accent: Color {
        currentScene.palette.accent
    }

    private func refreshSystemMediaControls() {
        systemMediaControls.update(
            station: currentPreset.radio,
            scene: currentScene,
            variant: currentVariant,
            track: currentTrack,
            isPlaying: isPlaying
        )
    }

    func togglePlayback() {
        isPlaying.toggle()
    }

    func selectPreset(at index: Int) {
        guard presets.indices.contains(index) else { return }
        selectedIndex = index
    }

    func previousStation() {
        selectedIndex = (selectedIndex + presets.count - 1) % presets.count
    }

    func nextStation() {
        selectedIndex = (selectedIndex + 1) % presets.count
    }

    func cycleVariant() {
        let all = SceneVariant.allCases
        guard let idx = all.firstIndex(of: currentVariant) else {
            currentVariant = .day
            return
        }
        currentVariant = all[(idx + 1) % all.count]
    }

    func toggleVisualMode() {
        let all = VisualMode.allCases
        guard let idx = all.firstIndex(of: visualMode) else {
            visualMode = .cinematic
            return
        }
        visualMode = all[(idx + 1) % all.count]
    }

    func toggleBongoOverlay() {
        bongoOverlayVisible.toggle()
    }

    var isBongoDesktopMaskEnabled: Bool {
        bongoDesktopMaskTint != .hidden
    }

    func toggleBongoDesktopMask() {
        bongoDesktopMaskTint = isBongoDesktopMaskEnabled ? .hidden : .modelDynamic
    }

    func nextGif() {
        guard !gifAssets.isEmpty else { return }
        currentGifIndex = (currentGifIndex + 1) % gifAssets.count
    }

    func setWidgetWindowVisible(_ visible: Bool) {
        isWidgetVisible = visible
    }

    private func syncPlayback() {
        if isPlaying {
            // Optimistically flip the spinner on so the play button responds
            // the instant it's pressed, even before AVPlayer's KVO catches
            // up. The `onPlaybackStateChange` callback will clear it once
            // .playing fires (or keep it on if we're really still buffering).
            isBuffering = true
            refreshLiveTrackLoop()
            refreshPlaybackWatchdog()
            Task {
                if currentTrack == nil {
                    await loadLiveTrack(replacingCurrentItem: true)
                } else {
                    playCurrentTrack(replacingCurrentItem: false)
                }
            }
        } else {
            cancelPlaybackRecovery()
            pauseChillhopTransition()
            audioEngine.stop(reason: "user-paused")
            isBuffering = false
            streamStatus = "Paused"
            refreshLiveTrackLoop()
            refreshPlaybackWatchdog()
        }
    }

    /// Starts a 20s poll while playing; clears the timer when paused so we
    /// do not keep hitting Chillhop/Radio.co APIs in the background.
    private func refreshLiveTrackLoop() {
        streamRefreshTimer?.invalidate()
        streamRefreshTimer = nil
        guard isPlaying else { return }
        streamRefreshTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.loadLiveTrack(replacingCurrentItem: false)
            }
        }
    }

    private func refreshPlaybackWatchdog() {
        playbackWatchdogTimer?.invalidate()
        playbackWatchdogTimer = nil
        lastPlaybackWatchdogSample = nil
        stalledPlaybackWatchdogTicks = 0

        guard isPlaying else { return }
        playbackWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluatePlaybackWatchdog()
            }
        }
    }

    private func evaluatePlaybackWatchdog() {
        guard isPlaying, let currentTrack else {
            lastPlaybackWatchdogSample = nil
            stalledPlaybackWatchdogTicks = 0
            return
        }

        let sample = audioEngine.playbackSample()
        defer { lastPlaybackWatchdogSample = sample }

        guard sample.hasItem else {
            stalledPlaybackWatchdogTicks = 0
            return
        }

        if sample.itemFailed {
            let error = sample.errorDescription ?? "nil"
            logger.error("Playback watchdog saw failed item error=\(error, privacy: .public)")
            isBuffering = true
            schedulePlaybackRecovery(.hardReload)
            return
        }

        if sample.isWaiting || sample.isBufferEmpty {
            stalledPlaybackWatchdogTicks = 0
            return
        }

        guard !currentTrack.isSynchronizedLiveStream, sample.isPlaying else {
            stalledPlaybackWatchdogTicks = 0
            return
        }

        guard let previous = lastPlaybackWatchdogSample,
              previous.itemID == sample.itemID,
              let previousTime = previous.currentTime,
              let currentTime = sample.currentTime
        else {
            stalledPlaybackWatchdogTicks = 0
            return
        }

        if currentTime - previousTime > 0.2 {
            stalledPlaybackWatchdogTicks = 0
            return
        }

        stalledPlaybackWatchdogTicks += 1
        guard stalledPlaybackWatchdogTicks >= 3 else { return }

        logger.info(
            "Playback watchdog detected no progress title=\(currentTrack.title, privacy: .public) time=\(currentTime, format: .fixed(precision: 2)) rate=\(sample.rate, format: .fixed(precision: 2)) likely=\(sample.isLikelyToKeepUp)"
        )
        stalledPlaybackWatchdogTicks = 0
        isBuffering = true
        schedulePlaybackRecovery(.softResume)
    }

    private func loadLiveTrack(replacingCurrentItem: Bool) async {
        switch currentPreset.radio.source {
        case let .chillhop(stationID):
            do {
                let playlist = try await chillhopService.fetchLiveTracks(stationID: stationID)
                guard let playlistIndex = playlist.liveTrackIndex() else {
                    currentTrack = nil
                    streamStatus = "Stream unavailable"
                    return
                }

                if replacingCurrentItem || currentTrack == nil || !currentPreset.radio.source.isChillhop {
                    let liveTrack = playlist[playlistIndex]
                    currentTrack = liveTrack
                    chillhopQueue = Array(playlist.dropFirst(playlistIndex + 1))
                    prepareUpcomingChillhopTrack()

                    if isPlaying {
                        playCurrentTrack(replacingCurrentItem: true)
                    } else {
                        scheduleChillhopTransition(for: liveTrack, elapsed: liveTrack.elapsedPlaybackSeconds())
                        streamStatus = "Ready · \(liveTrack.title)"
                    }
                } else {
                    refillChillhopQueue(with: playlist)
                }
            } catch {
                resetChillhopPlaybackState()
                currentTrack = nil
                streamStatus = "Stream unavailable"
            }
        case let .directStream(trackID, url):
            resetChillhopPlaybackState(clearPreparedTrack: false)
            let streamTrack = LiveTrack.directStream(
                id: trackID,
                title: currentPreset.radio.displayName,
                artists: currentPreset.radio.badgeSubtitle,
                streamURL: url
            )
            let trackChanged = currentTrack?.id != streamTrack.id || currentTrack?.streamURL != streamTrack.streamURL
            if trackChanged {
            }
            currentTrack = streamTrack

            if isPlaying {
                playCurrentTrack(replacingCurrentItem: replacingCurrentItem || trackChanged)
            } else {
                streamStatus = "Ready · \(currentPreset.radio.displayName)"
            }
        case let .radioCo(trackID, stationID):
            resetChillhopPlaybackState(clearPreparedTrack: false)
            do {
                let snapshot = try await radioCoService.fetchSnapshot(
                    stationID: stationID,
                    trackID: trackID,
                    fallbackTitle: currentPreset.radio.displayName,
                    fallbackArtists: currentPreset.radio.badgeSubtitle
                )
                let streamTrack = snapshot.track
                let trackChanged =
                    currentTrack?.id != streamTrack.id ||
                    currentTrack?.streamURL != streamTrack.streamURL

                currentTrack = streamTrack

                if isPlaying {
                    if replacingCurrentItem || trackChanged {
                        playCurrentTrack(replacingCurrentItem: true)
                    } else {
                        prepareLiveBackupIfNeeded(for: streamTrack, reason: "refresh radio backup")
                        streamStatus = "Live stream · \(streamTrack.title)"
                    }
                } else {
                    streamStatus = "Ready · \(streamTrack.title)"
                }
            } catch {
                logger.error("Radio.co snapshot fetch failed station=\(stationID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                if replacingCurrentItem || currentTrack == nil {
                    currentTrack = nil
                    streamStatus = "Stream unavailable"
                }
            }
        }
    }

    private func playCurrentTrack(replacingCurrentItem: Bool) {
        guard let currentTrack else {
            streamStatus = "Loading track…"
            return
        }

        let shouldBootstrapChillhopPosition = currentPreset.radio.source.isChillhop && replacingCurrentItem
        let elapsed = shouldBootstrapChillhopPosition ? currentTrack.elapsedPlaybackSeconds() : 0
        let reason = playbackStartReason(for: currentTrack, replacingCurrentItem: replacingCurrentItem)
        audioEngine.play(
            track: currentTrack,
            elapsed: elapsed,
            replacingCurrentItem: replacingCurrentItem,
            shouldSeekToElapsed: shouldBootstrapChillhopPosition,
            reason: reason
        )
        prepareLiveBackupIfNeeded(for: currentTrack, reason: "play current track")
        if currentTrack.isSynchronizedLiveStream {
            if replacingCurrentItem {
                scheduleChillhopTransition(for: currentTrack, elapsed: elapsed)
            } else {
                resumeChillhopTransitionIfNeeded()
            }
            streamStatus = "Now playing · \(currentTrack.title)"
        } else {
            streamStatus = "Live stream · \(currentTrack.title)"
        }
    }

    private func refillChillhopQueue(with playlist: [LiveTrack]) {
        let combined = chillhopQueue + playlist
        chillhopQueue = deduplicatedTracks(
            combined.filter { track in
                track.id != currentTrack?.id
            }
        )
        prepareUpcomingChillhopTrack()

        if let currentTrack, chillhopTransitionTimer == nil, chillhopTransitionRemaining == nil {
            scheduleChillhopTransition(for: currentTrack, elapsed: 0)
        }
    }

    private func prepareUpcomingChillhopTrack() {
        guard currentPreset.radio.source.isChillhop else {
            audioEngine.clearPreparedTrack(reason: "not chillhop")
            return
        }

        guard let nextTrack = chillhopQueue.first else {
            audioEngine.clearPreparedTrack(reason: "chillhop queue empty")
            return
        }

        audioEngine.prepareNext(track: nextTrack, reason: "prepare upcoming chillhop")
    }

    private func prepareLiveBackupIfNeeded(for track: LiveTrack, reason: String) {
        guard currentPreset.radio.source.usesLiveBackup else { return }
        guard isPlaying, !track.isSynchronizedLiveStream else { return }
        audioEngine.prepareLiveBackup(track: track, reason: reason)
    }

    private func scheduleChillhopTransition(for track: LiveTrack, elapsed: TimeInterval) {
        guard currentPreset.radio.source.isChillhop else {
            resetChillhopPlaybackState()
            return
        }

        chillhopTransitionTimer?.invalidate()
        chillhopTransitionTimer = nil
        chillhopTransitionFireDate = nil

        guard !chillhopQueue.isEmpty else {
            chillhopTransitionRemaining = nil
            audioEngine.clearPreparedTrack(reason: "chillhop queue empty for transition")
            return
        }

        let remaining = max(track.duration - elapsed - Self.chillhopCrossfadeDuration, 0.05)
        chillhopTransitionRemaining = remaining

        guard isPlaying else { return }

        let fireDate = Date().addingTimeInterval(remaining)
        chillhopTransitionFireDate = fireDate
        chillhopTransitionTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.beginChillhopTransition()
            }
        }
    }

    private func pauseChillhopTransition() {
        guard currentPreset.radio.source.isChillhop else { return }
        if let fireDate = chillhopTransitionFireDate {
            chillhopTransitionRemaining = max(fireDate.timeIntervalSinceNow, 0.05)
        }
        chillhopTransitionTimer?.invalidate()
        chillhopTransitionTimer = nil
        chillhopTransitionFireDate = nil
    }

    private func resumeChillhopTransitionIfNeeded() {
        guard currentPreset.radio.source.isChillhop else { return }
        guard chillhopTransitionTimer == nil else { return }
        guard !chillhopQueue.isEmpty else { return }
        guard let remaining = chillhopTransitionRemaining else { return }

        let delay = max(remaining, 0.05)
        chillhopTransitionRemaining = delay
        chillhopTransitionFireDate = Date().addingTimeInterval(delay)
        chillhopTransitionTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.beginChillhopTransition()
            }
        }
    }

    private func beginChillhopTransition() {
        guard currentPreset.radio.source.isChillhop else { return }
        guard let nextTrack = chillhopQueue.first else {
            chillhopTransitionRemaining = nil
            return
        }

        chillhopTransitionTimer?.invalidate()
        chillhopTransitionTimer = nil
        chillhopTransitionFireDate = nil
        chillhopTransitionRemaining = nil
        chillhopQueue.removeFirst()

        let didCrossfade = audioEngine.crossfadeToPreparedTrack(
            duration: Self.chillhopCrossfadeDuration,
            reason: "chillhop crossfade"
        )
        currentTrack = nextTrack

        if !didCrossfade {
            audioEngine.play(
                track: nextTrack,
                elapsed: 0,
                replacingCurrentItem: true,
                shouldSeekToElapsed: false,
                reason: "chillhop crossfade fallback"
            )
        }

        prepareUpcomingChillhopTrack()
        scheduleChillhopTransition(for: nextTrack, elapsed: 0)
        streamStatus = "Now playing · \(nextTrack.title)"

        if chillhopQueue.count < Self.chillhopQueueLowWatermark {
            Task {
                await loadLiveTrack(replacingCurrentItem: false)
            }
        }
    }

    private func resetChillhopPlaybackState(clearPreparedTrack: Bool = true) {
        chillhopQueue.removeAll()
        chillhopTransitionRemaining = nil
        chillhopTransitionFireDate = nil
        chillhopTransitionTimer?.invalidate()
        chillhopTransitionTimer = nil
        if clearPreparedTrack {
            audioEngine.clearPreparedTrack(reason: "reset chillhop playback state")
        }
    }

    private func schedulePlaybackRecovery(_ step: PlaybackRecoveryStep) {
        guard isPlaying, currentTrack != nil else {
            cancelPlaybackRecovery()
            return
        }
        guard pendingPlaybackRecovery != step else { return }

        playbackRecoveryTask?.cancel()
        pendingPlaybackRecovery = step
        playbackRecoveryTask = Task { [weak self] in
            let delay = UInt64(step.delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await self?.performPlaybackRecovery(step)
        }
    }

    private func cancelPlaybackRecovery() {
        playbackRecoveryTask?.cancel()
        playbackRecoveryTask = nil
        pendingPlaybackRecovery = nil
    }

    private func performPlaybackRecovery(_ step: PlaybackRecoveryStep) async {
        playbackRecoveryTask = nil
        pendingPlaybackRecovery = nil

        guard isPlaying, let currentTrack else { return }

        isBuffering = true
        streamStatus = reconnectingStatus(for: currentTrack)

        switch step {
        case .softResume:
            if audioEngine.retryCurrentItem(reason: "playback recovery soft resume") {
                schedulePlaybackRecovery(.hardReload)
            } else {
                await performPlaybackRecovery(.hardReload)
            }
        case .hardReload:
            if promoteLiveBackupIfPossible(for: currentTrack) {
                return
            }
            await loadLiveTrack(replacingCurrentItem: true)
        }
    }

    private func promoteLiveBackupIfPossible(for track: LiveTrack) -> Bool {
        guard currentPreset.radio.source.usesLiveBackup else { return false }
        guard !track.isSynchronizedLiveStream else { return false }
        guard audioEngine.promotePreparedLiveBackup(reason: "playback recovery hard reload") else {
            return false
        }

        isBuffering = false
        streamStatus = "Live stream · \(track.title)"
        prepareLiveBackupIfNeeded(for: track, reason: "refresh live backup after promotion")
        return true
    }

    private func reconnectingStatus(for track: LiveTrack) -> String {
        let prefix = track.isSynchronizedLiveStream ? "Track stalled" : "Stream stalled"
        return "\(prefix) · reconnecting…"
    }

    private func deduplicatedTracks(_ tracks: [LiveTrack]) -> [LiveTrack] {
        var seen = Set<Int>()
        return tracks.filter { track in
            seen.insert(track.id).inserted
        }
    }

    private func playbackStartReason(for track: LiveTrack, replacingCurrentItem: Bool) -> String {
        replacingCurrentItem
            ? (track.isSynchronizedLiveStream ? "replace-chillhop-live" : "replace-stream-item")
            : "continue-playback"
    }
}
