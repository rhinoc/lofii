import Foundation
import Testing
@testable import lofii

@Test
func bongoRuntimeIntentKeepsAnimationAliveWhenOnlyOcclusionIsMissing() throws {
    let snapshot = WidgetVisibilitySnapshot(
        isOrderedVisible: true,
        isMiniaturized: false,
        isOcclusionVisible: false,
        isFullscreen: false,
        isFullscreenTransitioning: false
    )

    let intent = BongoRuntimeIntent(visibility: snapshot)

    #expect(snapshot.isWindowPresent)
    #expect(!snapshot.allowsFullRateVisualRendering)
    #expect(intent.renderLoop == .throttled(framesPerSecond: 12))
    #expect(intent.animation.advancesClock)
    #expect(intent.input.monitorEnabled)
}

@Test
func bongoRuntimeIntentStopsWhenWidgetIsOrderedOut() throws {
    let snapshot = WidgetVisibilitySnapshot(
        isOrderedVisible: false,
        isMiniaturized: false,
        isOcclusionVisible: false,
        isFullscreen: false,
        isFullscreenTransitioning: false
    )

    let intent = BongoRuntimeIntent(visibility: snapshot)

    #expect(!snapshot.isWindowPresent)
    #expect(intent.renderLoop == .stopped)
    #expect(!intent.animation.advancesClock)
    #expect(!intent.input.monitorEnabled)
}

@Test
func elapsedPlaybackIsClampedWithinTrackDuration() async throws {
    let now = Date()
    let track = LiveTrack(
        id: 1,
        fileId: 2,
        artists: "Test Artist",
        title: "Test Track",
        image: nil,
        duration: 120,
        streamURL: URL(string: "https://example.com/test.mp3")!,
        startTime: now.addingTimeInterval(-160),
        endTime: now
    )

    #expect(track.elapsedPlaybackSeconds(relativeTo: now) == 120)
}

@Test
func directStreamsDoNotAttemptElapsedSync() async throws {
    let stream = LiveTrack.directStream(
        id: -1,
        title: "Fluid",
        artists: "SomaFM · Instrumental hip hop",
        streamURL: URL(string: "https://ice4.somafm.com/fluid-128-aac")!
    )

    #expect(!stream.isSynchronizedLiveStream)
    #expect(!stream.hasRealMetadata)
    #expect(stream.elapsedPlaybackSeconds() == 0)
}

@Test
func directStreamCanCarryResolvedMetadata() async throws {
    let artwork = URL(string: "https://example.com/art.jpg")!
    let stream = LiveTrack.directStream(
        id: -2001,
        title: "Current Set",
        artists: "SomaFM Live Event",
        streamURL: URL(string: "https://ice5.somafm.com/live-128-mp3")!,
        image: artwork,
        metadataKind: .real
    )

    #expect(stream.hasRealMetadata)
    #expect(stream.title == "Current Set")
    #expect(stream.artists == "SomaFM Live Event")
    #expect(stream.image == artwork)
}

@Test
func icyMetadataParserExtractsStreamFields() throws {
    let parsed = StationMetadataService.parseICYMetadataBlock(
        "StreamTitle='Def Con 32 Live - Merin MC Sunday Closing Set';StreamUrl='https://somafm.com/logos/512/live512.jpg';"
    )

    #expect(parsed["StreamTitle"] == "Def Con 32 Live - Merin MC Sunday Closing Set")
    #expect(parsed["StreamUrl"] == "https://somafm.com/logos/512/live512.jpg")
}

@Test
func youtubeReadoutTextRemovesEmojiButKeepsPlainText() throws {
    let sanitized = StationMetadataService.sanitizeYouTubeReadoutText(
        "Lo-fi girl 👩‍💻 study 🎧 24/7 1️⃣"
    )

    #expect(sanitized == "Lo-fi girl study 24/7")
}

