import Foundation

struct StationMetadataSnapshot: Equatable, Sendable {
    var title: String
    var artists: String
    var image: URL?

    func liveTrack(
        id: Int,
        streamURL: URL
    ) -> LiveTrack {
        LiveTrack.directStream(
            id: id,
            title: title,
            artists: artists,
            streamURL: streamURL,
            image: image,
            metadataKind: .real
        )
    }
}

enum StationMetadataService {
    private struct YouTubeOEmbedResponse: Decodable {
        let title: String
        let authorName: String
        let thumbnailURL: URL?

        private enum CodingKeys: String, CodingKey {
            case title
            case authorName = "author_name"
            case thumbnailURL = "thumbnail_url"
        }
    }

    static func fetchYouTube(videoID: String) async -> StationMetadataSnapshot? {
        guard var components = URLComponents(string: "https://www.youtube.com/oembed") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(videoID)"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue("Lofii/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode)
            else { return nil }
            let decoded = try JSONDecoder().decode(YouTubeOEmbedResponse.self, from: data)
            return StationMetadataSnapshot(
                title: decoded.title,
                artists: decoded.authorName,
                image: decoded.thumbnailURL
            )
        } catch {
            return nil
        }
    }

    static func fetchICY(url: URL) async -> StationMetadataSnapshot? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Lofii/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("1", forHTTPHeaderField: "Icy-MetaData")

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<400).contains(http.statusCode)
            else { return nil }

            let headers = ICYHeaders(response: http)
            guard let metaint = headers.metadataInterval, metaint > 0 else {
                return headers.stationSnapshot()
            }

            var audioBytesRemaining = metaint
            var metadataLength: Int?
            var metadataBytes: [UInt8] = []

            for try await byte in bytes {
                if audioBytesRemaining > 0 {
                    audioBytesRemaining -= 1
                    continue
                }

                if metadataLength == nil {
                    metadataLength = Int(byte) * 16
                    if metadataLength == 0 {
                        return headers.stationSnapshot()
                    }
                    continue
                }

                metadataBytes.append(byte)
                if metadataBytes.count >= metadataLength! {
                    let block = String(decoding: metadataBytes, as: UTF8.self)
                        .trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines))
                    return metadataSnapshot(from: block, headers: headers) ?? headers.stationSnapshot()
                }
            }

            return headers.stationSnapshot()
        } catch {
            return nil
        }
    }

    static func parseICYMetadataBlock(_ block: String) -> [String: String] {
        var result: [String: String] = [:]
        let fields = block.split(separator: ";")
        for field in fields {
            guard let separator = field.firstIndex(of: "=") else { continue }
            let key = field[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            var value = field[field.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            }
            if !key.isEmpty, !value.isEmpty {
                result[key] = value
            }
        }
        return result
    }

    private static func metadataSnapshot(from block: String, headers: ICYHeaders) -> StationMetadataSnapshot? {
        let fields = parseICYMetadataBlock(block)
        guard let title = fields["StreamTitle"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else { return nil }
        return StationMetadataSnapshot(
            title: title,
            artists: headers.subtitle,
            image: fields["StreamUrl"].flatMap(URL.init(string:))
        )
    }
}

private struct ICYHeaders {
    let name: String?
    let genre: String?
    let bitrate: String?
    let description: String?
    let metadataInterval: Int?

    init(response: HTTPURLResponse) {
        name = Self.header("icy-name", in: response)
        genre = Self.header("icy-genre", in: response)
        bitrate = Self.header("icy-br", in: response)
        description = Self.header("icy-description", in: response)
        metadataInterval = Self.header("icy-metaint", in: response).flatMap(Int.init)
    }

    var subtitle: String {
        let parts = [genre, bitrate.map { "\($0) kbps" }]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
        return parts.isEmpty ? (description ?? "Live stream") : parts.joined(separator: " · ")
    }

    func stationSnapshot() -> StationMetadataSnapshot? {
        guard let title = name ?? description, !title.isEmpty else { return nil }
        return StationMetadataSnapshot(
            title: title,
            artists: subtitle,
            image: nil
        )
    }

    private static func header(_ name: String, in response: HTTPURLResponse) -> String? {
        response.value(forHTTPHeaderField: name)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
