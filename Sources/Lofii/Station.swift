import SwiftUI

struct LofiiPreset: Identifiable {
    let id: String
    let scene: SceneAsset
    let defaultVariant: SceneVariant
    let radio: RadioStation
    var customStationID: UUID? = nil
    var builtInOverrideID: String? = nil
    var customDisplayName: String? = nil
    var customIcon: PixelGlyph? = nil
    var customAccent: Color? = nil

    var displayName: String { customDisplayName ?? scene.displayName }
    var pickerGlyph: PixelGlyph { customIcon ?? scene.glyph }
    var isCustom: Bool { customStationID != nil }
    var isBuiltInOverride: Bool { builtInOverrideID != nil }
    var isUserConfigured: Bool { isCustom || isBuiltInOverride }
    var pickerAccent: Color { customAccent ?? scene.palette.accent }

    static let presets: [LofiiPreset] = [
        LofiiPreset(
            id: "chill-vibes",
            scene: SceneCatalog.presets.first { $0.id == "chill-vibes" }!,
            defaultVariant: .nightRain,
            radio: RadioStation(
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
                providerName: "Chillhop",
                badgeSubtitle: "Live track sync",
                source: .chillhop(stationID: 12363)
            )
        ),
        LofiiPreset(
            id: "cozy-studio",
            scene: SceneCatalog.presets.first { $0.id == "cozy-studio" }!,
            defaultVariant: .nightRain,
            radio: RadioStation(
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
                providerName: "SomaFM",
                badgeSubtitle: "Instrumental Hip Hop",
                source: .directStream(
                    trackID: -2003,
                    url: URL(string: "https://ice4.somafm.com/fluid-128-aac")!
                )
            )
        ),
    ]
}

enum RadioSource: Equatable {
    case chillhop(stationID: Int)
    case directStream(trackID: Int, url: URL)
    case directVideo(trackID: Int, url: URL)
    case radioCo(trackID: Int, stationID: String)
    case youtube(videoID: String)

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

    var isYouTube: Bool {
        if case .youtube = self {
            return true
        }
        return false
    }

    var supportsTrackArtwork: Bool {
        switch self {
        case .chillhop, .radioCo:
            return true
        case .directStream, .directVideo, .youtube:
            return false
        }
    }

    var youtubeVideoID: String? {
        if case let .youtube(videoID) = self {
            return videoID
        }
        return nil
    }

    var directVideoURL: URL? {
        if case let .directVideo(_, url) = self {
            return url
        }
        return nil
    }

    var stableID: String {
        switch self {
        case let .chillhop(stationID):
            return "chillhop:\(stationID)"
        case let .directStream(trackID, _):
            return "direct:\(trackID)"
        case let .directVideo(trackID, _):
            return "direct-video:\(trackID)"
        case let .radioCo(trackID, stationID):
            return "radioco:\(stationID):\(trackID)"
        case let .youtube(videoID):
            return "youtube:\(videoID)"
        }
    }
}

struct RadioStation {
    let providerName: String
    let badgeSubtitle: String
    let source: RadioSource
}

extension CustomStation {
    func lofiiPreset(defaultScene: SceneAsset) -> LofiiPreset {
        let resolvedSource = CustomStationSourceResolver.resolve(station: self)
        let radioStation: RadioStation
        switch resolvedSource {
        case let .youtube(videoID):
            radioStation = RadioStation(
                providerName: "YouTube",
                badgeSubtitle: "Embedded video",
                source: .youtube(videoID: videoID)
            )
        case let .directVideo(url):
            radioStation = RadioStation(
                providerName: "Direct Video",
                badgeSubtitle: "Direct media URL",
                source: .directVideo(trackID: Self.stableNegativeID(for: id), url: url)
            )
        case let .directAudio(url):
            radioStation = RadioStation(
                providerName: "Direct Audio",
                badgeSubtitle: "Direct audio stream",
                source: .directStream(trackID: Self.stableNegativeID(for: id), url: url)
            )
        case nil:
            radioStation = RadioStation(
                providerName: "YouTube",
                badgeSubtitle: "Embedded video",
                source: .youtube(videoID: videoID)
            )
        }

        return LofiiPreset(
            id: "custom-\(kind.rawValue)-\(id.uuidString)",
            scene: defaultScene,
            defaultVariant: .nightRain,
            radio: radioStation,
            customStationID: id,
            customDisplayName: name,
            customIcon: PixelGlyph.customStationIcon(id: iconID),
            customAccent: Color(hex: themeColorHex)
        )
    }

    private static func stableNegativeID(for id: UUID) -> Int {
        let hash = id.uuidString.unicodeScalars.reduce(0) { partial, scalar in
            partial &* 31 &+ Int(scalar.value)
        }
        return -abs(hash == Int.min ? 0 : hash)
    }
}

extension BuiltInStationOverride {
    func apply(to preset: LofiiPreset) -> LofiiPreset {
        let resolvedSource = CustomStationSourceResolver.resolve(override: self)
        let radioStation: RadioStation
        switch resolvedSource {
        case let .youtube(videoID):
            radioStation = RadioStation(
                providerName: "YouTube",
                badgeSubtitle: "Embedded video",
                source: .youtube(videoID: videoID)
            )
        case let .directVideo(url):
            radioStation = RadioStation(
                providerName: "Direct Video",
                badgeSubtitle: "Direct media URL",
                source: .directVideo(trackID: Self.stableNegativeID(for: presetID), url: url)
            )
        case let .directAudio(url):
            radioStation = RadioStation(
                providerName: "Direct Audio",
                badgeSubtitle: "Direct audio stream",
                source: .directStream(trackID: Self.stableNegativeID(for: presetID), url: url)
            )
        case nil:
            radioStation = RadioStation(
                providerName: "YouTube",
                badgeSubtitle: "Embedded video",
                source: .youtube(videoID: videoID)
            )
        }

        return LofiiPreset(
            id: preset.id,
            scene: preset.scene,
            defaultVariant: preset.defaultVariant,
            radio: radioStation,
            builtInOverrideID: presetID,
            customDisplayName: name,
            customIcon: PixelGlyph.builtInStationIcon(id: iconID),
            customAccent: Color(hex: themeColorHex)
        )
    }

    private static func stableNegativeID(for value: String) -> Int {
        let hash = value.unicodeScalars.reduce(0) { partial, scalar in
            partial &* 31 &+ Int(scalar.value)
        }
        return -abs(hash == Int.min ? 0 : hash)
    }
}
