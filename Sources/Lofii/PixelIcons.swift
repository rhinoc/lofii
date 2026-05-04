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
/// (e.g. `.play` = `U+EB7B`). Keep this list small — adding new icons is
/// cheap, but having a curated set makes it obvious where each glyph is
/// used and lets us swap families in one place if we ever change fonts.
enum PixelGlyph: String {
    // Window chrome
    case close       = "\u{ea8e}"
    case expand      = "\u{ead4}" // used as "enter fullscreen"
    case scale       = "\u{eb90}" // used as "exit fullscreen"
    case pin         = "\u{eb79}"
    case grid        = "\u{eafe}"
    case radioSignal = "\u{eb83}"
    case sliders     = "\u{eba4}"

    // Visual mode
    case movie       = "\u{eb65}"
    case gif         = "\u{eaf5}"
    case shuffle     = "\u{eba2}"

    // Variant (day/night/rain)
    case sun         = "\u{ebb2}"
    case moon        = "\u{eb60}"
    case cloudSun    = "\u{ea92}"
    case cloudMoon   = "\u{ea91}"

    // Transport
    case prev        = "\u{eb7f}"
    case next        = "\u{eb67}"
    case play        = "\u{eb7b}"
    case pause       = "\u{eb75}"

    // Volume — pixelarticons ships a 5-step ladder of speaker glyphs
    // (mute → 1 wave → 2 waves → 3 waves → "full"). We use the ladder
    // in `VolumeOverlay` so the speaker icon visually grows louder
    // along with the slider, the same way macOS / iOS speaker glyphs do.
    case speaker     = "\u{eba8}"
    case volumeMute  = "\u{ebdf}" // volume-x
    case volume1     = "\u{ebd9}" // volume-1 (one wave)
    case volume2     = "\u{ebda}" // volume-2 (two waves)
    case volume3     = "\u{ebdb}" // volume-3 (three waves)
    case volumeFull  = "\u{ebe0}" // volume   (max)

    // Status
    case signalOff   = "\u{ea76}" // cellular-signal-off — used for stream errors

    // Scene catalog (shown in StationPicker rows). Pixelarticons (the free
    // 800-glyph set) doesn't carry every SF Symbol the original
    // SceneCatalog reached for, so the matches below are evocative rather
    // than literal — the goal is "this row is the cozy/woodsy one"
    // not perfect iconographic equivalence.
    case musicNote   = "\u{eb66}" // music
    case cocktail    = "\u{ea95}" // honolulu / tropical
    case buildings   = "\u{ea47}" // city skylines
    case coffee      = "\u{ea98}" // sunset camp / cozy warmth
    case lightbulb   = "\u{eb33}" // cozy studio (lamp.desk)
    case home        = "\u{eb05}" // tree house / cabin
    case camera      = "\u{ea69}" // in the woods / macro shot
    case wind        = "\u{ebe3}" // sea side / breeze

    // Bongo mode
    case gamepad     = "\u{eaf4}"
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
        Text(glyph.rawValue)
            .font(.custom(PixelIcons.familyName, size: size))
            // Force the layout to size to the visible glyph rather than
            // the font metrics, so a row of icons aligns vertically by
            // their visual centers regardless of the cap-height of each
            // glyph (some pixelart icons sit higher in the box than
            // others).
            .frame(width: size, height: size)
    }
}