@Test
func bilibiliLiveMetadataPrefersUserCoverForArtwork() throws {
    let data = """
    {
      "code": 0,
      "data": {
        "title": "  全新中式恐怖游戏  ",
        "user_cover": "https://i0.hdslb.com/bfs/live/user_cover/cover.jpg",
        "cover": null,
        "keyframe": "https://i0.hdslb.com/bfs/live-key-frame/keyframe.jpg"
      }
    }
    """.data(using: .utf8)!

    let metadata = try #require(StationMetadataService.bilibiliLiveMetadata(from: data))
    #expect(metadata.title == "全新中式恐怖游戏")
    #expect(metadata.artists == "Bilibili")
    #expect(metadata.image == URL(string: "https://i0.hdslb.com/bfs/live/user_cover/cover.jpg"))
}

@Test
func liveTrackIndexFindsCurrentTrackFromPlaylist() async throws {
    let now = Date()
    let playlist = [
        LiveTrack(
            id: 1,
            fileId: 1,
            artists: "Artist 1",
            title: "Track 1",
            image: nil,
            duration: 120,
            streamURL: URL(string: "https://example.com/1.mp3")!,
            startTime: now.addingTimeInterval(-240),
            endTime: now.addingTimeInterval(-120)
        ),
        LiveTrack(
            id: 2,
            fileId: 2,
            artists: "Artist 2",
            title: "Track 2",
            image: nil,
            duration: 120,
            streamURL: URL(string: "https://example.com/2.mp3")!,
            startTime: now.addingTimeInterval(-120),
            endTime: now.addingTimeInterval(0)
        ),
        LiveTrack(
            id: 3,
            fileId: 3,
            artists: "Artist 3",
            title: "Track 3",
            image: nil,
            duration: 120,
            streamURL: URL(string: "https://example.com/3.mp3")!,
            startTime: now,
            endTime: now.addingTimeInterval(120)
        ),
    ]

    #expect(playlist.liveTrackIndex(relativeTo: now.addingTimeInterval(-30)) == 1)
    #expect(playlist.liveTrackIndex(relativeTo: now.addingTimeInterval(30)) == 2)
}

@Test
func liveTrackIndexFallsBackToNextUpcomingTrack() async throws {
    let now = Date()
    let playlist = [
        LiveTrack(
            id: 10,
            fileId: 10,
            artists: "Artist 10",
            title: "Track 10",
            image: nil,
            duration: 120,
            streamURL: URL(string: "https://example.com/10.mp3")!,
            startTime: now.addingTimeInterval(60),
            endTime: now.addingTimeInterval(180)
        ),
        LiveTrack(
            id: 11,
            fileId: 11,
            artists: "Artist 11",
            title: "Track 11",
            image: nil,
            duration: 120,
            streamURL: URL(string: "https://example.com/11.mp3")!,
            startTime: now.addingTimeInterval(180),
            endTime: now.addingTimeInterval(300)
        ),
    ]

    #expect(playlist.liveTrackIndex(relativeTo: now) == 0)
}

@Test
func allScenePresetsNowMapToDistinctStations() async throws {
    let stationIDs = Set(LofiiPreset.presets.map(\.radio.source.stableID))

    #expect(stationIDs.count == LofiiPreset.presets.count)
}

@Test
func presetDisplayNameUsesSceneNameByDefault() throws {
    let preset = try #require(LofiiPreset.presets.first { $0.id == "chill-vibes" })

    #expect(preset.displayName == "Chill Vibes")
}

@Test
func trackArtworkSupportIsLimitedToMetadataProviders() throws {
    #expect(RadioSource.chillhop(stationID: 12354).supportsTrackArtwork)
    #expect(RadioSource.radioCo(trackID: -3001, stationID: "sc9cb59935").supportsTrackArtwork)
    #expect(!RadioSource.bilibiliLive(roomID: 545068).supportsTrackArtwork)
    #expect(!RadioSource.directStream(trackID: -2001, url: URL(string: "https://example.com/live.aac")!).supportsTrackArtwork)
    #expect(!RadioSource.directVideo(trackID: -2002, url: URL(string: "https://example.com/live.m3u8")!).supportsTrackArtwork)
    #expect(RadioSource.twitch(channelName: "twitchdev").supportsTrackArtwork)
    #expect(!RadioSource.youtube(videoID: "1wckb-eWOxw").supportsTrackArtwork)
}

