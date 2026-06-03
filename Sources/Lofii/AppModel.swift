import AppKit
import Foundation
import OSLog
import SwiftUI

enum VisualMode: String, CaseIterable, Identifiable, Sendable {
    case live
    case scene
    case media

    var id: String { rawValue }

    var label: String {
        switch self {
        case .live:  return "Live"
        case .scene: return "Scene"
        case .media: return "Media"
        }
    }

    var glyph: PixelGlyph {
        switch self {
        case .live:  return .airplaySharp
        case .scene: return .buildingCommunitySharp
        case .media: return .imageSharp
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
        let base = mode == .scene ? 0.18 : 0.30
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
        case .subtle: return 0.20
        case .balanced: return 0.31
        case .strong: return 0.42
        }
    }

    var resolvedRefraction: Double {
        switch self {
        case .subtle: return 4
        case .balanced: return 7
        case .strong: return 10
        }
    }

    var resolvedHighlight: Double {
        switch self {
        case .subtle: return 0.13
        case .balanced: return 0.20
        case .strong: return 0.28
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

enum ReadoutWaveformStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case randomEQ
    case retroPulse
    case oscilloscopeBars
    case phaseBars

    var id: String { rawValue }

    var label: String {
        switch self {
        case .randomEQ: return "Random EQ"
        case .retroPulse: return "Retro Pulse"
        case .oscilloscopeBars: return "Osc Bars"
        case .phaseBars: return "Phase Bars"
        }
    }

    var menuLabel: String {
        switch self {
        case .randomEQ: return "Random EQ"
        case .retroPulse: return "Retro Pulse"
        case .oscilloscopeBars: return "Oscilloscope Bars"
        case .phaseBars: return "Phase Bars"
        }
    }
}

struct ReadoutFontSettings: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case weight
        case elementShape
        case slant
        case waveform
        case waveformStyle
        case textShadow
        case textGlow
    }

    var weight: ReadoutFontWeight = .medium
    var elementShape: ReadoutFontElementShape = .square
    var slant: ReadoutFontSlant = .upright
    /// Mini spectrum above the station name (Readout menu).
    var waveform: Bool = true
    var waveformStyle: ReadoutWaveformStyle = .retroPulse
    /// Black drop shadow under readout glyphs; independent of Readout ▸ Text Glow.
    var textShadow: Bool = true
    /// Colored bloom on readout text and waveform.
    var textGlow: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weight = (try? container.decodeIfPresent(ReadoutFontWeight.self, forKey: .weight)) ?? .medium
        elementShape = (try? container.decodeIfPresent(ReadoutFontElementShape.self, forKey: .elementShape)) ?? .square
        slant = (try? container.decodeIfPresent(ReadoutFontSlant.self, forKey: .slant)) ?? .upright
        waveform = (try? container.decodeIfPresent(Bool.self, forKey: .waveform)) ?? true
        waveformStyle = (try? container.decodeIfPresent(ReadoutWaveformStyle.self, forKey: .waveformStyle)) ?? .retroPulse
        textShadow = (try? container.decodeIfPresent(Bool.self, forKey: .textShadow)) ?? true
        textGlow = (try? container.decodeIfPresent(Bool.self, forKey: .textGlow)) ?? true
    }
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
    /// Default preset (`standard`) from [ayangweb/BongoCat](https://github.com/ayangweb/BongoCat).
    case standard

    /// Bundled model when preferences are absent or not recognized.
    static let bundledDefault: BongoCatModelKind = .standard

    var menuLabel: String {
        switch self {
        case .standard: return "BongoCat"
        }
    }

    /// Subfolder under `BongoCat/` in the module resource bundle.
    var bundleFolderName: String {
        switch self {
        case .standard: return "standard"
        }
    }

    /// MOC filename stem (without `.moc3`) for native bootstrap diagnostics.
    var mocStem: String {
        switch self {
        case .standard: return "demomodel"
        }
    }

    static let modelSettingFileName = "cat.model3.json"

    var resourcesSubdirectory: String {
        "BongoCat/\(bundleFolderName)/resources"
    }

    var leftKeysSubdirectory: String {
        "\(resourcesSubdirectory)/left-keys"
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

/// Free placement for the fitted Bongo stage, stored as a ratio within the
/// available layout range so it survives widget and model-size changes.
struct BongoStageOriginRatio: Codable, Equatable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }

    init(origin: CGPoint, container: CGSize, stage: CGSize) {
        let maxX = max(0, container.width - stage.width)
        let maxY = max(0, container.height - stage.height)
        self.init(
            x: maxX > 0 ? origin.x / maxX : 0,
            y: maxY > 0 ? origin.y / maxY : 0
        )
    }

    func resolvedOrigin(in container: CGSize, stage: CGSize) -> CGPoint {
        let maxX = max(0, container.width - stage.width)
        let maxY = max(0, container.height - stage.height)
        return CGPoint(
            x: min(max(CGFloat(x) * maxX, 0), maxX),
            y: min(max(CGFloat(y) * maxY, 0), maxY)
        )
    }
}

struct BongoStagePlacement: Codable, Equatable, Sendable {
    var anchor: BongoStageAnchor
    var customOriginRatio: BongoStageOriginRatio?

    static let `default` = BongoStagePlacement(anchor: .bottomLeading, customOriginRatio: nil)
}

/// User scale for the Bongo Live2D stage (logical points cap before fitting).
enum BongoStageScaleTier: String, CaseIterable, Identifiable, Codable, Sendable {
    case small
    case medium
    case large

    var id: String { rawValue }

    /// Multiplier applied to the pack's logical stage size.
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

/// How Live2D `ParamMouseX` / `ParamMouseY` are normalized from the system pointer.
enum BongoMouseCursorSpace: String, CaseIterable, Identifiable, Codable, Sendable {
    /// 0…1 within the display that currently contains the cursor (multi-monitor friendly).
    case currentDisplay
    /// 0…1 across the bounding box of every `NSScreen` (whole virtual desktop).
    case allDisplays

    var id: String { rawValue }

