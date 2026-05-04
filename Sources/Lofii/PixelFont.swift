import SwiftUI
import AppKit
import CoreText

/// Bundles + registers **Doto** from
/// `Resources/Fonts/Doto[ROND,wght].ttf`.
///
/// Doto (https://fonts.google.com/specimen/Doto, OFL 1.1) is variable on
/// `wght` (100–900) and `ROND` (0–100). We register once at launch and drive
/// axes through CoreText for the readout.
enum PixelFont {
    /// Family name from `CTFontCopyFamilyName` on the bundled VF.
    static let familyName = "Doto"

    @MainActor private static var registered = false

    /// Registers the bundled .ttf with CoreText. Safe to call multiple
    /// times — `alreadyRegistered` is treated as success.
    @MainActor
    static func registerIfNeeded() {
        guard !registered else { return }
        registered = true

        guard let url = LofiiResources.bundle.url(
            forResource: "Doto[ROND,wght]",
            withExtension: "ttf",
            subdirectory: "Fonts"
        ) else {
            assertionFailure("Doto variable font missing from bundle")
            return
        }

        var error: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if !ok, let err = error?.takeRetainedValue() {
            let code = CFErrorGetCode(err)
            if code != 105 {
                assertionFailure("Failed to register Doto: \(err)")
            }
        }
    }
}

extension Font {
    /// Readout / chrome pixel font at a semantic SwiftUI weight.
    static func pixel(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        Font.custom(PixelFont.familyName, size: size).weight(weight)
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

    static func makeVariableCTFont(
        size: CGFloat,
        weightAxis: Double,
        elementShape: Double
    ) -> CTFont? {
        let base = CTFontCreateWithName(familyName as CFString, size, nil)
        let variations: [NSNumber: NSNumber] = [
            NSNumber(value: weightAxisTag): NSNumber(value: max(100, min(weightAxis, 900))),
            NSNumber(value: roundnessAxisTag): NSNumber(value: max(0, min(elementShape, 100))),
        ]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(base),
            [kCTFontVariationAttribute: variations] as CFDictionary
        )
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    private static func fourCharTag(_ value: String) -> UInt32 {
        value.utf8.reduce(0) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
    }
}
