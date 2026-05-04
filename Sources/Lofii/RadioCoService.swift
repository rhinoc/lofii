import Foundation

struct RadioCoSnapshot {
    let track: LiveTrack
    let bitrate: Int?
}

struct RadioCoService {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            return try Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: false))
        }
        self.decoder = decoder
    }

    func fetchSnapshot(
        stationID: String,
        trackID: Int,
        fallbackTitle: String,
        fallbackArtists: String
    ) async throws -> RadioCoSnapshot {
        async let status = fetchStatus(stationID: stationID)
        async let currentTrack = fetchCurrentTrack(stationID: stationID)

        let (stationStatus, nowPlaying) = try await (status, currentTrack)

        guard let output = stationStatus.outputs.first(where: { $0.name == "listen" }) ?? stationStatus.outputs.first,
              let streamURL = URL(string: "https://\(stationStatus.streamingHostname)/\(stationID)/\(output.name)")
        else {
            throw RadioCoServiceError.invalidStationStatus
        }

        let parsed = ParsedTrackTitle(
            rawTitle: nowPlaying.data.title,
            fallbackTitle: fallbackTitle,
            fallbackArtists: fallbackArtists,
            preferredArtist: nowPlaying.data.trackArtist,
            preferredTitle: nowPlaying.data.trackTitle
        )

        let duration = nowPlaying.data.trackDurationSeconds ?? 0
        let startTime = nowPlaying.data.startTime
        let endTime = duration > 0
            ? startTime.addingTimeInterval(duration)
            : startTime

        let track = LiveTrack(
            id: trackID,
            fileId: trackID,
            artists: parsed.artists,
            title: parsed.title,
            image: nowPlaying.data.artworkURLs.large ?? nowPlaying.data.artworkURLs.standard,
            duration: duration,
            streamURL: streamURL,
            startTime: startTime,
            endTime: endTime,
            isSynchronizedLiveStream: false
        )

        return RadioCoSnapshot(track: track, bitrate: output.bitrate)
    }

    private func fetchStatus(stationID: String) async throws -> RadioCoStationStatus {
        let url = URL(string: "https://public.radio.co/stations/\(stationID)/status?v=1")!
        let (data, response) = try await session.data(from: url)

        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw RadioCoServiceError.invalidResponse
        }

        return try decoder.decode(RadioCoStationStatus.self, from: data)
    }

    private func fetchCurrentTrack(stationID: String) async throws -> RadioCoCurrentTrackEnvelope {
        let url = URL(string: "https://public.radio.co/api/v2/\(stationID)/track/current")!
        let (data, response) = try await session.data(from: url)

        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw RadioCoServiceError.invalidResponse
        }

        return try decoder.decode(RadioCoCurrentTrackEnvelope.self, from: data)
    }
}

private struct RadioCoStationStatus: Decodable {
    let streamingHostname: String
    let outputs: [RadioCoOutput]

    enum CodingKeys: String, CodingKey {
        case streamingHostname = "streaming_hostname"
        case outputs
    }
}

private struct RadioCoOutput: Decodable {
    let name: String
    let format: String
    let bitrate: Int?
}

private struct RadioCoCurrentTrackEnvelope: Decodable {
    let data: RadioCoCurrentTrack
}

private struct RadioCoCurrentTrack: Decodable {
    let title: String
    let startTime: Date
    let artworkURLs: RadioCoArtworkURLs
    let trackArtist: String?
    let trackTitle: String?
    let trackDurationMilliseconds: Double?
    let trackPlayoutDurationMilliseconds: Double?

    enum CodingKeys: String, CodingKey {
        case title
        case startTime = "start_time"
        case artworkURLs = "artwork_urls"
        case trackArtist = "track_artist"
        case trackTitle = "track_title"
        case trackDurationMilliseconds = "track_duration"
        case trackPlayoutDurationMilliseconds = "track_playout_duration"
    }

    var trackDurationSeconds: Double? {
        if let trackDurationMilliseconds {
            return trackDurationMilliseconds / 1000
        }
        if let trackPlayoutDurationMilliseconds {
            return trackPlayoutDurationMilliseconds / 1000
        }
        return nil
    }
}

private struct RadioCoArtworkURLs: Decodable {
    let standard: URL?
    let large: URL?
}

private struct ParsedTrackTitle {
    let artists: String
    let title: String

    init(
        rawTitle: String,
        fallbackTitle: String,
        fallbackArtists: String,
        preferredArtist: String?,
        preferredTitle: String?
    ) {
        let trimmedArtist = preferredArtist?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = preferredTitle?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let artist = trimmedArtist, !artist.isEmpty,
           let title = trimmedTitle, !title.isEmpty {
            self.artists = artist
            self.title = title
            return
        }

        let split = rawTitle.split(separator: "-", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if split.count == 2, !split[0].isEmpty, !split[1].isEmpty {
            artists = split[0]
            title = split[1]
            return
        }

        let resolvedArtists = trimmedArtist?.isEmpty == false ? trimmedArtist! : fallbackArtists
        let preferredResolvedTitle = trimmedTitle?.isEmpty == false ? trimmedTitle! : rawTitle
        let resolvedTitle = preferredResolvedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallbackTitle
            : preferredResolvedTitle

        artists = resolvedArtists
        title = resolvedTitle
    }
}

enum RadioCoServiceError: LocalizedError {
    case invalidResponse
    case invalidStationStatus

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Radio.co returned an invalid response."
        case .invalidStationStatus:
            return "Radio.co station status was missing stream output details."
        }
    }
}
