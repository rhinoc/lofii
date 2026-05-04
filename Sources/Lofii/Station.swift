import SwiftUI

struct LofiiPreset: Identifiable {
    let id: String
    let scene: SceneAsset
    let defaultVariant: SceneVariant
    let radio: RadioStation

    var displayName: String { scene.displayName }

    static let presets: [LofiiPreset] = [
        LofiiPreset(
            id: "chill-vibes",
            scene: SceneCatalog.presets.first { $0.id == "chill-vibes" }!,
            defaultVariant: .nightRain,
            radio: RadioStation(
                displayName: "Lofi Hip Hop Beats",
                providerName: "Chillhop",
                badgeSubtitle: "Live track sync",
                source: .chillhop(stationID: 12354)
            )
        ),
        LofiiPreset(
            id: "sea-side",
            scene: SceneCatalog.presets.first { $0.id == "sea-side" }!,
            defaultVariant: .day,
            radio: RadioStation(
                displayName: "Poolsuite FM",
                providerName: "Poolsuite",
                badgeSubtitle: "Ultra-summer internet radio",
                source: .radioCo(
                    trackID: -3001,
                    stationID: "sc9cb59935"
                )
            )
        ),
        LofiiPreset(
            id: "seoul",
            scene: SceneCatalog.presets.first { $0.id == "seoul" }!,
            defaultVariant: .nightRain,
            radio: RadioStation(
                displayName: "Chill Study Beats",
                providerName: "Chillhop",
                badgeSubtitle: "Live track sync",
                source: .chillhop(stationID: 12363)
            )
        ),
        LofiiPreset(
            id: "honolulu",
            scene: SceneCatalog.presets.first { $0.id == "honolulu" }!,
            defaultVariant: .day,
            radio: RadioStation(
                displayName: "Groove Salad",
                providerName: "SomaFM",
                badgeSubtitle: "Ambient · Downtempo",
                source: .directStream(
                    trackID: -2001,
                    url: URL(string: "https://ice4.somafm.com/groovesalad-128-aac")!
                )
            )
        ),
        LofiiPreset(
            id: "sunset-camping",
            scene: SceneCatalog.presets.first { $0.id == "sunset-camping" }!,
            defaultVariant: .night,
            radio: RadioStation(
                displayName: "Beat Blender",
                providerName: "SomaFM",
                badgeSubtitle: "Downtempo · Trip Hop",
                source: .directStream(
                    trackID: -2002,
                    url: URL(string: "https://ice4.somafm.com/beatblender-128-aac")!
                )
            )
        ),
        LofiiPreset(
            id: "cozy-studio",
            scene: SceneCatalog.presets.first { $0.id == "cozy-studio" }!,
            defaultVariant: .nightRain,
            radio: RadioStation(
                displayName: "Late Night Vibes",
                providerName: "Chillhop",
                badgeSubtitle: "Live track sync",
                source: .chillhop(stationID: 12352)
            )
        ),
        LofiiPreset(
            id: "tree-house",
            scene: SceneCatalog.presets.first { $0.id == "tree-house" }!,
            defaultVariant: .dayRain,
            radio: RadioStation(
                displayName: "Fluid",
                providerName: "SomaFM",
                badgeSubtitle: "Instrumental Hip Hop",
                source: .directStream(
                    trackID: -2003,
                    url: URL(string: "https://ice4.somafm.com/fluid-128-aac")!
                )
            )
        ),
        LofiiPreset(
            id: "in-the-woods",
            scene: SceneCatalog.presets.first { $0.id == "in-the-woods" }!,
            defaultVariant: .day,
            radio: RadioStation(
                displayName: "Drone Zone",
                providerName: "SomaFM",
                badgeSubtitle: "Ambient Drift",
                source: .directStream(
                    trackID: -2004,
                    url: URL(string: "https://ice4.somafm.com/dronezone-128-aac")!
                )
            )
        ),
    ]
}

enum RadioSource: Equatable {
    case chillhop(stationID: Int)
    case directStream(trackID: Int, url: URL)
    case radioCo(trackID: Int, stationID: String)

    var isChillhop: Bool {
        if case .chillhop = self {
            return true
        }
        return false
    }

    var usesLiveBackup: Bool {
        if case .radioCo = self {
            return true
        }
        return false
    }

    var stableID: String {
        switch self {
        case let .chillhop(stationID):
            return "chillhop:\(stationID)"
        case let .directStream(trackID, _):
            return "direct:\(trackID)"
        case let .radioCo(trackID, stationID):
            return "radioco:\(stationID):\(trackID)"
        }
    }
}

struct RadioStation {
    let displayName: String
    let providerName: String
    let badgeSubtitle: String
    let source: RadioSource
}