    var menuLabel: String {
        switch self {
        case .currentDisplay: return "Current display"
        case .allDisplays: return "All displays"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    private static let chillhopCrossfadeDuration: TimeInterval = 2.8
    private static let chillhopQueueLowWatermark = 3
    private static let playbackWatchdogInterval: TimeInterval = 2
    private static let playbackStallTickThreshold = 3

    @Published private(set) var presets = LofiiPreset.presets
    @Published private(set) var customStations: [CustomStation] = []
    @Published private(set) var builtInStationOverrides: [BuiltInStationOverride] = []
    @Published private(set) var gifAssets = GifSceneCatalog.animated
    @Published private(set) var userVisualMediaAssets: [VisualMediaAsset] = UserVisualMediaLibrary.listImportedMedia()
    @Published private(set) var visualMediaReloadToken: UInt = 0
    @Published var visualMediaLibraryScope: VisualMediaLibraryScope = AppModel.loadVisualMediaLibraryScope() {
        didSet {
            guard visualMediaLibraryScope != oldValue else { return }
            UserDefaults.standard.set(visualMediaLibraryScope.rawValue, forKey: Self.visualMediaLibraryScopeKey)
            ensureCurrentVisualMediaSelection()
            if visualMode == .media {
                resetVisualStageLoadingGate(updateBongoLayer: false)
            }
        }
    }
    @Published var currentVisualMediaID: String? = AppModel.loadCurrentVisualMediaID() {
        didSet {
            guard currentVisualMediaID != oldValue else { return }
            if let currentVisualMediaID {
                UserDefaults.standard.set(currentVisualMediaID, forKey: Self.currentVisualMediaIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.currentVisualMediaIDKey)
            }
            if visualMode == .media {
                resetVisualStageLoadingGate(updateBongoLayer: false)
            }
        }
    }
    @Published var currentSceneID: String? = AppModel.loadCurrentSceneID() {
        didSet {
            guard currentSceneID != oldValue else { return }
            if let currentSceneID {
                UserDefaults.standard.set(currentSceneID, forKey: Self.currentSceneIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.currentSceneIDKey)
            }
            refreshSystemMediaControls()
            if visualMode == .scene {
                resetVisualStageLoadingGate(updateBongoLayer: false)
            }
        }
    }
    @Published var selectedIndex = 0 {
        didSet {
            guard selectedIndex != oldValue else { return }
            activateSelectedPreset()
        }
    }
    @Published var currentVariant: SceneVariant = .nightRain {
        didSet {
            refreshSystemMediaControls()
            if visualMode == .scene {
                resetVisualStageLoadingGate(updateBongoLayer: false)
            }
        }
    }
    @Published var visualMode: VisualMode = AppModel.loadVisualMode() {
        didSet {
            guard visualMode != oldValue else { return }
            UserDefaults.standard.set(visualMode.rawValue, forKey: Self.visualModeKey)
            if visualMode == .media {
                Task { await GifCache.shared.prefetchStatics() }
            }
            resetVisualStageLoadingGate(updateBongoLayer: false)
        }
    }

    /// Live2D Bongo overlay on top of the current visual background. Toggled from the right-click menu.
    @Published var bongoOverlayVisible: Bool = AppModel.loadBongoOverlayVisible() {
        didSet {
            guard bongoOverlayVisible != oldValue else { return }
            UserDefaults.standard.set(bongoOverlayVisible, forKey: Self.bongoOverlayVisibleKey)
            if bongoOverlayVisible {
                BongoInputMonitor.requestAccessibilityTrustPromptIfNeeded()
                markBongoLive2DPending()
                if !liveModeUsesEmbeddedVideoBackground {
                    resetVisualStageLoadingGate(updateBongoLayer: false)
                }
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
    @Published var currentVisualMediaIndex: Int = 0 {
        didSet {
            guard currentVisualMediaIndex != oldValue else { return }
            guard visualMode == .media else { return }
            // Swapping the media index only invalidates primary media — Live2D
            // stays mounted, so we must not reset the Bongo layer gate.
            resetVisualStageLoadingGate(updateBongoLayer: false)
        }
    }

    // MARK: - Visual stage loading (global snow gate)

    /// True when every **tracked** contributor for the current layout is ready
    /// so the global loading snow can hide. Tracking is active in Live/Media mode
    /// or whenever Bongo is on (then primary media is the Bongo background and
    /// Bongo adds a Live2D dependency). Scene without Bongo handles its own
    /// transition.
    @Published private(set) var visualStageReady: Bool = true

    /// Primary media used by `VisualMediaSceneView` or the Bongo unified stage.
    private var primaryVisualMediaReady: Bool = false
    /// Live2D runtime for Bongo; ignored when `bongoOverlayVisible` is false.
    private var bongoLive2DReady: Bool = true

    private func refreshVisualStageReady() {
        let tracksLoading = bongoOverlayVisible || visualMode == .media || visualMode == .live
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
            DiagnosticLog.appendPlayback(
                "model.isPlaying value=\(isPlaying) preset=\(currentPreset.id) source=\(currentPreset.radio.source.stableID)"
            )
            syncPlayback()
            refreshSystemMediaControls()
        }
    }
    @Published var volume = 0.58 {
        didSet {
            audioEngine.setVolume(volume)
            DiagnosticLog.appendPlayback("model.volume value=\(volume)")
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
            if visualMode == .live, currentTrack?.image != oldValue?.image {
                if liveModeUsesTrackArtworkBackground {
                    resetVisualStageLoadingGate(updateBongoLayer: false)
                }
            }
        }
    }
    @Published var streamStatus = "Connecting…"
    /// True while the user has asked us to play but the network/AVPlayer
    /// pipeline is still spinning up (initial connect or mid-stream rebuffer).
    /// Drives the spinner overlay on the play/pause button.
    @Published private(set) var isBuffering = false
    @Published private(set) var isYouTubeBuffering = false
    @Published private(set) var isTwitchBuffering = false
    @Published private(set) var isTwitchUnavailable = false
    @Published private(set) var isBilibiliLiveBuffering = false
    @Published private(set) var isBilibiliLiveUnavailable = false
    /// UI-level visibility gate for high-frequency visual rendering work.
    /// When false (widget hidden via menubar), scene/gif playback and
    /// animated overlays pause to reduce CPU/GPU usage.
    @Published private(set) var isWidgetVisible = true

    /// Single gate for non-Bongo MTK-backed stages and media decode: pauses when transport is
    /// stopped or the widget is off-screen (`isWidgetVisible` false).
    var shouldRenderStageMotion: Bool { isPlaying && isWidgetVisible }

    /// Bongo is an input companion, not transport artwork. Keep its Live2D stage moving while
    /// music is paused, but still pause it when the widget is hidden/off-screen.
    var shouldRenderBongoMotion: Bool { isWidgetVisible }

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
            if bongoOverlayVisible {
                markBongoLive2DPending()
            }
        }
    }

    /// Names of valid packs under `~/.lofii/bongo/<name>/` (see `BongoCatPack.listImportedFolderNames()`).
    @Published private(set) var bongoImportedModelFolderNames: [String] = BongoCatPack.listImportedFolderNames()

    /// Bumped on `reloadBongoModelsFromDisk()` so `BongoView` tears down Live2D / Metal state and reloads from disk.
    @Published private(set) var bongoPackReloadToken: UInt = 0

    @Published var bongoStagePlacement: BongoStagePlacement = AppModel.loadBongoStagePlacement() {
        didSet {
            guard bongoStagePlacement != oldValue else { return }
            if let data = try? JSONEncoder().encode(bongoStagePlacement) {
                UserDefaults.standard.set(data, forKey: Self.bongoStagePlacementKey)
            }
            UserDefaults.standard.set(bongoStagePlacement.anchor.rawValue, forKey: Self.bongoStageAnchorKey)
        }
    }

    @Published var bongoStageDragLocked: Bool = AppModel.loadBongoStageDragLocked() {
        didSet {
            guard bongoStageDragLocked != oldValue else { return }
            UserDefaults.standard.set(bongoStageDragLocked, forKey: Self.bongoStageDragLockedKey)
        }
    }

    var bongoStageAnchor: BongoStageAnchor {
        get { bongoStagePlacement.anchor }
        set { selectBongoStageAnchor(newValue) }
    }

    var hasCustomBongoStagePlacement: Bool {
        bongoStagePlacement.customOriginRatio != nil
    }

    func selectBongoStageAnchor(_ anchor: BongoStageAnchor) {
        bongoStagePlacement = BongoStagePlacement(anchor: anchor, customOriginRatio: nil)
    }

    func setBongoStageCustomOriginRatio(_ ratio: BongoStageOriginRatio) {
        bongoStagePlacement = BongoStagePlacement(anchor: bongoStagePlacement.anchor, customOriginRatio: ratio)
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

    @Published var bongoMouseCursorSpace: BongoMouseCursorSpace = AppModel.loadBongoMouseCursorSpace() {
        didSet {
            guard bongoMouseCursorSpace != oldValue else { return }
            UserDefaults.standard.set(bongoMouseCursorSpace.rawValue, forKey: Self.bongoMouseCursorSpaceKey)
        }
    }

    private static let badgeSizeKey = "lofii.badgeSize"
    private static let readoutVisibleKey = "lofii.readoutVisible"
    private static let badgePositionKey = "lofii.badgePosition"
    private static let crtSettingsKey = "lofii.crtSettings"
    private static let shatteredGlassSettingsKey = "lofii.shatteredGlassSettings"
    private static let readoutFontSettingsKey = "lofii.readoutFontSettings"
    private static let visualModeKey = "lofii.visualMode"
    private static let currentSceneIDKey = "lofii.currentSceneID"
    private static let bongoOverlayVisibleKey = "lofii.bongoOverlayVisible"
    private static let debugModeEnabledKey = "lofii.debugModeEnabled"
    private static let bongoDesktopMaskTintKey = "lofii.bongoDesktopMaskTint"
    private static let bongoCatPackSelectionKey = "lofii.bongoCatPackSelection"
    private static let bongoStageAnchorKey = "lofii.bongoStageAnchor"
    private static let bongoStagePlacementKey = "lofii.bongoStagePlacement"
    private static let bongoStageDragLockedKey = "lofii.bongoStageDragLocked"
    private static let bongoStageScaleTierKey = "lofii.bongoStageScaleTier"
    private static let bongoInputTickRateKey = "lofii.bongoInputTickRate"
    private static let bongoMouseCursorSpaceKey = "lofii.bongoMouseCursorSpace"
    private static let visualMediaLibraryScopeKey = "lofii.visualMediaLibraryScope"
    private static let currentVisualMediaIDKey = "lofii.currentVisualMediaID"
    private static let selectedPresetIDKey = "lofii.selectedPresetID"
    private static let alwaysOnTopKey = "lofii.alwaysOnTop"
    private static let defaultCurrentVisualMediaID = "builtin-gif:xUOwGcu6wd0cXBj5n2"

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
        else { return .topTrailing }
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
            return .media
        }
        return VisualMode(rawValue: raw) ?? .media
    }

    private static func loadBongoOverlayVisible() -> Bool {
        if UserDefaults.standard.object(forKey: bongoOverlayVisibleKey) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: bongoOverlayVisibleKey)
    }

