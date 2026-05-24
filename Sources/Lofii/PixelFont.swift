import SwiftUI
import AppKit
import CoreText

/// Bundles + registers **Doto** from
/// `Resources/Fonts/Doto[ROND,wght].ttf`, with BoutiqueBitmap9x9 Square Dot
/// as the CJK fallback face.
///
/// Doto (https://fonts.google.com/specimen/Doto, OFL 1.1) is variable on
/// `wght` (100–900) and `ROND` (0–100). We register once at launch and drive
/// axes through CoreText for the readout. Doto remains the primary face; the
/// BoutiqueBitmap fallback is only used for glyphs Doto does not cover.
enum PixelFont {
    /// Family name from `CTFontCopyFamilyName` on the bundled VF.
    static let familyName = "Doto"
    static let fallbackFamilyName = "BoutiqueBitmap9x9 Square Dot"

    @MainActor private static var registered = false

    /// Registers the bundled .ttfs with CoreText. Safe to call multiple
    /// times — `alreadyRegistered` is treated as success.
    @MainActor
    static func registerIfNeeded() {
        guard !registered else { return }
        registered = true

        registerFont(
            forResource: "Doto[ROND,wght]",
            missingMessage: "Doto variable font missing from bundle",
            failureMessage: "Failed to register Doto"
        )
        registerFont(
            forResource: "BoutiqueBitmap9x9_Square_Dot",
            missingMessage: "BoutiqueBitmap9x9 Square Dot font missing from bundle",
            failureMessage: "Failed to register BoutiqueBitmap9x9 Square Dot"
        )
    }
}

extension Font {
    /// Readout / chrome pixel font at a semantic SwiftUI weight.
    static func pixel(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        let font = PixelFont.makeCascadingCTFont(
            size: size,
            weightAxis: PixelFont.weightAxis(for: weight),
            elementShape: nil
        )
        return font.map(Font.init) ?? Font.custom(PixelFont.familyName, size: size).weight(weight)
    }

    /// Variable-font readout: `wght` plus Doto `ROND`.
    static func pixel(
        size: CGFloat,
        weightAxis: Double,
        elementShape: Double
    ) -> Font {
        let font = PixelFont.makeVariableCTFont(
            size: size,
            weightAxis: weightAxis,
            elementShape: elementShape
        )
        return font.map(Font.init) ?? Font.custom(PixelFont.familyName, size: size)
    }
}

extension PixelFont {
    private static let weightAxisTag = fourCharTag("wght")
    private static let roundnessAxisTag = fourCharTag("ROND")

    @MainActor
    private static func registerFont(
        forResource resource: String,
        missingMessage: String,
        failureMessage: String
    ) {
        guard let url = LofiiResources.bundle.url(
            forResource: resource,
            withExtension: "ttf",
            subdirectory: "Fonts"
        ) else {
            assertionFailure(missingMessage)
            return
        }

        var error: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if !ok, let err = error?.takeRetainedValue() {
            let code = CFErrorGetCode(err)
            if code != 105 {
                assertionFailure("\(failureMessage): \(err)")
            }
        }
    }

    static func makeVariableCTFont(
        size: CGFloat,
        weightAxis: Double,
        elementShape: Double
    ) -> CTFont? {
        makeCascadingCTFont(
            size: size,
            weightAxis: weightAxis,
            elementShape: elementShape
        )
    }

    static func makeNSFont(size: CGFloat, weight: Font.Weight = .semibold) -> NSFont? {
        makeCascadingCTFont(
            size: size,
            weightAxis: weightAxis(for: weight),
            elementShape: nil
        ).map { $0 as NSFont }
    }

    static func makeCascadingCTFont(
        size: CGFloat,
        weightAxis: Double,
        elementShape: Double?
    ) -> CTFont? {
        let base = CTFontCreateWithName(familyName as CFString, size, nil)
        var variations: [NSNumber: NSNumber] = [
            NSNumber(value: weightAxisTag): NSNumber(value: max(100, min(weightAxis, 900))),
        ]
        if let elementShape {
            variations[NSNumber(value: roundnessAxisTag)] = NSNumber(value: max(0, min(elementShape, 100)))
        }
        let fallbackDescriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: fallbackFamilyName,
        ] as CFDictionary)
        let attributes: [CFString: Any] = [
            kCTFontVariationAttribute: variations,
            kCTFontCascadeListAttribute: [fallbackDescriptor],
        ]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(base),
            attributes as CFDictionary
        )
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    static func weightAxis(for weight: Font.Weight) -> Double {
        if weight == .ultraLight { return 200 }
        if weight == .thin { return 250 }
        if weight == .light { return 300 }
        if weight == .regular { return 400 }
        if weight == .medium { return 500 }
        if weight == .semibold { return 600 }
        if weight == .bold { return 700 }
        if weight == .heavy { return 800 }
        if weight == .black { return 900 }
        return 600
    }

    private static func fourCharTag(_ value: String) -> UInt32 {
        value.utf8.reduce(0) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
    }
}
