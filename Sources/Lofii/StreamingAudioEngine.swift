import AVFoundation
import CoreMedia
import Foundation
import OSLog
import QuartzCore

@MainActor
final class StreamingAudioEngine {
    private enum Deck {
        case a
        case b

        var other: Deck {
            switch self {
            case .a: return .b
            case .b: return .a
            }
        }
    }

    private let playerA = AVPlayer()
    private let playerB = AVPlayer()
    private var activeDeck: Deck = .a
    private var currentTrackURL: URL?
    private var preparedTrackURL: URL?
    private var statusObservations: [NSKeyValueObservation] = []
    private var activeItemObservations: [NSKeyValueObservation] = []
    private var activeItemNotificationTokens: [NSObjectProtocol] = []
    private var retryGeneration = 0
    private var fadeTimer: Timer?
    private var isCrossfading = false
    private var volume: Float = 1.0
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "lofii",
        category: "audio.engine"
    )

    /// Called whenever `AVPlayer.timeControlStatus` flips. The engine itself
    /// stays purely "what should be happening" — the consumer (`AppModel`)
    /// owns the @Published mirror that drives SwiftUI.
    var onPlaybackStateChange: ((PlaybackState) -> Void)?
    var onPlaybackStallDetected: ((String) -> Void)?

    enum PlaybackState: Equatable {
        case stopped
        case buffering
        case playing
    }

    struct PlaybackSample: Equatable {
        let itemID: ObjectIdentifier?
        let currentTime: TimeInterval?
        let rate: Float
        let timeControlStatus: String
        let isWaiting: Bool
        let isPlaying: Bool
        let isBufferEmpty: Bool
        let isBufferFull: Bool
        let isLikelyToKeepUp: Bool
        let itemStatus: String
        let itemFailed: Bool
        let errorDescription: String?
        let playerErrorDescription: String?
        let currentURL: String?
        let loadedTimeRanges: String

        var hasItem: Bool { itemID != nil }
    }

    init() {
        for player in [playerA, playerB] {
            player.automaticallyWaitsToMinimizeStalling = true
            player.volume = 0
        }

        // KVO on `timeControlStatus` is the canonical way to learn that an
        // AVPlayer is stalled / waiting on the network — `.waitingToPlay…`
        // covers both initial buffering and mid-stream rebuffering.
        //
        // The KVO callback fires on a nonisolated context. Under Swift 6
        // strict concurrency, `[weak self]` capture of a `@MainActor`
        // class crosses isolation domains; doing the `guard let self`
        // inside the nonisolated closure trips the runtime executor
        // check (we'd see a SIGSEGV inside `swift_task_isCurrent…` on
        // the very first KVO fire after init). Hop to main first via
        // `DispatchQueue.main.async`, THEN dereference self — this
        // keeps the weak capture out of the strict-concurrency path
        // entirely.
        statusObservations = [playerA, playerB].map { player in
            player.observe(\.timeControlStatus, options: [.new, .initial]) { [weak self] _, _ in
                DispatchQueue.main.async { [weak self] in
                    self?.emitPlaybackState()
                }
            }
        }
    }

    func play(
        track: LiveTrack,
        elapsed: TimeInterval,
        replacingCurrentItem: Bool,
        shouldSeekToElapsed: Bool,
        reason: String
    ) {
        cancelFade()

        let player = activePlayer
        if replacingCurrentItem || currentTrackURL != track.streamURL {
            logger.info(
                "Replace current item reason=\(reason, privacy: .public) title=\(track.title, privacy: .public) url=\(track.streamURL.absoluteString, privacy: .public)"
            )
            DiagnosticLog.appendPlayback(
                "engine.replace reason=\(reason) title=\"\(track.title)\" url=\(track.streamURL.absoluteString)"
            )
            let item = makePlayerItem(url: track.streamURL)
            player.replaceCurrentItem(with: item)
            currentTrackURL = track.streamURL
            observeActiveItem(item)
        }

        if shouldSeekToElapsed {
            syncPositionIfNeeded(on: player, elapsed, replacingCurrentItem: replacingCurrentItem)
        }
        inactivePlayer.pause()
        inactivePlayer.volume = 0
        player.volume = volume
        logger.info(
            "Play active deck reason=\(reason, privacy: .public) title=\(track.title, privacy: .public) replacing=\(replacingCurrentItem) seekToElapsed=\(shouldSeekToElapsed) elapsed=\(elapsed, format: .fixed(precision: 2))"
        )
        DiagnosticLog.appendPlayback(
            "engine.play reason=\(reason) title=\"\(track.title)\" replacing=\(replacingCurrentItem) seekToElapsed=\(shouldSeekToElapsed) elapsed=\(Self.formatSeconds(elapsed)) volume=\(volume)"
        )
        retryGeneration &+= 1
        player.play()
        emitPlaybackState()
    }

    func stop(reason: String) {
        logger.info(
            "Stop playback reason=\(reason, privacy: .public) currentURL=\(self.currentTrackURL?.absoluteString ?? "nil", privacy: .public)"
        )
        DiagnosticLog.appendPlayback(
            "engine.stop reason=\(reason) currentURL=\(currentTrackURL?.absoluteString ?? "nil")"
        )
        retryGeneration &+= 1
        activePlayer.pause()
        inactivePlayer.pause()
        emitPlaybackState()
    }

    /// Re-assert playback on the currently active item without swapping the
    /// URL. This mirrors the user's manual "pause then play" recovery path,
    /// which is often enough to kick a stalled HTTP stream back into life.
    @discardableResult
    func retryCurrentItem(reason: String) -> Bool {
        guard activePlayer.currentItem != nil else {
            logger.info(
                "Retry skipped reason=\(reason, privacy: .public) because no current item exists"
            )
            return false
        }

        cancelFade()
        inactivePlayer.volume = 0
        activePlayer.volume = volume
        let item = activePlayer.currentItem
        retryGeneration &+= 1
        let generation = retryGeneration
        logger.info(
            "Retry current item reason=\(reason, privacy: .public) currentURL=\(self.currentTrackURL?.absoluteString ?? "nil", privacy: .public)"
        )
        activePlayer.pause()
        emitPlaybackState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self, weak item] in
            Task { @MainActor [weak self, weak item] in
                guard let self,
                      self.retryGeneration == generation,
                      let item,
                      self.activePlayer.currentItem === item
                else { return }
                self.activePlayer.volume = self.volume
                self.activePlayer.play()
                self.emitPlaybackState()
            }
        }
        return true
    }

    func setVolume(_ value: Double) {
        volume = Float(value)
        if fadeTimer == nil {
            activePlayer.volume = volume
            inactivePlayer.volume = 0
        }
    }

    func prepareNext(track: LiveTrack, reason: String) {
        guard !isCrossfading else {
            logger.info(
                "Prepare next deferred reason=\(reason, privacy: .public) title=\(track.title, privacy: .public) because crossfade is active"
            )
            DiagnosticLog.appendPlayback(
                "engine.prepareNextDeferred reason=\(reason) title=\"\(track.title)\""
            )
            return
        }
        guard preparedTrackURL != track.streamURL else {
            logger.debug(
                "Prepare next skipped reason=\(reason, privacy: .public) title=\(track.title, privacy: .public) because URL already prepared"
            )
            return
        }

        let player = inactivePlayer
        player.pause()
        let item = makePlayerItem(url: track.streamURL)
        item.preferredForwardBufferDuration = 12
        player.replaceCurrentItem(with: item)
        player.volume = 0
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        preparedTrackURL = track.streamURL
        logger.info(
            "Prepared next track reason=\(reason, privacy: .public) title=\(track.title, privacy: .public) url=\(track.streamURL.absoluteString, privacy: .public)"
        )

        // Intentionally NOT calling `player.preroll(atRate: 1.0) { … }` here.
        //
        // Under Swift 6 strict concurrency the trailing completion closure is
        // inferred `@MainActor` (because `prepareNext` is `@MainActor`), but
        // AVFoundation invokes it from a non-main, non-Task dispatch queue.
        // That tripped a metadata fault deep inside SwiftUI's
        // `ObservationCenter` accessor (see
        // `Lofii-2026-04-26-1639*.ips`), crashing the app at launch as
        // soon as the chillhop bootstrap path called into here.
        //
        // `replaceCurrentItem(_:)` already starts buffering on its own, and
        // `automaticallyWaitsToMinimizeStalling = true` makes the eventual
        // `play()` wait for enough buffer anyway, so we get the same UX
        // without the explicit preroll.
    }

    func prepareLiveBackup(track: LiveTrack, reason: String) {
        guard preparedTrackURL != track.streamURL || inactivePlayer.currentItem == nil else {
            logger.debug(
                "Live backup skipped reason=\(reason, privacy: .public) title=\(track.title, privacy: .public) because URL already prepared"
            )
            return
        }

        let player = inactivePlayer
        player.pause()
        let item = makePlayerItem(url: track.streamURL)
        item.preferredForwardBufferDuration = 18
        player.replaceCurrentItem(with: item)
        player.volume = 0
        preparedTrackURL = track.streamURL
        logger.info(
            "Prepared live backup reason=\(reason, privacy: .public) title=\(track.title, privacy: .public) url=\(track.streamURL.absoluteString, privacy: .public)"
        )
        player.play()
    }

    func clearPreparedTrack(reason: String) {
        logger.info(
            "Clear prepared track reason=\(reason, privacy: .public) preparedURL=\(self.preparedTrackURL?.absoluteString ?? "nil", privacy: .public)"
        )
        inactivePlayer.pause()
        inactivePlayer.replaceCurrentItem(with: nil)
        inactivePlayer.volume = 0
        preparedTrackURL = nil
        emitPlaybackState()
    }

    @discardableResult
    func crossfadeToPreparedTrack(
        duration: TimeInterval,
        reason: String,
        onCompletion: (@MainActor @Sendable () -> Void)? = nil
    ) -> Bool {
        guard let incomingURL = preparedTrackURL, inactivePlayer.currentItem != nil else {
            logger.info(
                "Crossfade skipped reason=\(reason, privacy: .public) because prepared track is missing"
            )
            return false
        }

        cancelFade()
        isCrossfading = true

        let outgoingDeck = activeDeck
        let incomingDeck = activeDeck.other
        let outgoingPlayer = player(for: outgoingDeck)
        let incomingPlayer = player(for: incomingDeck)

        incomingPlayer.volume = 0
        logger.info(
            "Begin crossfade reason=\(reason, privacy: .public) duration=\(duration, format: .fixed(precision: 2)) fromDeck=\(String(describing: outgoingDeck), privacy: .public) toDeck=\(String(describing: incomingDeck), privacy: .public)"
        )
        incomingPlayer.play()

        guard duration > 0 else {
            outgoingPlayer.pause()
            outgoingPlayer.replaceCurrentItem(with: nil)
            outgoingPlayer.volume = 0
            activeDeck = incomingDeck
            currentTrackURL = incomingURL
            preparedTrackURL = nil
            activePlayer.volume = volume
            retryGeneration &+= 1
            observeActiveItem(activePlayer.currentItem)
            isCrossfading = false
            logger.info(
                "Crossfade completed immediately reason=\(reason, privacy: .public) currentURL=\(self.currentTrackURL?.absoluteString ?? "nil", privacy: .public)"
            )
            emitPlaybackState()
            onCompletion?()
            return true
        }

        let startedAt = CACurrentMediaTime()
        let targetVolume = volume
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            let progress = min((CACurrentMediaTime() - startedAt) / duration, 1)
            outgoingPlayer.volume = targetVolume * Float(1 - progress)
            incomingPlayer.volume = targetVolume * Float(progress)

            guard progress >= 1 else { return }

            timer.invalidate()
            Task { @MainActor in
                self.fadeTimer = nil
                outgoingPlayer.pause()
                outgoingPlayer.replaceCurrentItem(with: nil)
                outgoingPlayer.volume = 0
                self.activeDeck = incomingDeck
                self.currentTrackURL = incomingURL
                self.preparedTrackURL = nil
                self.activePlayer.volume = self.volume
                self.retryGeneration &+= 1
                self.observeActiveItem(self.activePlayer.currentItem)
                self.isCrossfading = false
                self.logger.info(
                    "Crossfade completed reason=\(reason, privacy: .public) currentURL=\(self.currentTrackURL?.absoluteString ?? "nil", privacy: .public)"
                )
                self.emitPlaybackState()
                onCompletion?()
            }
        }
        emitPlaybackState()
        return true
    }

    @discardableResult
    func promotePreparedLiveBackup(reason: String) -> Bool {
        guard preparedTrackURL != nil,
              let item = inactivePlayer.currentItem,
              item.status == .readyToPlay || inactivePlayer.timeControlStatus == .playing
        else {
            logger.info(
                "Live backup promote skipped reason=\(reason, privacy: .public) preparedURL=\(self.preparedTrackURL?.absoluteString ?? "nil", privacy: .public)"
            )
            return false
        }

        cancelFade()
        let outgoingPlayer = activePlayer
        let incomingDeck = activeDeck.other
        let incomingPlayer = inactivePlayer
        outgoingPlayer.pause()
        outgoingPlayer.replaceCurrentItem(with: nil)
        outgoingPlayer.volume = 0
        activeDeck = incomingDeck
        currentTrackURL = preparedTrackURL
        preparedTrackURL = nil
        activePlayer.volume = volume
        retryGeneration &+= 1
        observeActiveItem(activePlayer.currentItem)
        logger.info(
            "Promoted live backup reason=\(reason, privacy: .public) currentURL=\(self.currentTrackURL?.absoluteString ?? "nil", privacy: .public)"
        )
        incomingPlayer.play()
        emitPlaybackState()
        return true
    }

    func playbackSample() -> PlaybackSample {
        let player = activePlayer
        let item = player.currentItem
        let seconds = player.currentTime().seconds
        let currentTime = seconds.isFinite ? seconds : nil
        return PlaybackSample(
            itemID: item.map { ObjectIdentifier($0) },
            currentTime: currentTime,
            rate: player.rate,
            timeControlStatus: Self.describe(player.timeControlStatus),
            isWaiting: player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
            isPlaying: player.timeControlStatus == .playing || player.rate > 0,
            isBufferEmpty: item?.isPlaybackBufferEmpty ?? false,
            isBufferFull: item?.isPlaybackBufferFull ?? false,
            isLikelyToKeepUp: item?.isPlaybackLikelyToKeepUp ?? false,
            itemStatus: item.map { Self.describe($0.status) } ?? "nil",
            itemFailed: item?.status == .failed,
            errorDescription: item?.error?.localizedDescription,
            playerErrorDescription: player.error?.localizedDescription,
            currentURL: currentTrackURL?.absoluteString,
            loadedTimeRanges: Self.describeLoadedTimeRanges(item?.loadedTimeRanges)
        )
    }

    private var activePlayer: AVPlayer {
        player(for: activeDeck)
    }

    private var inactivePlayer: AVPlayer {
        player(for: activeDeck.other)
    }

    private func player(for deck: Deck) -> AVPlayer {
        switch deck {
        case .a: return playerA
        case .b: return playerB
        }
    }

    private func makePlayerItem(url: URL) -> AVPlayerItem {
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 12
        return item
    }

    private func observeActiveItem(_ item: AVPlayerItem?) {
        activeItemObservations.removeAll()
        activeItemNotificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        activeItemNotificationTokens.removeAll()

        guard let item else { return }

        activeItemObservations = [
            item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
                DispatchQueue.main.async { [weak self, weak observedItem] in
                    guard let observedItem else { return }
                    self?.handleActiveItemSignal(item: observedItem, reason: "item status changed")
                }
            },
            item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] observedItem, _ in
                DispatchQueue.main.async { [weak self, weak observedItem] in
                    guard let observedItem else { return }
                    self?.handleActiveItemSignal(item: observedItem, reason: "buffer empty changed")
                }
            },
            item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] observedItem, _ in
                DispatchQueue.main.async { [weak self, weak observedItem] in
                    guard let observedItem else { return }
                    self?.handleActiveItemSignal(item: observedItem, reason: "likely to keep up changed")
                }
            },
        ]

        let stalled = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleActiveItemSignal(item: item, reason: "playback stalled notification")
            }
        }
        let failed = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleActiveItemSignal(item: item, reason: "failed to play to end notification")
            }
        }
        activeItemNotificationTokens = [stalled, failed]
    }

    private func handleActiveItemSignal(item: AVPlayerItem, reason: String) {
        guard activePlayer.currentItem === item else { return }

        if item.status == .failed {
            let error = item.error?.localizedDescription ?? "nil"
            logger.error(
                "Active item failed reason=\(reason, privacy: .public) error=\(error, privacy: .public)"
            )
            DiagnosticLog.appendPlayback(
                "engine.itemFailed reason=\"\(reason)\" error=\"\(error)\" url=\(currentTrackURL?.absoluteString ?? "nil")"
            )
            onPlaybackStallDetected?("item failed: \(error)")
            emitPlaybackState()
            return
        }

        if item.isPlaybackBufferEmpty {
            logger.info("Active item buffer empty reason=\(reason, privacy: .public)")
            DiagnosticLog.appendPlayback(
                "engine.bufferEmpty reason=\"\(reason)\" likely=\(item.isPlaybackLikelyToKeepUp) url=\(currentTrackURL?.absoluteString ?? "nil")"
            )
            onPlaybackStallDetected?("buffer empty")
            emitPlaybackState()
            return
        }

        emitPlaybackState()
    }

    private func cancelFade() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        isCrossfading = false
    }

    private func emitPlaybackState() {
        let players = fadeTimer == nil ? [activePlayer] : [playerA, playerB]
        let state: PlaybackState
        if players.contains(where: { $0.timeControlStatus == .waitingToPlayAtSpecifiedRate }) {
            state = .buffering
        } else if players.contains(where: { $0.timeControlStatus == .playing }) {
            state = .playing
        } else if fadeTimer == nil,
                  activePlayer.currentItem != nil,
                  activePlayer.timeControlStatus == .paused {
            // A loaded item with `.paused` is neither `.playing` nor
            // `.waitingToPlayAtSpecifiedRate`, so it used to fall through to
            // `.stopped` — which made `AppModel` clear `isBuffering` and the
            // waveform animate as if audio were flowing while the user heard
            // silence (common after HTTP stream underrun / transport failure).
            // Treat as buffering; user-initiated pause goes through `stop()`
            // and `AppModel.isBuffering = isPlaying` stays false while paused.
            state = .buffering
        } else {
            state = .stopped
        }
        logger.debug("Emit playback state state=\(String(describing: state), privacy: .public)")
        onPlaybackStateChange?(state)
    }

    private static func describe(_ status: AVPlayer.TimeControlStatus) -> String {
        switch status {
        case .paused: return "paused"
        case .waitingToPlayAtSpecifiedRate: return "waitingToPlayAtSpecifiedRate"
        case .playing: return "playing"
        @unknown default: return "unknown"
        }
    }

    private static func describe(_ status: AVPlayerItem.Status) -> String {
        switch status {
        case .unknown: return "unknown"
        case .readyToPlay: return "readyToPlay"
        case .failed: return "failed"
        @unknown default: return "unknown"
        }
    }

    private static func describeLoadedTimeRanges(_ ranges: [NSValue]?) -> String {
        guard let ranges, !ranges.isEmpty else { return "[]" }
        return ranges.map { value in
            let range = value.timeRangeValue
            let start = range.start.seconds
            let duration = range.duration.seconds
            return "[\(formatSeconds(start))+\(formatSeconds(duration))]"
        }.joined(separator: ",")
    }

    private static func formatSeconds(_ value: TimeInterval) -> String {
        guard value.isFinite else { return "nan" }
        return String(format: "%.2f", value)
    }

    private func syncPositionIfNeeded(on player: AVPlayer, _ elapsed: TimeInterval, replacingCurrentItem: Bool) {
        let target = CMTime(seconds: elapsed, preferredTimescale: 600)

        if replacingCurrentItem {
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            return
        }

        let drift = abs(player.currentTime().seconds - elapsed)
        guard drift > 2 else {
            return
        }

        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