    private static func loadDebugModeEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: debugModeEnabledKey)
    }

    private static func loadBongoDesktopMaskTint() -> BongoDesktopMaskTint {
        guard let raw = UserDefaults.standard.string(forKey: bongoDesktopMaskTintKey),
              let value = BongoDesktopMaskTint(rawValue: raw)
        else { return .dynamic }
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
        return .bundled(BongoCatModelKind.bundledDefault)
    }

    private static func loadBongoStagePlacement() -> BongoStagePlacement {
        if UserDefaults.standard.data(forKey: bongoStagePlacementKey) != nil {
            return loadDecodedJSON(
                BongoStagePlacement.self,
                key: bongoStagePlacementKey,
                default: BongoStagePlacement.default
            )
        }
        return BongoStagePlacement(anchor: loadBongoStageAnchor(), customOriginRatio: nil)
    }

    private static func loadBongoStageAnchor() -> BongoStageAnchor {
        guard let raw = UserDefaults.standard.string(forKey: bongoStageAnchorKey),
              let value = BongoStageAnchor(rawValue: raw)
        else { return .bottomLeading }
        return value
    }

    private static func loadBongoStageDragLocked() -> Bool {
        if UserDefaults.standard.object(forKey: bongoStageDragLockedKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: bongoStageDragLockedKey)
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

    private static func loadBongoMouseCursorSpace() -> BongoMouseCursorSpace {
        guard let raw = UserDefaults.standard.string(forKey: bongoMouseCursorSpaceKey),
              let value = BongoMouseCursorSpace(rawValue: raw)
        else { return .allDisplays }
        return value
    }

    private static func loadVisualMediaLibraryScope() -> VisualMediaLibraryScope {
        guard let raw = UserDefaults.standard.string(forKey: visualMediaLibraryScopeKey),
              let value = VisualMediaLibraryScope(rawValue: raw)
        else { return .builtIn }
        return value
    }

    private static func loadCurrentVisualMediaID() -> String? {
        UserDefaults.standard.string(forKey: currentVisualMediaIDKey) ?? defaultCurrentVisualMediaID
    }

    private static func loadCurrentSceneID() -> String? {
        UserDefaults.standard.string(forKey: currentSceneIDKey)
    }

    private static func loadSelectedPresetIndex(from presets: [LofiiPreset]) -> Int {
        guard let presetID = UserDefaults.standard.string(forKey: selectedPresetIDKey),
              let index = presets.firstIndex(where: { $0.id == presetID })
        else { return 0 }
        return index
    }

    private static func combinedPresets(
        customStations: [CustomStation],
        builtInOverrides: [BuiltInStationOverride]
    ) -> [LofiiPreset] {
        let defaultScene = SceneCatalog.presets.first { $0.id == "chill-vibes" }
            ?? SceneCatalog.presets[0]
        let overridesByPresetID = Dictionary(uniqueKeysWithValues: builtInOverrides.map { ($0.presetID, $0) })
        let builtIns = LofiiPreset.presets.map { preset in
            overridesByPresetID[preset.id]?.apply(to: preset) ?? preset
        }
        return builtIns + customStations.map { station in
            station.lofiiPreset(defaultScene: defaultScene)
        }
    }

    private static func sourceIdentity(for source: RadioSource) -> String {
        switch source {
        case let .chillhop(stationID):
            return "chillhop:\(stationID)"
        case let .directStream(_, url):
            return "direct-audio:\(url.absoluteString)"
        case let .directVideo(_, url):
            return "direct-video:\(url.absoluteString)"
        case let .radioCo(_, stationID):
            return "radioco:\(stationID)"
        case let .bilibiliLive(roomID):
            return "bilibili-live:\(roomID)"
        case let .twitch(channelName):
            return "twitch:\(channelName)"
        case let .youtube(videoID):
            return "youtube:\(videoID)"
        }
    }

    private func activateSelectedPreset() {
        UserDefaults.standard.set(currentPreset.id, forKey: Self.selectedPresetIDKey)
        isYouTubeBuffering = false
        isTwitchBuffering = false
        isTwitchUnavailable = false
        isBilibiliLiveBuffering = false
        isBilibiliLiveUnavailable = false
        cancelPlaybackRecovery()
        resetChillhopPlaybackState()
        currentTrack = nil
        lastPlaybackWatchdogSample = nil
        stalledPlaybackWatchdogTicks = 0
        streamStatus = "Connecting…"
        refreshSystemMediaControls()
        if visualMode == .live {
            resetVisualStageLoadingGate(updateBongoLayer: false)
        }
        Task {
            await loadLiveTrack(replacingCurrentItem: true)
        }
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
    private let customStationStore = CustomStationStore()
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
        let stationDocument = customStationStore.loadDocument()
        customStations = stationDocument.stations
        builtInStationOverrides = stationDocument.builtInOverrides
        presets = Self.combinedPresets(
            customStations: customStations,
            builtInOverrides: builtInStationOverrides
        )
        selectedIndex = Self.loadSelectedPresetIndex(from: presets)
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
            if self.currentPreset.radio.source.isEmbeddedVideo {
                self.isBuffering = false
                self.cancelPlaybackRecovery()
                return
            }
            DiagnosticLog.appendPlayback(
                "model.playbackState state=\(String(describing: state)) isPlaying=\(self.isPlaying) isBuffering=\(self.isBuffering) preset=\(self.currentPreset.id) track=\"\(self.currentTrack?.title ?? "nil")\""
            )
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
            if self.currentPreset.radio.source.isEmbeddedVideo {
                self.isBuffering = false
                self.cancelPlaybackRecovery()
                return
            }
            self.logger.info("Playback stall signal reason=\(reason, privacy: .public)")
            DiagnosticLog.appendPlayback(
                "model.stallSignal reason=\"\(reason)\" \(self.playbackDiagnosticContext(sample: self.audioEngine.playbackSample()))"
            )
            self.isBuffering = self.isPlaying
            self.schedulePlaybackRecovery(.hardReload)
        }

        DiagnosticLog.appendPlayback(
            "model.launch version=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown") preset=\(currentPreset.id) source=\(currentPreset.radio.source.stableID) isPlaying=\(isPlaying) volume=\(volume)"
        )
        syncPlayback()

        currentVisualMediaIndex = Int.random(in: 0..<max(gifAssets.count, 1))
        refreshUserVisualMediaFromDisk()
        ensureCurrentVisualMediaSelection()

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

    func openBongoModelsFolder() {
        let url = BongoCatPack.userImportsRootURL()
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
        } catch {
            logger.error("Failed to open Bongo models folder: \(error.localizedDescription, privacy: .public)")
        }
    }

    var visualMediaAssets: [VisualMediaAsset] {
        switch visualMediaLibraryScope {
        case .builtIn:
            return builtInVisualMediaAssets
        case .custom:
            return userVisualMediaAssets
        case .all:
            return builtInVisualMediaAssets + userVisualMediaAssets
        }
    }

    private var builtInVisualMediaAssets: [VisualMediaAsset] {
        gifAssets.map(VisualMediaAsset.builtInGif)
    }

    private var effectiveVisualMediaAssets: [VisualMediaAsset] {
        let assets = visualMediaAssets
        return assets.isEmpty ? builtInVisualMediaAssets : assets
    }

    var effectiveVisualMediaChoices: [VisualMediaAsset] {
        effectiveVisualMediaAssets
    }

    var currentVisualMedia: VisualMediaAsset? {
        let assets = effectiveVisualMediaAssets
        guard !assets.isEmpty else { return nil }
        if let currentVisualMediaID,
           let selected = assets.first(where: { $0.id == currentVisualMediaID }) {
            return selected
        }
        let idx = ((currentVisualMediaIndex % assets.count) + assets.count) % assets.count
        return assets[idx]
    }

    var currentVisualMediaLabel: String {
        currentVisualMedia?.displayName ?? "Built-in Media"
    }

    var hasCustomVisualMedia: Bool {
        !userVisualMediaAssets.isEmpty
    }

    func refreshUserVisualMediaFromDisk() {
        userVisualMediaAssets = UserVisualMediaLibrary.listImportedMedia()
        logVisualMedia(
            "scan scope=\(visualMediaLibraryScope.rawValue) customCount=\(userVisualMediaAssets.count) first=\"\(userVisualMediaAssets.first?.displayName ?? "nil")\" root=\"\(UserVisualMediaLibrary.userImportsRootURL().path)\""
        )
    }

    func reloadUserVisualMediaFromDisk() {
        refreshUserVisualMediaFromDisk()
        ensureCurrentVisualMediaSelection()
        visualMediaReloadToken &+= 1
        logVisualMedia(
            "reload token=\(visualMediaReloadToken) scope=\(visualMediaLibraryScope.rawValue) selected=\"\(currentVisualMediaID ?? "nil")\" effectiveCount=\(effectiveVisualMediaAssets.count)"
        )
        if visualMode == .media {
            resetVisualStageLoadingGate(updateBongoLayer: false)
        }
    }

    func openUserVisualMediaFolder() {
        let url = UserVisualMediaLibrary.userImportsRootURL()
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
        } catch {
            logger.error("Failed to open user media folder: \(error.localizedDescription, privacy: .public)")
        }
    }

    func selectVisualMedia(_ asset: VisualMediaAsset) {
        setCurrentVisualMediaID(asset.id, reason: "explicit-select")
        if let index = effectiveVisualMediaAssets.firstIndex(of: asset) {
            currentVisualMediaIndex = index
        }
        if visualMode != .media {
            visualMode = .media
        }
    }

    private func ensureCurrentVisualMediaSelection() {
        let assets = effectiveVisualMediaAssets
        guard !assets.isEmpty else {
            setCurrentVisualMediaID(nil, reason: "no-effective-assets")
            return
        }
        if let currentVisualMediaID,
           assets.contains(where: { $0.id == currentVisualMediaID }) {
            logVisualMedia(
                "selection-kept reason=existing scope=\(visualMediaLibraryScope.rawValue) selected=\"\(currentVisualMediaID)\" effectiveCount=\(assets.count)"
            )
            return
        }
        let idx = ((currentVisualMediaIndex % assets.count) + assets.count) % assets.count
        setCurrentVisualMediaID(assets[idx].id, reason: "repair-missing-selection")
    }

    private func setCurrentVisualMediaID(_ id: String?, reason: String) {
        currentVisualMediaID = id
        if let id {
            UserDefaults.standard.set(id, forKey: Self.currentVisualMediaIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.currentVisualMediaIDKey)
        }
        logVisualMedia(
            "selection-set reason=\(reason) scope=\(visualMediaLibraryScope.rawValue) selected=\"\(id ?? "nil")\" customCount=\(userVisualMediaAssets.count) effectiveCount=\(effectiveVisualMediaAssets.count)"
        )
    }

    private func logVisualMedia(_ message: String) {
        logger.info("visualMedia.\(message, privacy: .public)")
        DiagnosticLog.appendPlayback("visualMedia.\(message)")
    }

    var sceneChoices: [SceneAsset] {
        SceneCatalog.presets
    }

    var currentPreset: LofiiPreset {
        presets[selectedIndex]
    }

    var currentYouTubeVideoID: String? {
        currentPreset.radio.source.youtubeVideoID
    }

    var currentBilibiliLiveRoomID: Int? {
        currentPreset.radio.source.bilibiliLiveRoomID
    }

    var currentTwitchChannelName: String? {
        currentPreset.radio.source.twitchChannelName
    }

    var currentDirectVideoURL: URL? {
        currentPreset.radio.source.directVideoURL
    }

    var isCurrentStationYouTube: Bool {
        currentPreset.radio.source.isYouTube
    }

    var isCurrentStationBilibiliLive: Bool {
        currentPreset.radio.source.isBilibiliLive
    }

    var isCurrentStationTwitch: Bool {
        currentPreset.radio.source.isTwitch
    }

    var isCurrentStationEmbeddedVideo: Bool {
        currentPreset.radio.source.isEmbeddedVideo
    }

    var isEmbeddedVideoBuffering: Bool {
        isYouTubeBuffering || isTwitchBuffering || isBilibiliLiveBuffering
    }

    var isReadoutWaveformActive: Bool {
        guard isPlaying else { return false }
        if isCurrentStationBilibiliLive {
            return !isBilibiliLiveUnavailable && !isBilibiliLiveBuffering
        }
        if isCurrentStationTwitch {
            return !isTwitchUnavailable && !isTwitchBuffering
        }
        if isCurrentStationYouTube {
            return !isYouTubeBuffering
        }
        return !isBuffering
    }

    var isCurrentStationDirectVideo: Bool {
        currentPreset.radio.source.directVideoURL != nil
    }

    private var liveModeUsesTrackArtworkBackground: Bool {
        visualMode == .live &&
            currentYouTubeVideoID == nil &&
            currentBilibiliLiveRoomID == nil &&
            currentTwitchChannelName == nil &&
            currentDirectVideoURL == nil
    }

    private var liveModeUsesEmbeddedVideoBackground: Bool {
        visualMode == .live &&
            isCurrentStationEmbeddedVideo
    }

    var isSceneVariantControlAvailable: Bool {
        visualMode == .scene
    }

    var currentScene: SceneAsset {
        if let currentSceneID,
           let scene = SceneCatalog.presets.first(where: { $0.id == currentSceneID }) {
            return scene
        }
        return SceneCatalog.presets.first ?? currentPreset.scene
    }

    var accent: Color {
        currentPreset.pickerAccent
    }

    private func refreshSystemMediaControls() {
        systemMediaControls.update(
            stationName: currentPreset.displayName,
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

    func handleYouTubePlayerError(_ code: Int) {
        guard currentPreset.radio.source.isYouTube else { return }
        streamStatus = "YouTube video unavailable"
        isBuffering = false
        isYouTubeBuffering = false
        DiagnosticLog.appendPlayback(
            "model.youtubeError preset=\(currentPreset.id) source=\(currentPreset.radio.source.stableID) code=\(code)"
        )
    }

    func handleYouTubePlaybackState(_ state: YouTubePlaybackState) {
        guard currentPreset.radio.source.isYouTube else { return }
        switch state {
        case .playing:
            isYouTubeBuffering = false
            isBuffering = false
            streamStatus = "Playing on YouTube"
            let sourceStableID = currentPreset.radio.source.stableID
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 550_000_000)
                guard visualMode == .live,
                      currentPreset.radio.source.stableID == sourceStableID
                else { return }
                markPrimaryVisualMediaReady()
            }
        case .buffering:
            isYouTubeBuffering = isPlaying
            streamStatus = isPlaying ? "YouTube buffering…" : "Paused"
        case .paused, .ended, .cued, .unstarted, .unknown:
            isYouTubeBuffering = false
            if !isPlaying {
                streamStatus = "Paused"
            }
        }
    }

    func handleTwitchPlaybackEvent(_ event: TwitchPlaybackEvent) {
        guard currentPreset.radio.source.isTwitch else { return }
        DiagnosticLog.appendPlayback(
            "model.twitchEvent preset=\(currentPreset.id) source=\(currentPreset.radio.source.stableID) event=\(event.rawValue)"
        )
        switch event {
        case .ready, .online:
            isTwitchUnavailable = false
            isTwitchBuffering = false
            markEmbeddedVideoVisualReady(after: 250_000_000)
            if !isPlaying {
                streamStatus = "Ready · Twitch"
            }
        case .play:
            isTwitchUnavailable = false
            isTwitchBuffering = isPlaying
            streamStatus = isPlaying ? "Twitch buffering…" : "Paused"
        case .playing:
            isTwitchUnavailable = false
            isTwitchBuffering = false
            isBuffering = false
            streamStatus = "Playing on Twitch"
            let sourceStableID = currentPreset.radio.source.stableID
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 550_000_000)
                guard visualMode == .live,
                      currentPreset.radio.source.stableID == sourceStableID
                else { return }
                markPrimaryVisualMediaReady()
            }
        case .pause, .ended:
            isTwitchBuffering = false
            if !isPlaying {
                streamStatus = "Paused"
            }
        case .offline:
            isTwitchBuffering = false
            isTwitchUnavailable = true
            markEmbeddedVideoVisualReady(after: 250_000_000)
            streamStatus = "Twitch channel offline"
        case .playbackBlocked:
            isTwitchBuffering = false
            isTwitchUnavailable = true
            markEmbeddedVideoVisualReady(after: 250_000_000)
            streamStatus = "Twitch playback blocked"
            DiagnosticLog.appendPlayback(
                "model.twitchPlaybackBlocked preset=\(currentPreset.id) source=\(currentPreset.radio.source.stableID)"
            )
        }
    }

    func handleBilibiliLivePlaybackEvent(_ event: BilibiliLivePlaybackEvent) {
        guard currentPreset.radio.source.isBilibiliLive else { return }
        DiagnosticLog.appendPlayback(
            "model.bilibiliLiveEvent preset=\(currentPreset.id) source=\(currentPreset.radio.source.stableID) event=\(event.logValue)"
        )
        switch event {
        case .ready:
            markEmbeddedVideoVisualReady(after: 250_000_000)
        case .live:
            isBilibiliLiveUnavailable = false
            isBilibiliLiveBuffering = isPlaying
            markEmbeddedVideoVisualReady(after: 250_000_000)
            streamStatus = isPlaying ? "Bilibili live buffering…" : "Ready · Bilibili"
        case .playing, .mutedAutoplay:
            isBilibiliLiveUnavailable = false
            isBilibiliLiveBuffering = false
            isBuffering = false
            markEmbeddedVideoVisualReady(after: 250_000_000)
            streamStatus = "Playing on Bilibili"
        case .notAutoplay:
            isBilibiliLiveUnavailable = false
            isBilibiliLiveBuffering = false
            markEmbeddedVideoVisualReady(after: 250_000_000)
            streamStatus = "Bilibili playback blocked"
        case .paused:
            isBilibiliLiveBuffering = false
            if !isPlaying {
                streamStatus = "Paused"
            }
        case .offline:
            isBilibiliLiveUnavailable = true
            isBilibiliLiveBuffering = false
            markEmbeddedVideoVisualReady(after: 250_000_000)
            streamStatus = "Bilibili live offline"
        case .replay:
            isBilibiliLiveUnavailable = false
            isBilibiliLiveBuffering = false
            markEmbeddedVideoVisualReady(after: 250_000_000)
            streamStatus = "Bilibili replay"
        }
    }

    private func markEmbeddedVideoVisualReady(after delay: UInt64) {
        let sourceStableID = currentPreset.radio.source.stableID
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard visualMode == .live,
                  currentPreset.radio.source.stableID == sourceStableID
            else { return }
            markPrimaryVisualMediaReady()
        }
    }

    func selectPreset(at index: Int) {
        guard presets.indices.contains(index) else { return }
        selectedIndex = index
    }

    func builtInOverride(forPresetID presetID: String) -> BuiltInStationOverride? {
        builtInStationOverrides.first { $0.presetID == presetID }
    }

    func addCustomStation(
        name: String,
        url: String,
        iconID: String = PixelGlyph.headphone.stableID,
        themeColorHex: String = StationThemeColor.pink.hex
    ) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw CustomStationValidationError.missingName
        }
        guard let source = await CustomStationSourceResolver.resolveWithProbe(trimmedURL) else {
            throw CustomStationValidationError.invalidStationURL
        }
        guard !stationConfigurationsContainSource(source) else {
            throw CustomStationValidationError.duplicateStation
        }

        var station = CustomStation(
            kind: source.kind,
            name: trimmedName,
            url: trimmedURL,
            videoID: source.videoID,
            iconID: iconID,
            themeColorHex: themeColorHex
        )
        station.updatedAt = station.createdAt
        customStations.append(station)
        try persistStationConfiguration(selectingCustomID: station.id)
    }

    func updateCustomStation(
        id: UUID,
        name: String,
        url: String,
        iconID: String,
        themeColorHex: String
    ) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw CustomStationValidationError.missingName
        }
        guard let source = await CustomStationSourceResolver.resolveWithProbe(trimmedURL) else {
            throw CustomStationValidationError.invalidStationURL
        }
        guard !stationConfigurationsContainSource(source, ignoringCustomID: id) else {
            throw CustomStationValidationError.duplicateStation
        }
        guard let index = customStations.firstIndex(where: { $0.id == id }) else { return }
        let wasCurrent = currentPreset.customStationID == id
        let previousSourceIdentity = CustomStationSourceResolver.resolve(station: customStations[index])?.identity

        customStations[index].kind = source.kind
        customStations[index].name = trimmedName
        customStations[index].url = trimmedURL
        customStations[index].videoID = source.videoID
        customStations[index].iconID = iconID
        customStations[index].themeColorHex = StationThemeColor.validatedHex(themeColorHex)
        customStations[index].updatedAt = Date()
        try persistStationConfiguration(
            selectingCustomID: id,
            reactivateIfTargetAlreadySelected: wasCurrent && previousSourceIdentity != source.identity
        )
    }

    func updateBuiltInStation(
        presetID: String,
        name: String,
        url: String,
        iconID: String,
        themeColorHex: String
    ) async throws {
        guard LofiiPreset.presets.contains(where: { $0.id == presetID }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw CustomStationValidationError.missingName
        }
        guard let source = await CustomStationSourceResolver.resolveWithProbe(trimmedURL) else {
            throw CustomStationValidationError.invalidStationURL
        }
        guard !stationConfigurationsContainSource(source, ignoringBuiltInPresetID: presetID) else {
            throw CustomStationValidationError.duplicateStation
        }
        let wasCurrent = currentPreset.id == presetID
        let previousSourceIdentity = wasCurrent ? Self.sourceIdentity(for: currentPreset.radio.source) : nil

        let override = BuiltInStationOverride(
            presetID: presetID,
            kind: source.kind,
            name: trimmedName,
            url: trimmedURL,
            videoID: source.videoID,
            iconID: iconID,
            themeColorHex: themeColorHex
        )

        if let index = builtInStationOverrides.firstIndex(where: { $0.presetID == presetID }) {
            builtInStationOverrides[index] = override
        } else {
            builtInStationOverrides.append(override)
        }
        try persistStationConfiguration(
            selectingPresetID: presetID,
            reactivateIfTargetAlreadySelected: wasCurrent && previousSourceIdentity != source.identity
        )
    }

    func resetBuiltInStation(presetID: String) {
        builtInStationOverrides.removeAll { $0.presetID == presetID }
        do {
            try persistStationConfiguration(
                selectingPresetID: presetID,
                reactivateIfTargetAlreadySelected: currentPreset.id == presetID
            )
        } catch {
            DiagnosticLog.appendPlayback(
                "customStations.resetBuiltInSaveFailed presetID=\(presetID) error=\"\(error.localizedDescription)\""
            )
        }
    }

    func deleteCustomStation(id: UUID) {
        let selectedID = currentPreset.customStationID
        customStations.removeAll { $0.id == id }
        do {
            try persistStationConfiguration(
                selectingCustomID: selectedID == id ? nil : selectedID,
                reactivateIfTargetAlreadySelected: selectedID == id
            )
        } catch {
            DiagnosticLog.appendPlayback(
                "customStations.deleteSaveFailed id=\(id.uuidString) error=\"\(error.localizedDescription)\""
            )
        }
    }

    private func stationConfigurationsContainSource(
        _ source: CustomStationSource,
        ignoringCustomID: UUID? = nil,
        ignoringBuiltInPresetID: String? = nil
    ) -> Bool {
        customStations.contains { station in
            station.id != ignoringCustomID &&
                CustomStationSourceResolver.resolve(station: station)?.identity == source.identity
        } || builtInStationOverrides.contains { station in
            station.presetID != ignoringBuiltInPresetID &&
                CustomStationSourceResolver.resolve(override: station)?.identity == source.identity
        }
    }

    private func persistStationConfiguration(
        selectingCustomID customStationID: UUID? = nil,
        selectingPresetID presetID: String? = nil,
        reactivateIfTargetAlreadySelected: Bool = false
    ) throws {
        let previousPresetID = currentPreset.id
        try customStationStore.save(
            CustomStationDocument(
                stations: customStations,
                builtInOverrides: builtInStationOverrides
            )
        )
        presets = Self.combinedPresets(
            customStations: customStations,
            builtInOverrides: builtInStationOverrides
        )

        let targetIndex: Int
        if let presetID,
           let index = presets.firstIndex(where: { $0.id == presetID }) {
            targetIndex = index
        } else if let customStationID,
           let index = presets.firstIndex(where: { $0.customStationID == customStationID }) {
            targetIndex = index
        } else if let index = presets.firstIndex(where: { $0.id == previousPresetID }) {
            targetIndex = index
        } else {
            targetIndex = min(selectedIndex, max(presets.count - 1, 0))
        }

        if selectedIndex == targetIndex {
            let targetPresetReplacedCurrent = currentPreset.id != previousPresetID
            guard reactivateIfTargetAlreadySelected || targetPresetReplacedCurrent else {
                UserDefaults.standard.set(currentPreset.id, forKey: Self.selectedPresetIDKey)
                refreshSystemMediaControls()
                return
            }
            activateSelectedPreset()
        } else {
            selectedIndex = targetIndex
        }
    }

    func previousStation() {
        selectedIndex = (selectedIndex + presets.count - 1) % presets.count
    }

    func nextStation() {
        selectedIndex = (selectedIndex + 1) % presets.count
    }

    func cycleVariant() {
        guard isSceneVariantControlAvailable else { return }
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
            visualMode = all.first ?? .scene
            return
        }
        visualMode = all[(idx + 1) % all.count]
    }

    func selectScene(_ scene: SceneAsset) {
        currentSceneID = scene.id
        if visualMode != .scene {
            visualMode = .scene
        }
    }

    func nextScene() {
        guard !sceneChoices.isEmpty else { return }
        let currentIndex = sceneChoices.firstIndex(where: { $0.id == currentScene.id }) ?? 0
        selectScene(sceneChoices[(currentIndex + 1) % sceneChoices.count])
    }

    func toggleBongoOverlay() {
        bongoOverlayVisible.toggle()
    }

    func toggleBongoStageDragLock() {
        bongoStageDragLocked.toggle()
    }

    var isBongoDesktopMaskEnabled: Bool {
        bongoDesktopMaskTint != .hidden
    }

    func toggleBongoDesktopMask() {
        bongoDesktopMaskTint = isBongoDesktopMaskEnabled ? .hidden : .dynamic
    }

    func nextVisualMedia() {
        let assets = effectiveVisualMediaAssets
        guard !assets.isEmpty else { return }
        let currentIndex = currentVisualMedia.flatMap { current in
            assets.firstIndex(of: current)
        } ?? currentVisualMediaIndex
        let nextIndex = (currentIndex + 1) % assets.count
        currentVisualMediaIndex = nextIndex
        currentVisualMediaID = assets[nextIndex].id
        if visualMode != .media {
            visualMode = .media
        }
    }

    func setWidgetWindowVisible(_ visible: Bool) {
        isWidgetVisible = visible
    }

    private func syncPlayback() {
        DiagnosticLog.appendPlayback(
            "model.syncPlayback isPlaying=\(isPlaying) preset=\(currentPreset.id) source=\(currentPreset.radio.source.stableID) currentTrack=\"\(currentTrack?.title ?? "nil")\""
        )
        if currentPreset.radio.source.isEmbeddedVideo {
            cancelPlaybackRecovery()
            resetChillhopPlaybackState()
            let stopReason =
                currentPreset.radio.source.isYouTube ? "youtube-station-active" :
                (currentPreset.radio.source.isTwitch ? "twitch-station-active" : "bilibili-live-station-active")
            audioEngine.stop(reason: stopReason)
            refreshLiveTrackLoop()
            refreshPlaybackWatchdog()
            if currentTrack == nil {
                Task {
                    await loadLiveTrack(replacingCurrentItem: true)
                }
            }
            isBuffering = false
            if !isPlaying {
                isYouTubeBuffering = false
                isTwitchBuffering = false
                isBilibiliLiveBuffering = false
            }
            if currentPreset.radio.source.isYouTube {
                streamStatus = isPlaying
                    ? (isYouTubeBuffering ? "YouTube buffering…" : "Playing on YouTube")
                    : "Paused"
            } else if currentPreset.radio.source.isTwitch {
                streamStatus = isPlaying
                    ? (isTwitchBuffering ? "Twitch buffering…" : "Playing on Twitch")
                    : "Paused"
            } else {
                streamStatus = isPlaying
                    ? (isBilibiliLiveBuffering ? "Bilibili live buffering…" : "Playing on Bilibili")
                    : "Paused"
            }
            return
        }

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
        guard isPlaying, !currentPreset.radio.source.isEmbeddedVideo else { return }
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

        guard isPlaying, !currentPreset.radio.source.isEmbeddedVideo else { return }
        playbackWatchdogTimer = Timer.scheduledTimer(withTimeInterval: Self.playbackWatchdogInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluatePlaybackWatchdog()
            }
        }
    }

    private func evaluatePlaybackWatchdog() {
        guard !currentPreset.radio.source.isEmbeddedVideo else {
            lastPlaybackWatchdogSample = nil
            stalledPlaybackWatchdogTicks = 0
            isBuffering = false
            return
        }
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

        let stallReason: String
        if sample.isWaiting {
            stallReason = "waiting"
        } else if sample.isBufferEmpty {
            stallReason = "buffer-empty"
        } else if !sample.isPlaying {
            stallReason = "not-playing"
        } else if let previous = lastPlaybackWatchdogSample,
                  previous.itemID == sample.itemID,
                  let previousTime = previous.currentTime,
                  let currentTime = sample.currentTime,
                  currentTime - previousTime <= 0.2 {
            stallReason = "no-progress"
        } else {
            stalledPlaybackWatchdogTicks = 0
            return
        }

        stalledPlaybackWatchdogTicks += 1
        guard stalledPlaybackWatchdogTicks >= Self.playbackStallTickThreshold else { return }

        let stallSeconds = Self.playbackWatchdogInterval * TimeInterval(Self.playbackStallTickThreshold)
        logger.info(
            "Playback watchdog detected stall reason=\(stallReason, privacy: .public) seconds=\(stallSeconds, format: .fixed(precision: 1)) title=\(currentTrack.title, privacy: .public) rate=\(sample.rate, format: .fixed(precision: 2)) status=\(sample.timeControlStatus, privacy: .public) likely=\(sample.isLikelyToKeepUp)"
        )
        DiagnosticLog.appendPlayback(
            "model.watchdogStall thresholdSeconds=\(Self.formatSeconds(stallSeconds)) reason=\(stallReason) \(playbackDiagnosticContext(sample: sample))"
        )
        stalledPlaybackWatchdogTicks = 0
        isBuffering = true
        schedulePlaybackRecovery(stallReason == "no-progress" ? .softResume : .hardReload)
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
                    DiagnosticLog.appendPlayback(
                        "model.loadTrack provider=chillhop stationID=\(stationID) replacing=\(replacingCurrentItem) index=\(playlistIndex) queueCount=\(max(playlist.count - playlistIndex - 1, 0)) title=\"\(liveTrack.title)\" elapsed=\(Self.formatSeconds(liveTrack.elapsedPlaybackSeconds())) url=\(liveTrack.streamURL.absoluteString)"
                    )
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
                    DiagnosticLog.appendPlayback(
                        "model.refillQueue provider=chillhop stationID=\(stationID) playlistCount=\(playlist.count) currentTrack=\"\(currentTrack?.title ?? "nil")\""
                    )
                    refillChillhopQueue(with: playlist)
                }
            } catch {
                DiagnosticLog.appendPlayback(
                    "model.loadTrackFailed provider=chillhop stationID=\(stationID) replacing=\(replacingCurrentItem) error=\"\(error.localizedDescription)\""
                )
                resetChillhopPlaybackState()
                currentTrack = nil
                streamStatus = "Stream unavailable"
            }
        case let .directStream(trackID, url):
            await loadDirectMediaTrack(
                provider: "direct",
                trackID: trackID,
                url: url,
                replacingCurrentItem: replacingCurrentItem
            )
        case let .directVideo(trackID, url):
            await loadDirectMediaTrack(
                provider: "directVideo",
                trackID: trackID,
                url: url,
                replacingCurrentItem: replacingCurrentItem
            )
        case let .radioCo(trackID, stationID):
            resetChillhopPlaybackState(clearPreparedTrack: false)
            do {
                let snapshot = try await radioCoService.fetchSnapshot(
                    stationID: stationID,
                    trackID: trackID,
                    fallbackTitle: currentPreset.displayName,
                    fallbackArtists: currentPreset.radio.badgeSubtitle
                )
                let streamTrack = snapshot.track
                let trackChanged =
                    currentTrack?.id != streamTrack.id ||
                    currentTrack?.streamURL != streamTrack.streamURL

                DiagnosticLog.appendPlayback(
                    "model.loadTrack provider=radioco stationID=\(stationID) replacing=\(replacingCurrentItem) trackChanged=\(trackChanged) title=\"\(streamTrack.title)\" url=\(streamTrack.streamURL.absoluteString)"
                )
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
                DiagnosticLog.appendPlayback(
                    "model.loadTrackFailed provider=radioco stationID=\(stationID) replacing=\(replacingCurrentItem) error=\"\(error.localizedDescription)\""
                )
                if replacingCurrentItem || currentTrack == nil {
                    currentTrack = nil
                    streamStatus = "Stream unavailable"
                }
            }
        case let .bilibiliLive(roomID):
            resetChillhopPlaybackState(clearPreparedTrack: false)
            audioEngine.stop(reason: "bilibili-live-station-loaded")
            isBuffering = false
            isBilibiliLiveBuffering = isPlaying
            isBilibiliLiveUnavailable = false
            let sourceStableID = currentPreset.radio.source.stableID
            let streamURL = URL(string: "https://live.bilibili.com/\(roomID)")!
            let trackID = Self.stableNegativeID(forEmbeddedVideoID: "bilibili-live:\(roomID)")
            let streamTrack = LiveTrack.directStream(
                id: trackID,
                title: currentPreset.displayName,
                artists: currentPreset.radio.providerName,
                streamURL: streamURL
            )
            currentTrack = streamTrack
            streamStatus = isPlaying ? "Playing on Bilibili" : "Ready · Bilibili"
            DiagnosticLog.appendPlayback(
                "model.loadTrack provider=bilibiliLive roomID=\(roomID) replacing=\(replacingCurrentItem) title=\"\(streamTrack.title)\""
            )
            markEmbeddedVideoVisualReady(after: 4_000_000_000)
            if let metadata = await StationMetadataService.fetchBilibiliLive(roomID: roomID),
               currentPreset.radio.source.stableID == sourceStableID {
                currentTrack = metadata.liveTrack(id: trackID, streamURL: streamURL)
                DiagnosticLog.appendPlayback(
                    "model.loadTrackMetadata provider=bilibiliLive roomID=\(roomID) title=\"\(metadata.title)\" image=\"\(metadata.image?.absoluteString ?? "nil")\""
                )
            }
        case let .youtube(videoID):
            resetChillhopPlaybackState(clearPreparedTrack: false)
            audioEngine.stop(reason: "youtube-station-loaded")
            isBuffering = false
            let streamURL = URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
            let streamTrack = LiveTrack.directStream(
                id: Self.stableNegativeID(forYouTubeVideoID: videoID),
                title: currentPreset.displayName,
                artists: currentPreset.radio.providerName,
                streamURL: streamURL
            )
            currentTrack = streamTrack
            streamStatus = isPlaying ? "Playing on YouTube" : "Ready · YouTube"
            DiagnosticLog.appendPlayback(
                "model.loadTrack provider=youtube videoID=\(videoID) replacing=\(replacingCurrentItem) title=\"\(streamTrack.title)\""
            )
            if let metadata = await StationMetadataService.fetchYouTube(videoID: videoID),
               currentPreset.radio.source.youtubeVideoID == videoID {
                currentTrack = metadata.liveTrack(
                    id: Self.stableNegativeID(forYouTubeVideoID: videoID),
                    streamURL: streamURL
                )
                DiagnosticLog.appendPlayback(
                    "model.loadTrackMetadata provider=youtube videoID=\(videoID) title=\"\(metadata.title)\" artists=\"\(metadata.artists)\""
                )
            }
        case let .twitch(channelName):
            resetChillhopPlaybackState(clearPreparedTrack: false)
            audioEngine.stop(reason: "twitch-station-loaded")
            isBuffering = false
            isTwitchBuffering = isPlaying
            isTwitchUnavailable = false
            let streamURL = URL(string: "https://www.twitch.tv/\(channelName)")!
            let streamTrack = LiveTrack.directStream(
                id: Self.stableNegativeID(forEmbeddedVideoID: "twitch:\(channelName)"),
                title: currentPreset.displayName,
                artists: currentPreset.radio.providerName,
                streamURL: streamURL,
                image: currentPreset.radio.source.twitchPreviewImageURL
            )
            currentTrack = streamTrack
            streamStatus = isPlaying ? "Playing on Twitch" : "Ready · Twitch"
            DiagnosticLog.appendPlayback(
                "model.loadTrack provider=twitch channelName=\(channelName) replacing=\(replacingCurrentItem) title=\"\(streamTrack.title)\" image=\"\(streamTrack.image?.absoluteString ?? "nil")\""
            )
            markEmbeddedVideoVisualReady(after: 4_000_000_000)
        }
    }

    private func loadDirectMediaTrack(
        provider: String,
        trackID: Int,
        url: URL,
        replacingCurrentItem: Bool
    ) async {
        resetChillhopPlaybackState(clearPreparedTrack: false)
        let sourceStableID = currentPreset.radio.source.stableID
        let reusableDirectMetadata: LiveTrack? = {
            guard let currentTrack,
                  currentTrack.id == trackID,
                  currentTrack.streamURL == url,
                  currentTrack.hasRealMetadata
            else { return nil }
            return currentTrack
        }()
        let fallbackTrack = LiveTrack.directStream(
            id: trackID,
            title: reusableDirectMetadata?.title ?? currentPreset.displayName,
            artists: reusableDirectMetadata?.artists ?? currentPreset.radio.badgeSubtitle,
            streamURL: url,
            image: reusableDirectMetadata?.image,
            metadataKind: reusableDirectMetadata?.metadataKind ?? .fallback
        )
        let trackChanged = currentTrack?.id != fallbackTrack.id || currentTrack?.streamURL != fallbackTrack.streamURL
        if trackChanged {
            DiagnosticLog.appendPlayback(
                "model.loadTrack provider=\(provider) replacing=\(replacingCurrentItem) trackChanged=true title=\"\(fallbackTrack.title)\" url=\(fallbackTrack.streamURL.absoluteString)"
            )
        }
        currentTrack = fallbackTrack

        if isPlaying {
            playCurrentTrack(replacingCurrentItem: replacingCurrentItem || trackChanged)
        } else {
            streamStatus = "Ready · \(currentPreset.displayName)"
        }

        guard let metadata = await StationMetadataService.fetchICY(url: url),
              currentPreset.radio.source.stableID == sourceStableID
        else { return }

        let enhancedTrack = metadata.liveTrack(id: trackID, streamURL: url)
        currentTrack = enhancedTrack
        streamStatus = isPlaying
            ? "Live stream · \(enhancedTrack.title)"
            : "Ready · \(enhancedTrack.title)"
        DiagnosticLog.appendPlayback(
            "model.loadTrackMetadata provider=\(provider) title=\"\(enhancedTrack.title)\" artists=\"\(enhancedTrack.artists)\" image=\"\(enhancedTrack.image?.absoluteString ?? "nil")\""
        )
    }

    private func playCurrentTrack(replacingCurrentItem: Bool) {
        guard !currentPreset.radio.source.isEmbeddedVideo else {
            if currentPreset.radio.source.isYouTube {
                streamStatus = isPlaying ? "Playing on YouTube" : "Ready · YouTube"
            } else if currentPreset.radio.source.isTwitch {
                streamStatus = isPlaying ? "Playing on Twitch" : "Ready · Twitch"
            } else {
                streamStatus = isPlaying ? "Playing on Bilibili" : "Ready · Bilibili"
            }
            return
        }
        guard let currentTrack else {
            streamStatus = "Loading track…"
            return
        }

        let shouldBootstrapChillhopPosition = currentPreset.radio.source.isChillhop && replacingCurrentItem
        let elapsed = shouldBootstrapChillhopPosition ? currentTrack.elapsedPlaybackSeconds() : 0
        let reason = playbackStartReason(for: currentTrack, replacingCurrentItem: replacingCurrentItem)
        DiagnosticLog.appendPlayback(
            "model.playCurrent reason=\(reason) replacing=\(replacingCurrentItem) preset=\(currentPreset.id) source=\(currentPreset.radio.source.stableID) title=\"\(currentTrack.title)\" elapsed=\(Self.formatSeconds(elapsed)) synchronized=\(currentTrack.isSynchronizedLiveStream)"
        )
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

        DiagnosticLog.appendPlayback(
            "model.scheduleChillhopTransition title=\"\(track.title)\" elapsed=\(Self.formatSeconds(elapsed)) remaining=\(Self.formatSeconds(remaining)) queueCount=\(chillhopQueue.count)"
        )
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
        DiagnosticLog.appendPlayback(
            "model.beginChillhopTransition didCrossfade=\(didCrossfade) nextTitle=\"\(nextTrack.title)\" remainingQueue=\(chillhopQueue.count)"
        )

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
        guard !currentPreset.radio.source.isEmbeddedVideo else {
            cancelPlaybackRecovery()
            return
        }
        guard isPlaying, currentTrack != nil else {
            cancelPlaybackRecovery()
            return
        }
        guard pendingPlaybackRecovery != step else {
            DiagnosticLog.appendPlayback(
                "model.recoveryAlreadyPending step=\(step) \(playbackDiagnosticContext(sample: audioEngine.playbackSample()))"
            )
            return
        }

        playbackRecoveryTask?.cancel()
        pendingPlaybackRecovery = step
        DiagnosticLog.appendPlayback(
            "model.scheduleRecovery step=\(step) delay=\(Self.formatSeconds(step.delay)) \(playbackDiagnosticContext(sample: audioEngine.playbackSample()))"
        )
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
        DiagnosticLog.appendPlayback(
            "model.performRecovery step=\(step) \(playbackDiagnosticContext(sample: audioEngine.playbackSample()))"
        )

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

    private func playbackDiagnosticContext(sample: StreamingAudioEngine.PlaybackSample) -> String {
        [
            "preset=\(currentPreset.id)",
            "source=\(currentPreset.radio.source.stableID)",
            "track=\"\(currentTrack?.title ?? "nil")\"",
            "artists=\"\(currentTrack?.artists ?? "nil")\"",
            "synchronized=\(currentTrack?.isSynchronizedLiveStream ?? false)",
            "streamStatus=\"\(streamStatus)\"",
            "isPlayingIntent=\(isPlaying)",
            "isBuffering=\(isBuffering)",
            "volume=\(volume)",
            "item=\(sample.hasItem)",
            "itemStatus=\(sample.itemStatus)",
            "timeControl=\(sample.timeControlStatus)",
            "rate=\(Self.formatSeconds(Double(sample.rate)))",
            "time=\(sample.currentTime.map(Self.formatSeconds) ?? "nil")",
            "waiting=\(sample.isWaiting)",
            "playing=\(sample.isPlaying)",
            "bufferEmpty=\(sample.isBufferEmpty)",
            "bufferFull=\(sample.isBufferFull)",
            "likely=\(sample.isLikelyToKeepUp)",
            "itemFailed=\(sample.itemFailed)",
            "itemError=\"\(sample.errorDescription ?? "nil")\"",
            "playerError=\"\(sample.playerErrorDescription ?? "nil")\"",
            "loaded=\(sample.loadedTimeRanges)",
            "url=\(sample.currentURL ?? "nil")"
        ].joined(separator: " ")
    }

    private static func formatSeconds(_ value: TimeInterval) -> String {
        guard value.isFinite else { return "nan" }
        return String(format: "%.2f", value)
    }

    private static func stableNegativeID(forYouTubeVideoID videoID: String) -> Int {
        stableNegativeID(forEmbeddedVideoID: "youtube:\(videoID)")
    }

    private static func stableNegativeID(forEmbeddedVideoID value: String) -> Int {
        let hash = value.unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 31) &+ Int(scalar.value)
        }
        return -100_000 - abs(hash % 800_000)
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
