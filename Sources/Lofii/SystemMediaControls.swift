import AppKit
import AVFoundation
import Foundation
import MediaPlayer

final class SystemMediaControls: @unchecked Sendable {
    private var commandTargets: [Any] = []
    private var artworkCache: [URL: MPMediaItemArtwork] = [:]
    private var sceneArtworkCache: [String: MPMediaItemArtwork] = [:]
    private var artworkTask: Task<Void, Never>?
    private var sceneArtworkTask: Task<Void, Never>?
    private var currentArtworkURL: URL?
    private var currentSceneArtworkKey: String?
    private lazy var fallbackArtwork = Self.loadFallbackArtwork()
    private var playAction: (@MainActor () -> Void)?
    private var pauseAction: (@MainActor () -> Void)?
    private var togglePlayPauseAction: (@MainActor () -> Void)?
    private var nextTrackAction: (@MainActor () -> Void)?
    private var previousTrackAction: (@MainActor () -> Void)?

    deinit {
        artworkTask?.cancel()
        sceneArtworkTask?.cancel()
        clearCommandTargets()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    func install(
        play: @escaping @MainActor () -> Void,
        pause: @escaping @MainActor () -> Void,
        togglePlayPause: @escaping @MainActor () -> Void,
        nextTrack: @escaping @MainActor () -> Void,
        previousTrack: @escaping @MainActor () -> Void
    ) {
        playAction = play
        pauseAction = pause
        togglePlayPauseAction = togglePlayPause
        nextTrackAction = nextTrack
        previousTrackAction = previousTrack

        clearCommandTargets()

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true

        commandTargets = [
            commandCenter.playCommand.addTarget { [weak self] _ in
                self?.perform(self?.playAction) ?? .commandFailed
            },
            commandCenter.pauseCommand.addTarget { [weak self] _ in
                self?.perform(self?.pauseAction) ?? .commandFailed
            },
            commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
                self?.perform(self?.togglePlayPauseAction) ?? .commandFailed
            },
            commandCenter.nextTrackCommand.addTarget { [weak self] _ in
                self?.perform(self?.nextTrackAction) ?? .commandFailed
            },
            commandCenter.previousTrackCommand.addTarget { [weak self] _ in
                self?.perform(self?.previousTrackAction) ?? .commandFailed
            },
        ]
    }

    func update(
        station: RadioStation,
        scene: SceneAsset,
        variant: SceneVariant,
        track: LiveTrack?,
        isPlaying: Bool
    ) {
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyAlbumTitle: station.displayName,
            MPMediaItemPropertyTitle: track?.title ?? station.displayName,
            MPMediaItemPropertyArtist: track?.artists ?? station.providerName,
            MPMediaItemPropertyArtwork: artwork(
                for: track?.image,
                scene: scene,
                variant: variant
            ),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]

        if let track, track.duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = track.duration
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = track.elapsedPlaybackSeconds()
        } else {
            nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = true
        }

        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nowPlayingInfo
        center.playbackState = isPlaying ? .playing : .paused

        loadSceneArtworkIfNeeded(for: scene, variant: variant)
        loadArtworkIfNeeded(from: track?.image)
    }

    private func perform(_ action: (@MainActor () -> Void)?) -> MPRemoteCommandHandlerStatus {
        guard let action else { return .commandFailed }
        Task { @MainActor in
            action()
        }
        return .success
    }

    private func clearCommandTargets() {
        let commandCenter = MPRemoteCommandCenter.shared()
        for target in commandTargets {
            commandCenter.playCommand.removeTarget(target)
            commandCenter.pauseCommand.removeTarget(target)
            commandCenter.togglePlayPauseCommand.removeTarget(target)
            commandCenter.nextTrackCommand.removeTarget(target)
            commandCenter.previousTrackCommand.removeTarget(target)
        }
        commandTargets.removeAll()
    }

    private func artwork(
        for url: URL?,
        scene: SceneAsset,
        variant: SceneVariant
    ) -> MPMediaItemArtwork {
        let sceneFallback = sceneArtworkCache[sceneArtworkKey(scene: scene, variant: variant)] ?? fallbackArtwork
        guard let url else { return sceneFallback }
        return artworkCache[url] ?? sceneFallback
    }

    private func loadArtworkIfNeeded(from url: URL?) {
        guard let url else {
            currentArtworkURL = nil
            artworkTask?.cancel()
            artworkTask = nil
            return
        }
        guard artworkCache[url] == nil else {
            currentArtworkURL = url
            return
        }
        guard currentArtworkURL != url else { return }

        currentArtworkURL = url
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled,
                      let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode),
                      let image = NSImage(data: data)
                else { return }

                let artwork = Self.makeArtwork(from: image)
                await MainActor.run { [weak self] in
                    guard let self, self.currentArtworkURL == url else { return }
                    self.artworkCache[url] = artwork
                    var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                }
            } catch {
                return
            }
        }
    }

    private func loadSceneArtworkIfNeeded(for scene: SceneAsset, variant: SceneVariant) {
        let key = sceneArtworkKey(scene: scene, variant: variant)
        guard sceneArtworkCache[key] == nil else {
            currentSceneArtworkKey = key
            return
        }
        guard currentSceneArtworkKey != key else { return }

        currentSceneArtworkKey = key
        sceneArtworkTask?.cancel()
        sceneArtworkTask = Task { [weak self] in
            guard let self else { return }
            do {
                let videoURL = try await SceneVideoCache.shared.ensureLocalVideo(for: scene, variant: variant)
                guard !Task.isCancelled,
                      let image = try await Self.firstVideoFrameImage(from: videoURL)
                else { return }

                let artwork = Self.makeArtwork(from: image)
                await MainActor.run { [weak self] in
                    guard let self, self.currentSceneArtworkKey == key else { return }
                    self.sceneArtworkCache[key] = artwork

                    var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    if nowPlayingInfo[MPMediaItemPropertyArtwork] == nil ||
                       nowPlayingInfo[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork === self.fallbackArtwork {
                        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                    }
                }
            } catch {
                return
            }
        }
    }

    private func sceneArtworkKey(scene: SceneAsset, variant: SceneVariant) -> String {
        "\(scene.id)/\(variant.rawValue)"
    }

    private static func loadFallbackArtwork() -> MPMediaItemArtwork {
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return makeArtwork(from: image)
        }
        return makeArtwork(from: NSImage(size: NSSize(width: 512, height: 512)))
    }

    private static func makeArtwork(from image: NSImage) -> MPMediaItemArtwork {
        let squareImage = squareCroppedImage(from: image)
        return MPMediaItemArtwork(boundsSize: squareImage.size) { _ in squareImage }
    }

    private static func squareCroppedImage(from image: NSImage) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        let side = min(cgImage.width, cgImage.height)
        guard side > 0 else { return image }

        let cropRect = CGRect(
            x: (cgImage.width - side) / 2,
            y: (cgImage.height - side) / 2,
            width: side,
            height: side
        )
        guard let cropped = cgImage.cropping(to: cropRect) else {
            return image
        }

        return NSImage(cgImage: cropped, size: NSSize(width: side, height: side))
    }

    private static func firstVideoFrameImage(from url: URL) async throws -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1024, height: 1024)
        let result = try await generator.image(at: CMTime(seconds: 0, preferredTimescale: 600))
        let cgImage = result.image
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