@Test
func twitchSourceProvidesLivePreviewArtworkURL() throws {
    #expect(
        RadioSource.twitch(channelName: "jinnytty").twitchPreviewImageURL?.absoluteString ==
            "https://static-cdn.jtvnw.net/previews-ttv/live_user_jinnytty-640x360.jpg"
    )
    #expect(RadioSource.youtube(videoID: "1wckb-eWOxw").twitchPreviewImageURL == nil)
}

@Test
func youtubeURLParserAcceptsCommonVideoShapes() throws {
    #expect(YouTubeURLParser.videoID(from: "https://www.youtube.com/watch?v=1wckb-eWOxw") == "1wckb-eWOxw")
    #expect(YouTubeURLParser.videoID(from: "https://youtu.be/5yx6BWlEVcY?t=10") == "5yx6BWlEVcY")
    #expect(YouTubeURLParser.videoID(from: "youtube.com/embed/lP26UCnoH9s") == "lP26UCnoH9s")
    #expect(YouTubeURLParser.videoID(from: "https://www.youtube.com/live/tNkZsRW7h2c?feature=share") == "tNkZsRW7h2c")
    #expect(YouTubeURLParser.videoID(from: "apCom1TeTiA") == "apCom1TeTiA")
}

@Test
func youtubeURLParserRejectsNonVideoShapes() throws {
    #expect(YouTubeURLParser.videoID(from: "https://www.youtube.com/playlist?list=PL123") == nil)
    #expect(YouTubeURLParser.videoID(from: "https://www.youtube.com/channel/UC1234567890") == nil)
    #expect(YouTubeURLParser.videoID(from: "https://example.com/watch?v=1wckb-eWOxw") == nil)
    #expect(YouTubeURLParser.videoID(from: "too-short") == nil)
}

@Test
func customStationSourceResolverDetectsYouTube() throws {
    #expect(CustomStationSourceResolver.resolve("https://www.youtube.com/watch?v=1wckb-eWOxw") == .youtube(videoID: "1wckb-eWOxw"))
}

@Test
func bilibiliLiveURLParserAcceptsCommonRoomShapes() throws {
    #expect(BilibiliLiveURLParser.roomID(from: "https://live.bilibili.com/545068") == 545068)
    #expect(BilibiliLiveURLParser.roomID(from: "live.bilibili.com/545068?spm_id_from=333.1007") == 545068)
    #expect(BilibiliLiveURLParser.roomID(from: "545068") == 545068)
}

@Test
func bilibiliLiveURLParserRejectsNonRoomShapes() throws {
    #expect(BilibiliLiveURLParser.roomID(from: "https://www.bilibili.com/video/BV123") == nil)
    #expect(BilibiliLiveURLParser.roomID(from: "https://live.bilibili.com/blackboard/activity") == nil)
    #expect(BilibiliLiveURLParser.roomID(from: "not-a-room") == nil)
}

@Test
func customStationSourceResolverDetectsBilibiliLive() throws {
    #expect(CustomStationSourceResolver.resolve("https://live.bilibili.com/545068") == .bilibiliLive(roomID: 545068))
}

@Test
func twitchURLParserAcceptsCommonChannelShapes() throws {
    #expect(TwitchURLParser.channelName(from: "https://www.twitch.tv/twitchdev") == "twitchdev")
    #expect(TwitchURLParser.channelName(from: "twitch.tv/TwitchDev?ref=lofii") == "twitchdev")
    #expect(TwitchURLParser.channelName(from: "https://m.twitch.tv/monstercat") == "monstercat")
    #expect(TwitchURLParser.channelName(from: "twitchdev") == "twitchdev")
}

