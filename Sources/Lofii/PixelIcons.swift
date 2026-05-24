import SwiftUI
import AppKit
import CoreText

/// Bundles + registers `pixelart-icons-font` (MIT, by Gerrit Halfmann —
/// https://github.com/halfmage/pixelarticons) and exposes a small enum of
/// the icons we actually use, so call sites can write
/// `PixelIcon(.play)` without hard-coding PUA codepoints.
///
/// We picked an icon font (instead of SF Symbols or vector SVGs) because
/// the rest of the readout uses the Doto grid face — SF Symbols are
/// vector-smooth and look out of place next to it. Pixelarticons is drawn
/// on a strict 24×24 grid with no anti-aliasing, so it matches Doto's
/// "every dot deliberate" aesthetic exactly.
enum PixelIcons {
    /// Family name of the font as embedded in the .ttf — verified via
    /// `CTFontCopyFamilyName`.
    static let familyName = "pixelart-icons-font"

    @MainActor private static var registered = false

    @MainActor
    static func registerIfNeeded() {
        guard !registered else { return }
        registered = true

        guard let url = LofiiResources.bundle.url(
            forResource: "PixelartIcons",
            withExtension: "ttf",
            subdirectory: "Fonts"
        ) else {
            assertionFailure("PixelartIcons.ttf missing from bundle")
            return
        }

        var error: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if !ok, let err = error?.takeRetainedValue() {
            let code = CFErrorGetCode(err)
            // 105 = kCTFontManagerErrorAlreadyRegistered. Ignore.
            if code != 105 {
                assertionFailure("Failed to register PixelartIcons: \(err)")
            }
        }
    }
}

/// Symbolic names for every pixelart icon we currently render. The raw
/// value is the Private Use Area codepoint from `pixelart-icons-font.css`
/// (e.g. `.play` = `U+EC32`). Keep this list small — adding new icons is
/// cheap, but having a curated set makes it obvious where each glyph is
/// used and lets us swap families in one place if we ever change fonts.
enum PixelGlyph {
    // Window chrome
    case close
    case expand      // used as "enter fullscreen"
    case scale       // used as "exit fullscreen"
    case pin         // anchor-sharp fallback for the old pin semantic
    case anchor
    case grid        // grid-3x3-sharp
    case radio
    case radioSignal // radio fallback for the old radio-signal semantic
    case sliders     // settings-2-sharp

    // View mode
    case airplaySharp
    case buildingCommunitySharp
    case imageSharp
    case movie       // clapperboard-sharp
    case gif         // image-sharp
    case imageFrame  // frame
    case shuffle     // shuffle-sharp

    // Variant (day/night/rain)
    case sun         // cloud-sun fallback; v2 has no plain sun
    case moon
    case cloudSun
    case cloudMoon

    // Transport
    case prev        // chevron-left
    case next        // chevron-right
    case play
    case pause       // rendered by PixelPauseIconShape

    // Volume — pixelarticons ships a 5-step ladder of speaker glyphs
    // (mute → 1 wave → 2 waves → 3 waves → "full"). We use the ladder
    // in `VolumeOverlay` so the speaker icon visually grows louder
    // along with the slider, the same way macOS / iOS speaker glyphs do.
    case speaker     // volume
    case volumeMute  // volume-1 fallback; v2 has no volume-x
    case volume1     // volume-1 (one wave)
    case volume2     // volume-2 (two waves)
    case volume3     // volume-3 (three waves)
    case volumeFull  // volume   (max)

    // Status
    case signalOff   // cellular-signal-0 — used for stream errors

    // Scene catalog (shown in StationPicker rows). Pixelarticons (the free
    // 800-glyph set) doesn't carry every SF Symbol the original
    // SceneCatalog reached for, so the matches below are evocative rather
    // than literal — the goal is "this row is the cozy/woodsy one"
    // not perfect iconographic equivalence.
    case musicNote   // music-sharp
    case cocktail    // bottle-wine-sharp / tropical
    case buildings   // building-community-sharp
    case coffee      // coffee-sharp / cozy warmth
    case lightbulb   // cozy studio
    case home        // home-sharp / tree house / cabin
    case camera      // camera-sharp / in the woods / macro shot
    case wind        // sea side / breeze
    case headphone   // custom station identity, kept out of chrome controls
    case album
    case bookmark
    case heart
    case leaf
    case fire
    case treePine
    case star
    case sparkles
    case sofa
    case smartHome

