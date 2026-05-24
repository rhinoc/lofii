import AppKit
import Foundation
import SwiftUI

struct CustomStation: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case youtube
        case directVideo
        case directAudio
    }

    let id: UUID
    var kind: Kind
    var name: String
    var url: String
    var videoID: String
    var iconID: String
    var themeColorHex: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        kind: Kind = .youtube,
        name: String,
        url: String,
        videoID: String,
        iconID: String = PixelGlyph.headphone.stableID,
        themeColorHex: String = StationThemeColor.pink.hex,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.url = url
        self.videoID = videoID
        self.iconID = iconID
        self.themeColorHex = StationThemeColor.validatedHex(themeColorHex)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case name
        case url
        case videoID
        case iconID
        case themeColorHex
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(Kind.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        videoID = try container.decode(String.self, forKey: .videoID)
        iconID = try container.decode(String.self, forKey: .iconID)
        themeColorHex = StationThemeColor.validatedHex(
            try container.decode(String.self, forKey: .themeColorHex)
        )
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct BuiltInStationOverride: Codable, Equatable, Identifiable {
    var id: String { presetID }

    let presetID: String
    var kind: CustomStation.Kind
    var name: String
    var url: String
    var videoID: String
    var iconID: String
    var themeColorHex: String
    var updatedAt: Date

    init(
        presetID: String,
        kind: CustomStation.Kind = .youtube,
        name: String,
        url: String,
        videoID: String,
        iconID: String,
        themeColorHex: String,
        updatedAt: Date = Date()
    ) {
        self.presetID = presetID
        self.kind = kind
        self.name = name
        self.url = url
        self.videoID = videoID
        self.iconID = iconID
        self.themeColorHex = StationThemeColor.validatedHex(themeColorHex)
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case presetID
        case kind
        case name
        case url
        case videoID
        case iconID
        case themeColorHex
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        presetID = try container.decode(String.self, forKey: .presetID)
        kind = try container.decode(CustomStation.Kind.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        videoID = try container.decode(String.self, forKey: .videoID)
        iconID = try container.decode(String.self, forKey: .iconID)
        themeColorHex = StationThemeColor.validatedHex(
            try container.decode(String.self, forKey: .themeColorHex)
        )
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct CustomStationDocument: Codable, Equatable {
    static let currentSchemaVersion = 3

    var schemaVersion: Int
    var stations: [CustomStation]
    var builtInOverrides: [BuiltInStationOverride]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        stations: [CustomStation],
        builtInOverrides: [BuiltInStationOverride] = []
    ) {
        self.schemaVersion = schemaVersion
        self.stations = stations
        self.builtInOverrides = builtInOverrides
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case stations
        case builtInOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        stations = try container.decode([CustomStation].self, forKey: .stations)
        builtInOverrides = try container.decode(
            [BuiltInStationOverride].self,
            forKey: .builtInOverrides
        )
    }
}

enum StationThemeColor: String, CaseIterable, Identifiable, Codable {
    case pink = "#FF6AD5"
    case red = "#FF5C7A"
    case amber = "#FFBD66"
    case lime = "#D7F75B"
    case sky = "#9EDBFF"
    case coral = "#FF8C4D"
    case mint = "#A8F2BD"
    case green = "#9EF29E"
    case cyan = "#73DBFF"
    case blue = "#6AA8FF"
    case violet = "#B79CFF"

    var id: String { rawValue }
    var hex: String { rawValue }

    var label: String {
        switch self {
        case .pink: return "Pink"
        case .red: return "Red"
        case .amber: return "Amber"
        case .lime: return "Lime"
        case .sky: return "Sky"
        case .coral: return "Coral"
        case .mint: return "Mint"
        case .green: return "Green"
        case .cyan: return "Cyan"
        case .blue: return "Blue"
        case .violet: return "Violet"
        }
    }

    var color: Color {
        Color(hex: hex) ?? .white
    }

    static func validatedHex(_ value: String) -> String {
        let normalized = normalizeHex(value)
        if allCases.contains(where: { $0.hex == normalized }) {
            return normalized
        }
        return pink.hex
    }

    static func nearest(to color: Color) -> StationThemeColor {
        guard let rgb = color.rgbComponents else { return .pink }
        return allCases.min { lhs, rhs in
            distanceSquared(lhs.color.rgbComponents, rgb) < distanceSquared(rhs.color.rgbComponents, rgb)
        } ?? .pink
    }

    private static func normalizeHex(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let body = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard body.count == 6,
              body.allSatisfy({ $0.isHexDigit })
        else { return pink.hex }
        return "#\(body)"
    }

    private static func distanceSquared(_ lhs: (Double, Double, Double)?, _ rhs: (Double, Double, Double)) -> Double {
        guard let lhs else { return .infinity }
        let red = lhs.0 - rhs.0
        let green = lhs.1 - rhs.1
        let blue = lhs.2 - rhs.2
        return red * red + green * green + blue * blue
    }
}

extension Color {
    init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard body.count == 6,
              let value = Int(body, radix: 16)
        else { return nil }

        self.init(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }

    var hexRGB: String? {
        guard let color = rgbComponents else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int(round(color.0 * 255)),
            Int(round(color.1 * 255)),
            Int(round(color.2 * 255))
        )
    }

    fileprivate var rgbComponents: (Double, Double, Double)? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else {
            return nil
        }
        return (
            Double(color.redComponent),
            Double(color.greenComponent),
            Double(color.blueComponent)
        )
    }
}

enum YouTubeURLParser {
    static func videoID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if isValidVideoID(trimmed) {
            return trimmed
        }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: candidate),
              let host = components.host?.lowercased()
        else { return nil }

        let pathParts = components.path
            .split(separator: "/")
            .map(String.init)

        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            return validated(pathParts.first)
        }

        guard host == "youtube.com" || host.hasSuffix(".youtube.com") else {
            return nil
        }

        if components.path == "/watch" {
            let id = components.queryItems?.first(where: { $0.name == "v" })?.value
            return validated(id)
        }

        guard let first = pathParts.first else { return nil }
        switch first {
        case "embed", "live", "shorts":
            return validated(pathParts.dropFirst().first)
        default:
            return nil
        }
    }

    private static func validated(_ value: String?) -> String? {
        guard let value, isValidVideoID(value) else {
            return nil
        }
        return value
    }

    private static func isValidVideoID(_ value: String) -> Bool {
        guard value.count == 11 else { return false }
        return value.allSatisfy { character in
            character.isLetter || character.isNumber || character == "_" || character == "-"
        }
    }
}