@Test
func twitchURLParserRejectsNonChannelShapes() throws {
    #expect(TwitchURLParser.channelName(from: "https://www.twitch.tv/videos/123456") == nil)
    #expect(TwitchURLParser.channelName(from: "https://www.twitch.tv/directory/category/music") == nil)
    #expect(TwitchURLParser.channelName(from: "https://clips.twitch.tv/FineSlug") == nil)
    #expect(TwitchURLParser.channelName(from: "https://example.com/twitchdev") == nil)
    #expect(TwitchURLParser.channelName(from: "ab") == nil)
}

@Test
func customStationSourceResolverDetectsTwitch() throws {
    #expect(CustomStationSourceResolver.resolve("https://www.twitch.tv/twitchdev") == .twitch(channelName: "twitchdev"))
}

@Test
func customStationSourceResolverDetectsHLSVideo() throws {
    #expect(CustomStationSourceResolver.resolve("https://example.com/live/playlist.m3u8?token=abc") == .directVideo(url: URL(string: "https://example.com/live/playlist.m3u8?token=abc")!))
}

@Test
func customStationSourceResolverDetectsMP4Video() throws {
    #expect(CustomStationSourceResolver.resolve("https://cdn.example.com/lofi.mp4") == .directVideo(url: URL(string: "https://cdn.example.com/lofi.mp4")!))
}

@Test
func customStationSourceResolverDetectsAudioURLs() throws {
    #expect(CustomStationSourceResolver.resolve("https://cdn.example.com/live.mp3") == .directAudio(url: URL(string: "https://cdn.example.com/live.mp3")!))
    #expect(CustomStationSourceResolver.resolve("https://cdn.example.com/live.aac") == .directAudio(url: URL(string: "https://cdn.example.com/live.aac")!))
}

@Test
func customStationSourceResolverDetectsRadioStyleAudioSuffixes() throws {
    #expect(CustomStationSourceResolver.resolve("https://ice5.somafm.com/live-128-mp3") == .directAudio(url: URL(string: "https://ice5.somafm.com/live-128-mp3")!))
    #expect(CustomStationSourceResolver.resolve("https://ice5.somafm.com/live-128-aac") == .directAudio(url: URL(string: "https://ice5.somafm.com/live-128-aac")!))
    #expect(CustomStationSourceResolver.resolve("https://wrti-live.streamguys1.com/classical-mp3") == .directAudio(url: URL(string: "https://wrti-live.streamguys1.com/classical-mp3")!))
}

@Test
func customStationSourceResolverDetectsContentTypes() throws {
    let url = URL(string: "https://stream.example.com/live")!
    #expect(CustomStationSourceResolver.resolve(url: url, contentType: "audio/mpeg") == .directAudio(url: url))
    #expect(CustomStationSourceResolver.resolve(url: url, contentType: "audio/aacp; charset=utf-8") == .directAudio(url: url))
    #expect(CustomStationSourceResolver.resolve(url: url, contentType: "video/mp4") == .directVideo(url: url))
    #expect(CustomStationSourceResolver.resolve(url: url, contentType: "application/vnd.apple.mpegurl") == .directVideo(url: url))
}

@Test
func customStationSourceResolverRejectsInvalidURLs() throws {
    #expect(CustomStationSourceResolver.resolve("https://example.com/live.txt") == nil)
    #expect(CustomStationSourceResolver.resolve("example.com/live.mp3") == nil)
    #expect(CustomStationSourceResolver.resolve("not a station") == nil)
}

