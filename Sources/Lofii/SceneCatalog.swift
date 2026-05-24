import Foundation
import SwiftUI

enum SceneVariant: String, CaseIterable, Identifiable, Codable, Sendable {
    case day
    case dayRain = "day-rain"
    case night
    case nightRain = "night-rain"

    var id: String { rawValue }

    /// Pixel glyph used in the variant-cycle button. Pixelarticons doesn't
    /// have rain-specific weather glyphs, so we lean on `cloudSun` /
    /// `cloudMoon` for the rainy variants — the cloud reads as "weather"
    /// next to a clear sun/moon for the dry variants.
    var glyph: PixelGlyph {
        switch self {
        case .day: return .sun
        case .dayRain: return .cloudSun
        case .night: return .moon
        case .nightRain: return .cloudMoon
        }
    }

    var label: String {
        switch self {
        case .day: return "Day"
        case .dayRain: return "Day · Rain"
        case .night: return "Night"
        case .nightRain: return "Night · Rain"
        }
    }
}

struct SceneAsset: Identifiable, Sendable {
    let id: String
    let displayName: String
    /// Pixel glyph shown in the StationPicker row. See `PixelGlyph` for
    /// the full set; matches are evocative rather than literal because the
    /// free pixelarticons set doesn't cover every SF Symbol equivalent.
    let glyph: PixelGlyph
    let palette: ScenePalette

    func videoURL(variant: SceneVariant) -> URL {
        URL(string: "https://cdn.jsdelivr.net/gh/itzashoffcl/lofi-resources/scenes/\(id)/\(variant.rawValue).mp4")!
    }
}

struct ScenePalette: Sendable {
    let accent: Color
    let highlight: Color
    let backdropTop: Color
    let backdropBottom: Color
}

enum SceneCatalog {
    static let presets: [SceneAsset] = [
        SceneAsset(
            id: "chill-vibes",
            displayName: "Chill Vibes",
            glyph: .musicNote,
            palette: ScenePalette(
                accent: Color(red: 1.00, green: 0.42, blue: 0.83),
                highlight: Color(red: 0.36, green: 0.95, blue: 1.00),
                backdropTop: Color(red: 0.10, green: 0.04, blue: 0.22),
                backdropBottom: Color(red: 0.65, green: 0.18, blue: 0.50)
            )
        ),
        SceneAsset(
            id: "honolulu",
            displayName: "Honolulu",
            glyph: .cocktail,
            palette: ScenePalette(
                accent: Color(red: 1.00, green: 0.74, blue: 0.40),
                highlight: Color(red: 0.62, green: 1.00, blue: 0.84),
                backdropTop: Color(red: 0.08, green: 0.05, blue: 0.20),
                backdropBottom: Color(red: 0.88, green: 0.45, blue: 0.55)
            )
        ),
        SceneAsset(
            id: "seoul",
            displayName: "Seoul",
            glyph: .buildings,
            palette: ScenePalette(
                accent: Color(red: 0.62, green: 0.86, blue: 1.00),
                highlight: Color(red: 1.00, green: 0.71, blue: 0.92),
                backdropTop: Color(red: 0.05, green: 0.06, blue: 0.18),
                backdropBottom: Color(red: 0.30, green: 0.15, blue: 0.45)
            )
        ),
        SceneAsset(
            id: "sunset-camping",
            displayName: "Sunset Camp",
            glyph: .coffee,
            palette: ScenePalette(
                accent: Color(red: 1.00, green: 0.55, blue: 0.30),
                highlight: Color(red: 1.00, green: 0.85, blue: 0.55),
                backdropTop: Color(red: 0.08, green: 0.04, blue: 0.18),
                backdropBottom: Color(red: 0.85, green: 0.40, blue: 0.30)
            )
        ),
        SceneAsset(
            id: "cozy-studio",
            displayName: "Cosy Studio",
            glyph: .lightbulb,
            palette: ScenePalette(
                accent: Color(red: 1.00, green: 0.76, blue: 0.41),
                highlight: Color(red: 1.00, green: 0.54, blue: 0.39),
                backdropTop: Color(red: 0.10, green: 0.06, blue: 0.05),
                backdropBottom: Color(red: 0.36, green: 0.18, blue: 0.12)
            )
        ),
        SceneAsset(
            id: "tree-house",
            displayName: "Tree House",
            glyph: .home,
            palette: ScenePalette(
                accent: Color(red: 0.66, green: 0.95, blue: 0.74),
                highlight: Color(red: 0.96, green: 0.85, blue: 0.55),
                backdropTop: Color(red: 0.06, green: 0.10, blue: 0.10),
                backdropBottom: Color(red: 0.18, green: 0.30, blue: 0.22)
            )
        ),
        SceneAsset(
            id: "in-the-woods",
            displayName: "In the Woods",
            glyph: .camera,
            palette: ScenePalette(
                accent: Color(red: 0.62, green: 0.95, blue: 0.62),
                highlight: Color(red: 1.00, green: 0.92, blue: 0.62),
                backdropTop: Color(red: 0.05, green: 0.10, blue: 0.08),
                backdropBottom: Color(red: 0.25, green: 0.36, blue: 0.18)
            )
        ),
        SceneAsset(
            id: "sea-side",
            displayName: "Seaside",
            glyph: .wind,
            palette: ScenePalette(
                accent: Color(red: 0.45, green: 0.86, blue: 1.00),
                highlight: Color(red: 0.95, green: 0.88, blue: 0.62),
                backdropTop: Color(red: 0.04, green: 0.10, blue: 0.18),
                backdropBottom: Color(red: 0.20, green: 0.45, blue: 0.55)
            )
        ),
    ]
}
