import Foundation
import Testing
@testable import lofii

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
    #expect(stream.elapsedPlaybackSeconds() == 0)
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