@Test
func customStationStoreRoundTripsVersionedJSON() throws {
    let container = try makeTemporaryBundleContainer()
    defer { try? FileManager.default.removeItem(at: container) }

    let fileURL = container.appendingPathComponent("custom-stations.json")
    let store = CustomStationStore(fileURL: fileURL)
    let station = CustomStation(
        id: UUID(uuidString: "F0E9B75B-7F84-4F4C-9FA0-2C69D0DE7B71")!,
        name: "Study Stream",
        url: "https://www.youtube.com/watch?v=1wckb-eWOxw",
        videoID: "1wckb-eWOxw",
        iconID: PixelGlyph.headphone.stableID,
        themeColorHex: StationThemeColor.cyan.hex,
        createdAt: Date(timeIntervalSince1970: 100),
        updatedAt: Date(timeIntervalSince1970: 200)
    )
    let builtInOverride = BuiltInStationOverride(
        presetID: "sea-side",
        name: "Wave Stream",
        url: "https://www.youtube.com/watch?v=5yx6BWlEVcY",
        videoID: "5yx6BWlEVcY",
        iconID: PixelGlyph.star.stableID,
        themeColorHex: StationThemeColor.violet.hex,
        updatedAt: Date(timeIntervalSince1970: 300)
    )

    try store.save(CustomStationDocument(stations: [station], builtInOverrides: [builtInOverride]))

    let document = store.loadDocument()
    #expect(document.schemaVersion == CustomStationDocument.currentSchemaVersion)
    #expect(document.stations == [station])
    #expect(document.builtInOverrides == [builtInOverride])
}

@Test
func customStationStoreRejectsNonCurrentSchemaJSON() throws {
    let container = try makeTemporaryBundleContainer()
    defer { try? FileManager.default.removeItem(at: container) }

    let fileURL = container.appendingPathComponent("custom-stations.json")
    let store = CustomStationStore(fileURL: fileURL)
    let json = """
    {
      "schemaVersion": 2,
      "stations": [
        {
          "createdAt": "1970-01-01T00:01:40Z",
          "iconID": "headphone",
          "id": "F0E9B75B-7F84-4F4C-9FA0-2C69D0DE7B71",
          "kind": "youtube",
          "name": "Study Stream",
          "updatedAt": "1970-01-01T00:03:20Z",
          "url": "https://www.youtube.com/watch?v=1wckb-eWOxw",
          "videoID": "1wckb-eWOxw"
        }
      ],
      "builtInOverrides": []
    }
    """
    try #require(json.data(using: .utf8)).write(to: fileURL)

    let document = store.loadDocument()
    #expect(document.schemaVersion == CustomStationDocument.currentSchemaVersion)
    #expect(document.stations.isEmpty)
    #expect(document.builtInOverrides.isEmpty)
}

@Test
func customYouTubePresetUsesStableCustomIdentityAndSource() throws {
    let id = UUID(uuidString: "F0E9B75B-7F84-4F4C-9FA0-2C69D0DE7B71")!
    let station = CustomStation(
        id: id,
        name: "Study Stream",
        url: "https://www.youtube.com/watch?v=1wckb-eWOxw",
        videoID: "1wckb-eWOxw",
        iconID: PixelGlyph.leaf.stableID,
        themeColorHex: StationThemeColor.mint.hex
    )

    let preset = station.lofiiPreset(defaultScene: SceneCatalog.presets[0])

    #expect(preset.id == "custom-youtube-\(id.uuidString)")
    #expect(preset.customStationID == id)
    #expect(preset.displayName == "Study Stream")
    #expect(preset.pickerGlyph == .leaf)
    #expect(preset.pickerAccent.hexRGB == StationThemeColor.mint.hex)
    #expect(preset.radio.source.stableID == "youtube:1wckb-eWOxw")
    #expect(preset.radio.source.youtubeVideoID == "1wckb-eWOxw")
}

@Test
func customBilibiliLivePresetUsesStableCustomIdentityAndSource() throws {
    let id = UUID(uuidString: "3C6E0620-05DE-4B67-8829-EC19E2D6A55A")!
    let station = CustomStation(
        id: id,
        kind: .bilibiliLive,
        name: "Bilibili Room",
        url: "https://live.bilibili.com/545068",
        videoID: "545068",
        iconID: PixelGlyph.star.stableID,
        themeColorHex: StationThemeColor.sky.hex
    )

    let preset = station.lofiiPreset(defaultScene: SceneCatalog.presets[0])

    #expect(preset.id == "custom-bilibiliLive-\(id.uuidString)")
    #expect(preset.displayName == "Bilibili Room")
    #expect(preset.radio.providerName == "Bilibili")
    #expect(preset.radio.source.stableID == "bilibili-live:545068")
    #expect(preset.radio.source.bilibiliLiveRoomID == 545068)
}