enum CustomStationSource: Equatable {
    case youtube(videoID: String)
    case directVideo(url: URL)
    case directAudio(url: URL)

    var kind: CustomStation.Kind {
        switch self {
        case .youtube:
            return .youtube
        case .directVideo:
            return .directVideo
        case .directAudio:
            return .directAudio
        }
    }

    var videoID: String {
        switch self {
        case let .youtube(videoID):
            return videoID
        case .directVideo, .directAudio:
            return ""
        }
    }

    var identity: String {
        switch self {
        case let .youtube(videoID):
            return "youtube:\(videoID)"
        case let .directVideo(url):
            return "direct-video:\(url.absoluteString)"
        case let .directAudio(url):
            return "direct-audio:\(url.absoluteString)"
        }
    }
}

enum CustomStationSourceResolver {
    private static let videoExtensions: Set<String> = [
        "m3u8",
        "mp4",
        "m4v",
        "mov",
        "webm",
        "mkv",
    ]
    private static let audioExtensions: Set<String> = [
        "aac",
        "flac",
        "m4a",
        "mp3",
        "ogg",
        "opus",
        "wav",
    ]
    private static let audioPathSuffixes: [String] = [
        "-aac",
        "-aacp",
        "-flac",
        "-m4a",
        "-mp3",
        "-ogg",
        "-opus",
        "-wav",
    ]

