import Foundation

struct LiveTrack: Decodable, Identifiable {
    let id: Int
    let fileId: Int
    let artists: String
    let title: String
    let image: URL?
    let duration: Double
    let streamURL: URL
    let startTime: Date
    let endTime: Date
    let isSynchronizedLiveStream: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case fileId
        case artists
        case title
        case image
        case duration
        case streamURL = "streamUrl"
        case startTime
        case endTime
    }

    init(
        id: Int,
        fileId: Int,
        artists: String,
        title: String,
        image: URL?,
        duration: Double,
        streamURL: URL,
        startTime: Date,
        endTime: Date,
        isSynchronizedLiveStream: Bool = true
    ) {
        self.id = id
        self.fileId = fileId
        self.artists = artists
        self.title = title
        self.image = image
        self.duration = duration
        self.streamURL = streamURL
        self.startTime = startTime
        self.endTime = endTime
        self.isSynchronizedLiveStream = isSynchronizedLiveStream
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        fileId = try container.decode(Int.self, forKey: .fileId)
        artists = try container.decode(String.self, forKey: .artists)
        title = try container.decode(String.self, forKey: .title)
        image = try container.decodeIfPresent(URL.self, forKey: .image)
        duration = try container.decode(Double.self, forKey: .duration)
        streamURL = try container.decode(URL.self, forKey: .streamURL)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decode(Date.self, forKey: .endTime)
        isSynchronizedLiveStream = true
    }

    func elapsedPlaybackSeconds(relativeTo now: Date = .now) -> TimeInterval {
        guard isSynchronizedLiveStream else { return 0 }
        let elapsed = now.timeIntervalSince(startTime)
        return min(max(elapsed, 0), duration)
    }

    func contains(_ date: Date) -> Bool {
        startTime <= date && date < endTime
    }

    static func directStream(
        id: Int,
        title: String,
        artists: String,
        streamURL: URL,
        now: Date = .now
    ) -> LiveTrack {
        LiveTrack(
            id: id,
            fileId: id,
            artists: artists,
            title: title,
            image: nil,
            duration: 0,
            streamURL: streamURL,
            startTime: now,
            endTime: now,
            isSynchronizedLiveStream: false
        )
    }
}

extension Array where Element == LiveTrack {
    func liveTrackIndex(relativeTo now: Date = .now) -> Int? {
        if let currentIndex = firstIndex(where: { $0.contains(now) }) {
            return currentIndex
        }

        if let nextIndex = firstIndex(where: { $0.startTime > now }) {
            return nextIndex
        }

        return isEmpty ? nil : startIndex
    }
}

struct ChillhopService {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let baseURL = URL(string: "https://stream.chillhop.com")!

    init(session: URLSession = .shared) {
        self.session = session

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = try? Date(value, strategy: DateParsers.fractional) {
                return date
            }

            guard let date = try? Date(value, strategy: DateParsers.plain) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(value)")
            }

            return date
        }

        self.decoder = decoder
    }

    func fetchLiveTracks(stationID: Int) async throws -> [LiveTrack] {
        let url = baseURL.appending(path: "live/\(stationID)")
        let (data, response) = try await session.data(from: url)

        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw ChillhopServiceError.invalidResponse
        }

        let tracks = try decoder.decode([LiveTrack].self, from: data)
        guard !tracks.isEmpty else {
            throw ChillhopServiceError.emptyPlaylist
        }

        return tracks
    }
}

private enum DateParsers {
    static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    static let plain = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
}

enum ChillhopServiceError: LocalizedError {
    case invalidResponse
    case emptyPlaylist

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Chillhop stream API returned an invalid response."
        case .emptyPlaylist:
            return "Chillhop stream API returned no live track."
        }
    }
}