@Test
func customTwitchPresetUsesStableCustomIdentityAndSource() throws {
    let id = UUID(uuidString: "B4FB4C3A-0175-4B9D-AD09-CA56D346A0A7")!
    let station = CustomStation(
        id: id,
        kind: .twitch,
        name: "Twitch Dev",
        url: "https://www.twitch.tv/twitchdev",
        videoID: "twitchdev",
        iconID: PixelGlyph.star.stableID,
        themeColorHex: StationThemeColor.violet.hex
    )

    let preset = station.lofiiPreset(defaultScene: SceneCatalog.presets[0])

    #expect(preset.id == "custom-twitch-\(id.uuidString)")
    #expect(preset.displayName == "Twitch Dev")
    #expect(preset.radio.providerName == "Twitch")
    #expect(preset.radio.source.stableID == "twitch:twitchdev")
    #expect(preset.radio.source.twitchChannelName == "twitchdev")
}

@Test
func customDirectAudioPresetUsesDirectStreamSource() throws {
    let id = UUID(uuidString: "F0E9B75B-7F84-4F4C-9FA0-2C69D0DE7B71")!
    let url = URL(string: "https://cdn.example.com/live.mp3")!
    let station = CustomStation(
        id: id,
        kind: .directAudio,
        name: "Study Stream",
        url: url.absoluteString,
        videoID: "",
        iconID: PixelGlyph.leaf.stableID,
        themeColorHex: StationThemeColor.mint.hex
    )

    let preset = station.lofiiPreset(defaultScene: SceneCatalog.presets[0])

    #expect(preset.id == "custom-directAudio-\(id.uuidString)")
    #expect(preset.customStationID == id)
    #expect(preset.radio.providerName == "Direct Audio")
    guard case let .directStream(_, streamURL) = preset.radio.source else {
        Issue.record("Expected direct stream source")
        return
    }
    #expect(streamURL == url)
}

@Test
func savedDirectAudioStationDoesNotRequireExtensionOnReload() throws {
    let id = UUID(uuidString: "F0E9B75B-7F84-4F4C-9FA0-2C69D0DE7B71")!
    let url = URL(string: "https://ice5.somafm.com/live-128-mp3")!
    let station = CustomStation(
        id: id,
        kind: .directAudio,
        name: "SomaFM Live",
        url: url.absoluteString,
        videoID: "",
        iconID: PixelGlyph.leaf.stableID,
        themeColorHex: StationThemeColor.mint.hex
    )

    #expect(CustomStationSourceResolver.resolve(station: station) == .directAudio(url: url))
    let preset = station.lofiiPreset(defaultScene: SceneCatalog.presets[0])
    guard case let .directStream(_, streamURL) = preset.radio.source else {
        Issue.record("Expected direct stream source")
        return
    }
    #expect(streamURL == url)
}

@Test
func customDirectVideoPresetUsesDirectVideoSource() throws {
    let id = UUID(uuidString: "5E8A5649-14C0-48F0-B7CE-F5E8EC2D975D")!
    let url = URL(string: "https://cdn.example.com/live.m3u8")!
    let station = CustomStation(
        id: id,
        kind: .directVideo,
        name: "Study Stream",
        url: url.absoluteString,
        videoID: "",
        iconID: PixelGlyph.leaf.stableID,
        themeColorHex: StationThemeColor.mint.hex
    )

    let preset = station.lofiiPreset(defaultScene: SceneCatalog.presets[0])

    #expect(preset.id == "custom-directVideo-\(id.uuidString)")
    #expect(preset.customStationID == id)
    #expect(preset.radio.providerName == "Direct Video")
    #expect(preset.radio.source.directVideoURL == url)
    guard case let .directVideo(_, streamURL) = preset.radio.source else {
        Issue.record("Expected direct video source")
        return
    }
    #expect(streamURL == url)
}