    static func resolve(_ input: String) -> CustomStationSource? {
        if let videoID = YouTubeURLParser.videoID(from: input) {
            return .youtube(videoID: videoID)
        }

        guard let url = directMediaURL(from: input) else { return nil }

        return resolve(url: url, contentType: nil)
    }

    static func resolveWithProbe(_ input: String) async -> CustomStationSource? {
        if let source = resolve(input) {
            return source
        }
        guard let url = directMediaURL(from: input),
              let contentType = await probeContentType(for: url)
        else { return nil }
        return resolve(url: url, contentType: contentType)
    }

    static func resolve(url: URL, contentType: String?) -> CustomStationSource? {
        let pathExtension = url.pathExtension.lowercased()
        if videoExtensions.contains(pathExtension) {
            return .directVideo(url: url)
        }
        if audioExtensions.contains(pathExtension) {
            return .directAudio(url: url)
        }

        let lastPathComponent = url.lastPathComponent.lowercased()
        if audioPathSuffixes.contains(where: { lastPathComponent.hasSuffix($0) }) {
            return .directAudio(url: url)
        }

        guard let contentType else { return nil }
        let normalizedContentType = contentType
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if normalizedContentType.hasPrefix("video/") ||
            normalizedContentType == "application/vnd.apple.mpegurl" ||
            normalizedContentType == "application/x-mpegurl" ||
            normalizedContentType == "application/mpegurl" ||
            normalizedContentType == "audio/mpegurl" {
            return .directVideo(url: url)
        }

        let octetStreamWithAudioHint =
            normalizedContentType == "application/octet-stream" &&
            audioPathSuffixes.contains { suffix in
                lastPathComponent.contains(suffix.dropFirst())
            }

        if normalizedContentType.hasPrefix("audio/") ||
            normalizedContentType == "application/ogg" ||
            octetStreamWithAudioHint {
            return .directAudio(url: url)
        }

        return nil
    }

    private static func directMediaURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { return nil }
        return url
    }

    private static func probeContentType(for url: URL) async -> String? {
        var headRequest = URLRequest(url: url)
        headRequest.httpMethod = "HEAD"
        headRequest.timeoutInterval = 6
        headRequest.setValue("Lofii/1.0", forHTTPHeaderField: "User-Agent")
        if let contentType = await contentType(for: headRequest) {
            return contentType
        }

        var rangeRequest = URLRequest(url: url)
        rangeRequest.httpMethod = "GET"
        rangeRequest.timeoutInterval = 6
        rangeRequest.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        rangeRequest.setValue("Lofii/1.0", forHTTPHeaderField: "User-Agent")
        return await contentType(for: rangeRequest)
    }

    private static func contentType(for request: URLRequest) async -> String? {
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<400).contains(http.statusCode)
            else { return nil }
            return http.value(forHTTPHeaderField: "Content-Type") ?? response.mimeType
        } catch {
            return nil
        }
    }

    static func resolve(station: CustomStation) -> CustomStationSource? {
        switch station.kind {
        case .youtube:
            let candidate = station.videoID.isEmpty ? station.url : station.videoID
            guard let videoID = YouTubeURLParser.videoID(from: candidate) else {
                return nil
            }
            return .youtube(videoID: videoID)
        case .directVideo:
            guard let url = directMediaURL(from: station.url) else {
                return nil
            }
            return .directVideo(url: url)
        case .directAudio:
            guard let url = directMediaURL(from: station.url) else {
                return nil
            }
            return .directAudio(url: url)
        }
    }

    static func resolve(override: BuiltInStationOverride) -> CustomStationSource? {
        switch override.kind {
        case .youtube:
            let candidate = override.videoID.isEmpty ? override.url : override.videoID
            guard let videoID = YouTubeURLParser.videoID(from: candidate) else {
                return nil
            }
            return .youtube(videoID: videoID)
        case .directVideo:
            guard let url = directMediaURL(from: override.url) else {
                return nil
            }
            return .directVideo(url: url)
        case .directAudio:
            guard let url = directMediaURL(from: override.url) else {
                return nil
            }
            return .directAudio(url: url)
        }
    }
}