    // Bongo mode
    case gamepad

    var symbol: String {
        switch self {
        case .close: return "\u{eb23}"
        case .expand: return "\u{eb64}"
        case .scale: return "\u{ec5e}"
        case .pin, .anchor: return "\u{ea48}"
        case .grid: return "\u{eba3}"
        case .radio, .radioSignal: return "\u{ec43}"
        case .sliders: return "\u{ec70}"
        case .airplaySharp: return "\u{ea11}"
        case .buildingCommunitySharp: return "\u{ead1}"
        case .imageSharp: return "\u{ebc0}"
        case .movie: return "\u{eb1c}"
        case .gif: return "\u{ebc0}"
        case .imageFrame: return "\u{eb85}"
        case .shuffle: return "\u{ec7f}"
        case .sun, .cloudSun: return "\u{eb26}"
        case .moon: return "\u{ec0c}"
        case .cloudMoon: return "\u{eb24}"
        case .prev: return "\u{eb0b}"
        case .next: return "\u{eb0d}"
        case .play: return "\u{ec32}"
        case .pause: return "\u{ec05}"
        case .speaker, .volumeFull: return "\u{ed1c}"
        case .volumeMute, .volume1: return "\u{ed19}"
        case .volume2: return "\u{ed1a}"
        case .volume3: return "\u{ed1b}"
        case .signalOff: return "\u{eaf2}"
        case .musicNote: return "\u{ec12}"
        case .cocktail: return "\u{eab8}"
        case .buildings: return "\u{ead1}"
        case .coffee: return "\u{eb28}"
        case .lightbulb: return "\u{ebd8}"
        case .home: return "\u{ebb3}"
        case .camera: return "\u{eae7}"
        case .wind: return "\u{ed27}"
        case .headphone: return "\u{ebb0}"
        case .album: return "\u{ea14}"
        case .bookmark: return "\u{eab6}"
        case .heart: return "\u{ebb1}"
        case .leaf: return "\u{ebd5}"
        case .fire: return "\u{eb73}"
        case .treePine: return "\u{ecf8}"
        case .star: return "\u{ecb2}"
        case .sparkles: return "\u{ec93}"
        case .sofa: return "\u{ec8e}"
        case .smartHome: return "\u{ec88}"
        case .gamepad: return "\u{eb89}"
        }
    }

    fileprivate var isCustomPause: Bool {
        switch self {
        case .pause: return true
        default: return false
        }
    }
}

private struct PixelPauseIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let dx = rect.midX - 12 * scale
        let dy = rect.midY - 12 * scale
        var path = Path()
        for source in [
            CGRect(x: 7, y: 5, width: 4, height: 14),
            CGRect(x: 13, y: 5, width: 4, height: 14),
        ] {
            path.addRect(CGRect(
                x: dx + source.minX * scale,
                y: dy + source.minY * scale,
                width: source.width * scale,
                height: source.height * scale
            ))
        }
        return path
    }
}

/// SwiftUI view that renders a single `PixelGlyph` at the given pixel size.
/// Behaves like `Image(systemName:)`: ignores the parent font, takes its
/// color from `.foregroundStyle(...)`, and is sized via the `size`
/// parameter.
///
/// Pixelarticons is a bitmap-style icon font drawn on a 24px grid. To stay
/// crisp we render at multiples of the design size and disable text
/// smoothing — antialiased pixel icons look blurry. We use SwiftUI's
/// `.fontWeight(.regular)` (the font has no other weights) and let it
/// inherit the foreground color.
struct PixelIcon: View {
    let glyph: PixelGlyph
    let size: CGFloat

    init(_ glyph: PixelGlyph, size: CGFloat = 14) {
        self.glyph = glyph
        self.size = size
    }

    var body: some View {
        if glyph.isCustomPause {
            PixelPauseIconShape()
                .fill(.foreground)
                .frame(width: size, height: size)
        } else {
            Text(glyph.symbol)
                .font(.custom(PixelIcons.familyName, size: size))
                // Force the layout to size to the visible glyph rather than
                // the font metrics, so a row of icons aligns vertically by
                // their visual centers regardless of the cap-height of each
                // glyph (some pixelart icons sit higher in the box than
                // others).
                .frame(width: size, height: size)
        }
    }
}