@Test
func builtInStationOverrideKeepsPresetSlotAndAppliesYoutubeSource() throws {
    let original = try #require(LofiiPreset.presets.first { $0.id == "sea-side" })
    let override = BuiltInStationOverride(
        presetID: original.id,
        name: "Wave Stream",
        url: "https://www.youtube.com/watch?v=5yx6BWlEVcY",
        videoID: "5yx6BWlEVcY",
        iconID: PixelGlyph.star.stableID,
        themeColorHex: StationThemeColor.violet.hex
    )

    let preset = override.apply(to: original)

    #expect(preset.id == original.id)
    #expect(preset.customStationID == nil)
    #expect(preset.builtInOverrideID == original.id)
    #expect(preset.displayName == "Wave Stream")
    #expect(preset.pickerGlyph == .star)
    #expect(preset.pickerAccent.hexRGB == StationThemeColor.violet.hex)
    #expect(preset.radio.source.stableID == "youtube:5yx6BWlEVcY")
    #expect(preset.radio.source.youtubeVideoID == "5yx6BWlEVcY")
}

@Test
func builtInStationOverrideCanKeepOriginalIcon() throws {
    let original = try #require(LofiiPreset.presets.first { $0.id == "sea-side" })
    let override = BuiltInStationOverride(
        presetID: original.id,
        name: "Wave Stream",
        url: "https://www.youtube.com/watch?v=5yx6BWlEVcY",
        videoID: "5yx6BWlEVcY",
        iconID: original.pickerGlyph.stableID,
        themeColorHex: StationThemeColor.violet.hex
    )

    let preset = override.apply(to: original)

    #expect(preset.pickerGlyph == original.pickerGlyph)
}

@Test
@MainActor
func bongoMouseButtonReconcileClearsMissedRightMouseUp() async throws {
    var emitted: [(String, Double)] = []
    let monitor = BongoInputMonitor(
        paramCallback: { params in emitted.append(contentsOf: params) },
        keyCallback: { _, _ in },
        supportedKeyImages: []
    )

    monitor.reconcilePressedMouseButtons(1 << 1)
    monitor.reconcilePressedMouseButtons(1 << 1)
    monitor.reconcilePressedMouseButtons(0)

    #expect(emitted.count == 2)
    #expect(emitted[0].0 == "ParamMouseRightDown")
    #expect(emitted[0].1 == 1.0)
    #expect(emitted[1].0 == "ParamMouseRightDown")
    #expect(emitted[1].1 == 0.0)
}

@Test
func bongoStageOriginRatioSurvivesResizeAndClampsToVisibleRange() throws {
    let ratio = BongoStageOriginRatio(
        origin: CGPoint(x: 150, y: 100),
        container: CGSize(width: 500, height: 300),
        stage: CGSize(width: 200, height: 100)
    )

    let resized = ratio.resolvedOrigin(
        in: CGSize(width: 800, height: 500),
        stage: CGSize(width: 200, height: 100)
    )

    #expect(abs(resized.x - 300) < 0.001)
    #expect(abs(resized.y - 200) < 0.001)

    let clamped = BongoStageOriginRatio(
        origin: CGPoint(x: 999, y: -50),
        container: CGSize(width: 500, height: 300),
        stage: CGSize(width: 200, height: 100)
    )
    let resolved = clamped.resolvedOrigin(
        in: CGSize(width: 500, height: 300),
        stage: CGSize(width: 200, height: 100)
    )

    #expect(resolved.x == 300)
    #expect(resolved.y == 0)
}

@Test
func crtResolvedOverscanIsAtLeastPreset() throws {
    let preset = CurvationStrength.balanced.resolvedOverscan
    let k = CurvationStrength.balanced.resolvedCurvationFactor
    let o = CRTStageViewportShaping.resolvedOverscan(curvationFactor: k, presetOverscan: preset)
    #expect(o + 1e-9 >= preset)
}