struct CustomStationStore {
    let fileURL: URL

    init(fileURL: URL = Self.defaultFileURL()) {
        self.fileURL = fileURL
    }

    func loadDocument() -> CustomStationDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return CustomStationDocument(stations: [])
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let document = try decoder.decode(CustomStationDocument.self, from: data)
            guard document.schemaVersion == CustomStationDocument.currentSchemaVersion else {
                DiagnosticLog.appendPlayback(
                    "customStations.loadUnsupportedSchema version=\(document.schemaVersion)"
                )
                return CustomStationDocument(stations: [])
            }
            return CustomStationDocument(
                stations: document.stations.filter { CustomStationSourceResolver.resolve(station: $0) != nil },
                builtInOverrides: document.builtInOverrides.filter {
                    CustomStationSourceResolver.resolve(override: $0) != nil
                }
            )
        } catch {
            DiagnosticLog.appendPlayback(
                "customStations.loadFailed error=\"\(error.localizedDescription)\""
            )
            return CustomStationDocument(stations: [])
        }
    }

    func load() -> [CustomStation] {
        loadDocument().stations
    }

    func save(_ stations: [CustomStation]) throws {
        try save(CustomStationDocument(stations: stations))
    }

    func save(_ document: CustomStationDocument) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("Lofii", isDirectory: true)
            .appendingPathComponent("custom-stations.json", isDirectory: false)
    }
}

enum CustomStationValidationError: LocalizedError, Equatable {
    case missingName
    case invalidStationURL
    case duplicateStation

    var errorDescription: String? {
        switch self {
        case .missingName:
            return "Name is required."
        case .invalidStationURL:
            return "Paste a YouTube, video, or audio stream URL."
        case .duplicateStation:
            return "This station is already in your list."
        }
    }
}

extension PixelGlyph {
    static let customStationIconChoices: [PixelGlyph] = [
        .headphone,
        .album,
        .bookmark,
        .heart,
        .leaf,
        .fire,
        .treePine,
        .star,
        .sparkles,
        .sofa,
        .smartHome,
    ]

    static let builtInStationIconChoices: [PixelGlyph] = [
        .musicNote,
        .cocktail,
        .buildings,
        .coffee,
        .lightbulb,
        .home,
        .camera,
        .wind,
    ]

    var stableID: String {
        switch self {
        case .headphone: return "headphone"
        case .album: return "album"
        case .bookmark: return "bookmark"
        case .heart: return "heart"
        case .leaf: return "leaf"
        case .fire: return "fire"
        case .treePine: return "treePine"
        case .star: return "star"
        case .sparkles: return "sparkles"
        case .sofa: return "sofa"
        case .smartHome: return "smartHome"
        case .radioSignal: return "radioSignal"
        case .musicNote: return "musicNote"
        case .coffee: return "coffee"
        case .moon: return "moon"
        case .sun: return "sun"
        case .home: return "home"
        case .cocktail: return "cocktail"
        case .buildings: return "buildings"
        case .lightbulb: return "lightbulb"
        case .camera: return "camera"
        case .wind: return "wind"
        default: return PixelGlyph.headphone.stableID
        }
    }

    static func customStationIcon(id: String) -> PixelGlyph {
        switch id {
        case "headphone": return .headphone
        case "album": return .album
        case "bookmark": return .bookmark
        case "heart": return .heart
        case "leaf": return .leaf
        case "fire": return .fire
        case "treePine": return .treePine
        case "star": return .star
        case "sparkles": return .sparkles
        case "sofa": return .sofa
        case "smartHome": return .smartHome
        default: return .headphone
        }
    }

    static func builtInStationIcon(id: String) -> PixelGlyph {
        switch id {
        case "musicNote": return .musicNote
        case "cocktail": return .cocktail
        case "buildings": return .buildings
        case "coffee": return .coffee
        case "lightbulb": return .lightbulb
        case "home": return .home
        case "camera": return .camera
        case "wind": return .wind
        default: return customStationIcon(id: id)
        }
    }
}