@Test
func crtResolvedOverscanGrowsWithCurvature() throws {
    let preset = CurvationStrength.balanced.resolvedOverscan
    let subtle = CurvationStrength.subtle.resolvedCurvationFactor
    let strong = CurvationStrength.strong.resolvedCurvationFactor
    let oSubtle = CRTStageViewportShaping.resolvedOverscan(curvationFactor: subtle, presetOverscan: preset)
    let oStrong = CRTStageViewportShaping.resolvedOverscan(curvationFactor: strong, presetOverscan: preset)
    #expect(oStrong + 1e-9 >= oSubtle)
}

@Test
func shatteredGlassHighMatchesPreviousLowPreset() throws {
    #expect(ShatteredGlassStrength.strong.resolvedOpacity == 0.42)
    #expect(ShatteredGlassStrength.strong.resolvedRefraction == 10)
    #expect(ShatteredGlassStrength.strong.resolvedHighlight == 0.28)
}

@Test
func lofiiResourcesPreferMainBundleWhenReleaseResourcesAreFlattened() throws {
    let container = try makeTemporaryBundleContainer()
    defer { try? FileManager.default.removeItem(at: container) }

    let main = try makeBundle(
        named: "Main.bundle",
        in: container,
        resources: ["AppIcon.icns"]
    )

    let resolved = LofiiResources.resolveBundle(main: main)

    #expect(resolved.bundleURL.standardizedFileURL == main.bundleURL.standardizedFileURL)
}

@Test
func lofiiResourcesFindSwiftPMBundleWithoutCallingBundleModule() throws {
    let container = try makeTemporaryBundleContainer()
    defer { try? FileManager.default.removeItem(at: container) }

    let main = try makeBundle(named: "Main.bundle", in: container)
    let swiftPM = try makeBundle(
        named: "lofii_lofii.bundle",
        in: container,
        resources: ["AppIcon.icns"]
    )

    let resolved = LofiiResources.resolveBundle(main: main)

    #expect(resolved.bundleURL.standardizedFileURL == swiftPM.bundleURL.standardizedFileURL)
}

@Test
func userVisualMediaLibraryScansSupportedFlatFilesOnly() throws {
    let container = try makeTemporaryBundleContainer()
    defer { try? FileManager.default.removeItem(at: container) }

    try Data().write(to: container.appendingPathComponent("z-loop.mp4"))
    try Data().write(to: container.appendingPathComponent("a-scene.mov"))
    try Data().write(to: container.appendingPathComponent("notes.txt"))
    try Data().write(to: container.appendingPathComponent(".hidden.mp4"))
    try FileManager.default.createDirectory(
        at: container.appendingPathComponent("folder.gif", isDirectory: true),
        withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
        at: container.appendingPathComponent("linked.mp4"),
        withDestinationURL: container.appendingPathComponent("z-loop.mp4")
    )

    let media = UserVisualMediaLibrary.listImportedMedia(in: container)

    #expect(media.map(\.displayName) == ["a-scene", "z-loop"])
    #expect(media.map(\.kind) == [.userVideo, .userVideo])
}

@Test
func stationEditorPaletteMatchesIconChoices() {
    #expect(StationThemeColor.allCases.count == PixelGlyph.customStationIconChoices.count)
    #expect(Set(StationThemeColor.allCases.map(\.hex)).count == StationThemeColor.allCases.count)
}

private func makeTemporaryBundleContainer() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("lofii-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeBundle(
    named name: String,
    in container: URL,
    resources: [String] = []
) throws -> Bundle {
    let root = container.appendingPathComponent(name, isDirectory: true)
    let resourcesRoot = root.appendingPathComponent("Contents/Resources", isDirectory: true)
    try FileManager.default.createDirectory(at: resourcesRoot, withIntermediateDirectories: true)

    for resource in resources {
        let url = resourcesRoot.appendingPathComponent(resource)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("test".utf8).write(to: url)
    }

    return try #require(Bundle(url: root))
}
