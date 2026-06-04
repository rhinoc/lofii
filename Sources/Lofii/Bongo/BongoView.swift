import AppKit
@preconcurrency import AVFoundation
import CoreGraphics
import CoreVideo
import SwiftUI
import MetalKit
import CubismNativeBridge

private extension StageMetalSource {
    var mediaURL: URL {
        switch self {
        case .video(let url), .gif(let url), .image(let url):
            return url
        }
    }
}

// MARK: - BongoView

/// Top-level Bongo stage. Bongo mode owns the animated background (media or
/// scene video) and Live2D layer so source-sampling effects can run once over
/// the combined image.
struct BongoView: View {
    @EnvironmentObject private var model: AppModel
    let isPlaying: Bool
    let rendersVisualBackground: Bool
    let appliesCRT: Bool
    /// Forward scroll-wheel volume when the wheel catcher passes hits through the Live2D stage.
    var artworkScrollWheel: ((Double) -> Void)? = nil
    /// Right-click menu on the Metal stage (same as the wheel overlay) when hits pass through.
    var artworkContextMenu: (() -> NSMenu)? = nil

    var body: some View {
        BongoUnifiedStage(
            isPlaying: isPlaying,
            rendersVisualBackground: rendersVisualBackground,
            appliesCRT: appliesCRT,
            pack: model.bongoCatPack,
            inputTickRate: model.bongoInputTickRate,
            mouseCursorSpace: model.bongoMouseCursorSpace,
            artworkScrollWheel: artworkScrollWheel,
            artworkContextMenu: artworkContextMenu
        )
            .id("\(model.bongoCatPack.cacheTag)-\(model.bongoPackReloadToken)")
    }
}

private struct BongoUnifiedStage: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var agentCompanion: AgentCompanionModel
    @StateObject private var coordinator: BongoCoordinator
    let isPlaying: Bool
    let rendersVisualBackground: Bool
    let appliesCRT: Bool
    let pack: BongoCatPack
    let inputTickRate: BongoInputTickRate
    let mouseCursorSpace: BongoMouseCursorSpace
    let artworkScrollWheel: ((Double) -> Void)?
    let artworkContextMenu: (() -> NSMenu)?

    @State private var localURL: URL?
    @State private var visualMediaStageSource: StageMetalSource?
    @State private var transitionSnowURL: URL?
    @State private var transitionSnowOpacity: Double = 1
    @State private var darkFieldOpacity: Double = 0
    @State private var lastSettledAssetId: String?
    @State private var lastSettledVideoKey: String?
    @State private var lastSettledVisualMode: VisualMode?
    @State private var loadError: String?
    /// Prevents showing a stale URL (e.g. mp4 after switching media->scene) in `unifiedMetalSource`.
    @State private var settledLoadSessionKey: String?

    init(
        isPlaying: Bool,
        rendersVisualBackground: Bool = true,
        appliesCRT: Bool = true,
        pack: BongoCatPack,
        inputTickRate: BongoInputTickRate,
        mouseCursorSpace: BongoMouseCursorSpace,
        artworkScrollWheel: ((Double) -> Void)? = nil,
        artworkContextMenu: (() -> NSMenu)? = nil
    ) {
        self.isPlaying = isPlaying
        self.rendersVisualBackground = rendersVisualBackground
        self.appliesCRT = appliesCRT
        self.pack = pack
        self.inputTickRate = inputTickRate
        self.mouseCursorSpace = mouseCursorSpace
        self.artworkScrollWheel = artworkScrollWheel
        self.artworkContextMenu = artworkContextMenu
        _coordinator = StateObject(
            wrappedValue: BongoCoordinator(
                pack: pack,
                inputTickInterval: inputTickRate.timeInterval,
                mouseCursorSpace: mouseCursorSpace
            )
        )
    }

    private var backgroundTaskKey: String {
        guard rendersVisualBackground else { return "transparent-overlay" }
        switch model.visualMode {
        case .live:
            if let directVideoURL = model.currentDirectVideoURL {
                return "direct-video/\(directVideoURL.absoluteString)"
            }
            return model.currentTrack?.image?.absoluteString ?? "no-live-artwork"
        case .scene:
            return "\(model.currentScene.id)/\(model.currentVariant.rawValue)"
        case .media:
            return model.currentVisualMedia?.id ?? "no-visual-media"
        }
    }

    /// Includes **pack** and **reload token** so switching the Live2D model
    /// always changes the `.task(id:)` value. Previously only scene/media id was
    /// used — the id stayed the same across pack changes, so the background
    /// loader could skip (or leave `transitionSnowURL` / gate state stale)
    /// while `bongoCatPack` didSet already put Live2D back in “pending”.
    private var loadSessionKey: String {
        "\(model.visualMode.rawValue)-\(backgroundTaskKey)-\(pack.cacheTag)-\(model.bongoPackReloadToken)-\(model.visualMediaReloadToken)"
    }

    private var embeddedVideoOwnsPrimaryReadiness: Bool {
        !rendersVisualBackground &&
            model.visualMode == .live &&
            model.isCurrentStationEmbeddedVideo
    }

    /// True when this `loadSessionKey` has finished loading (no transition snow,
    /// Metal source is allowed). Used so a redundant `.task` delivery for the
    /// same id does not call `resetVisualStageLoadingGate` / nil out
    /// `settledLoadSessionKey` — that was re-tearing Metal + Cubism and could
    /// leave snow visible while `markPrimaryVisualMediaReady` fired twice.
    private var isBongoBackgroundFullyReadyForCurrentLoadSession: Bool {
        guard rendersVisualBackground else {
            return settledLoadSessionKey == loadSessionKey && localURL == nil && loadError == nil
        }
        guard settledLoadSessionKey == loadSessionKey else { return false }
        guard transitionSnowURL == nil, loadError == nil else { return false }
        guard darkFieldOpacity == 0 else { return false }
        switch model.visualMode {
        case .live:
            if let directVideoURL = model.currentDirectVideoURL {
                let cacheKey = "direct-video/\(directVideoURL.absoluteString)"
                guard lastSettledVideoKey == cacheKey else { return false }
                guard localURL == directVideoURL else { return false }
                return true
            }
            guard let artworkURL = model.currentTrack?.image else {
                return localURL == nil
            }
            guard lastSettledAssetId == artworkURL.absoluteString else { return false }
            guard let disk = TrackArtworkCache.cachedURLIfAvailable(for: artworkURL),
                  localURL == disk else { return false }
            return true
        case .scene:
            let asset = model.currentScene
            let variant = model.currentVariant
            let cacheKey = "\(asset.id)/\(variant.rawValue)"
            guard lastSettledVideoKey == cacheKey else { return false }
            guard let cached = SceneVideoCache.cachedURLIfAvailable(for: asset, variant: variant),
                  localURL == cached else { return false }
            return true
        case .media:
            guard let media = model.currentVisualMedia else { return false }
            guard lastSettledAssetId == media.id else { return false }
            guard let source = visualMediaStageSource,
                  localURL == source.mediaURL else { return false }
            return true
        }
    }

    private var unifiedMetalSource: StageMetalSource? {
        guard rendersVisualBackground else { return nil }
        guard let localURL else { return nil }
        switch model.visualMode {
        case .live:
            guard settledLoadSessionKey == loadSessionKey else { return nil }
            if model.currentDirectVideoURL != nil {
                return .video(localURL)
            }
            return .image(localURL)
        case .scene:
            guard settledLoadSessionKey == loadSessionKey else { return nil }
            return .video(localURL)
        case .media:
            guard settledLoadSessionKey == loadSessionKey else { return nil }
            return visualMediaStageSource ?? .gif(localURL)
        }
    }

    var body: some View {
        ZStack {
            if rendersVisualBackground, model.visualMode == .scene {
                LinearGradient(
                    colors: [
                        model.currentScene.palette.backdropTop,
                        model.currentScene.palette.backdropBottom,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else if rendersVisualBackground {
                Color(white: 0.02)
            }

            if unifiedMetalSource != nil || !rendersVisualBackground || (model.visualMode == .live && model.currentDirectVideoURL == nil) {
                let crtCurvationUniforms = model.crt.resolvedCurvationUniforms(
                    active: appliesCRT && model.crt.enabled && model.crt.curvation
                )
                let crtVignetteAlpha = model.crt.resolvedVignetteAlpha(
                    active: appliesCRT && model.crt.enabled && model.crt.vignette
                )
                let bongoShatteredGlass = model.shatteredGlass.resolvedForDisplayPipeline(
                    crtMasterEnabled: appliesCRT && model.crt.enabled
                )
                GeometryReader { geo in
                    BongoUnifiedMetalView(
                        background: unifiedMetalSource,
                        rendersVisualBackground: rendersVisualBackground,
                        isPlaying: isPlaying,
                        renderFramesPerSecond: inputTickRate.framesPerSecond,
                        bongoCoordinator: coordinator,
                        pack: pack,
                        bongoPackReloadToken: model.bongoPackReloadToken,
                        maxLogicalStageSize: pack.maxLogicalStageSize(scaledBy: model.bongoStageScaleTier),
                        stagePlacement: model.bongoStagePlacement,
                        isStageDragLocked: model.bongoStageDragLocked,
                        backgroundTransitionSnowURL: model.visualMode == .live ? transitionSnowURL : nil,
                        backgroundTransitionSnowOpacity: model.visualMode == .live ? transitionSnowOpacity : 0,
                        backgroundDarkFieldOpacity: model.visualMode == .live ? darkFieldOpacity : 0,
                        desktopTint: model.bongoDesktopMaskTint,
                        pressedKeyImages: coordinator.pressedKeyImages,
                        agentCompanionBubbles: agentCompanion.bubbles,
                        agentCompanionBubblePosition: agentCompanion.bubblePosition,
                        agentCompanionEmojiSize: model.bongoStageScaleTier.agentCompanionEmojiSize,
                        agentCompanionBubbleFlipped: agentCompanion.bubbleFlipped,
                        artworkScrollWheel: artworkScrollWheel,
                        artworkContextMenu: artworkContextMenu,
                        crt: model.crt,
                        curvationFactor: crtCurvationUniforms.factor,
                        curvationOverscan: crtCurvationUniforms.overscan,
                        curvationBorderSize: crtCurvationUniforms.border,
                        vignetteAlpha: crtVignetteAlpha,
                        motionBlurEnabled: appliesCRT && model.crt.enabled && model.crt.motionBlur,
                        motionBlurStrength: model.crt.motionBlurStrength.resolvedStrength,
                        chromaticAberrationEnabled: appliesCRT && model.crt.enabled && model.crt.chromaticAberration,
                        chromaticAberrationStrength: model.crt.chromaticAberrationStrength.resolvedStrength,
                        scanlinesEnabled: appliesCRT && model.crt.enabled && model.crt.scanlines,
                        scanlineOpacity: model.crt.scanlineOpacity.resolvedOpacity(for: model.visualMode),
                        scanlineDensity: model.crt.scanlineDensity.pitch,
                        shatteredGlassOpacity: bongoShatteredGlass.opacity,
                        shatteredGlassRefraction: bongoShatteredGlass.refraction,
                        shatteredGlassHighlight: bongoShatteredGlass.highlight,
                        shatteredGlassFlipX: model.shatteredGlass.resolvedFlipX,
                        maxFittedStageHeightFraction: model.bongoStageScaleTier.maxFittedStageHeightFractionOfContainer,
                        layoutContainerSize: geo.size,
                        onStagePlacementRatioChanged: { ratio in
                            model.setBongoStageCustomOriginRatio(ratio)
                        },
                        onLive2DWorkspaceReady: { model.markBongoLive2DReady() }
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(metalIdentityTag(for: unifiedMetalSource))
                .allowsHitTesting(model.visualStageReady)
            }

            if model.visualMode != .live, let transitionSnowURL {
                SnowOverlayView(url: transitionSnowURL)
                    .opacity(transitionSnowOpacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }

            Color.black
                .opacity(model.visualMode == .live ? 0 : darkFieldOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            if let loadError {
                VStack(spacing: 4) {
                    PixelIcon(.signalOff, size: 16)
                    Text(loadError)
                        .font(.pixel(size: 11))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding(10)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: WidgetChromeMetrics.contentCornerRadius))
            }

        }
        .task(id: loadSessionKey) {
            if isBongoBackgroundFullyReadyForCurrentLoadSession {
                return
            }
            if !embeddedVideoOwnsPrimaryReadiness {
                model.resetVisualStageLoadingGate(updateBongoLayer: false)
            }
            settledLoadSessionKey = nil
            if !rendersVisualBackground {
                await loadTransparentOverlay(markPrimaryReady: !embeddedVideoOwnsPrimaryReadiness)
                return
            }
            switch model.visualMode {
            case .live:
                if let directVideoURL = model.currentDirectVideoURL {
                    await loadDirectLiveVideo(directVideoURL)
                } else {
                    await loadCoverArtwork()
                }
            case .media:
                await loadGif()
            case .scene:
                await loadSceneVideo()
            }
        }
        .onAppear {
            // Live2D “workspace ready” is driven from `BongoUnifiedMetalView.onLive2DWorkspaceReady`
            // (same pattern as `StageMetalPlayerView.onFirstFrameReady`). Keep this only for the rare
            // case Metal attached before the first `update` tick while the model is already loaded.
            if coordinator.bongoModelIsReady {
                model.markBongoLive2DReady()
            }
            coordinator.setPlaying(isPlaying)
        }
        .onDisappear {
            coordinator.tearDown()
        }
        .onChange(of: isPlaying) { _, newValue in
            coordinator.setPlaying(newValue)
        }
        .onChange(of: model.bongoInputTickRate) { _, rate in
            coordinator.applyInputTickRate(rate)
        }
        .onChange(of: model.bongoMouseCursorSpace) { _, space in
            coordinator.applyMouseCursorSpace(space)
        }
    }

    private func metalIdentityTag(for source: StageMetalSource?) -> String {
        let tok = model.bongoPackReloadToken
        switch source {
        case nil:
            return "transparent-overlay-\(pack.cacheTag)-\(tok)"
        case .gif:
            return "\(model.currentVisualMedia?.id ?? "media")-\(model.visualMediaReloadToken)-\(pack.cacheTag)-\(tok)"
        case .video(let url):
            return "\(url.absoluteString)-\(pack.cacheTag)-\(tok)"
        case .image(let url):
            return "\(url.absoluteString)-\(pack.cacheTag)-\(tok)"
        }
    }

    @MainActor
    private func loadTransparentOverlay(markPrimaryReady: Bool) async {
        localURL = nil
        visualMediaStageSource = nil
        loadError = nil
        darkFieldOpacity = 0
        transitionSnowOpacity = 1
        transitionSnowURL = nil
        settledLoadSessionKey = loadSessionKey
        lastSettledVisualMode = model.visualMode
        if markPrimaryReady {
            model.markPrimaryVisualMediaReady()
        }
    }

    @MainActor
    private func loadGif() async {
        guard let media = model.currentVisualMedia else {
            localURL = nil
            visualMediaStageSource = nil
            loadError = nil
            settledLoadSessionKey = nil
            lastSettledVisualMode = nil
            return
        }

        loadError = nil
        let cachedSource = media.cachedStageMetalSourceIfAvailable()

        if let cachedSource,
           localURL == cachedSource.mediaURL,
           visualMediaStageSource == cachedSource,
           lastSettledAssetId == media.id,
           transitionSnowURL == nil {
            darkFieldOpacity = 0
            transitionSnowOpacity = 1
            transitionSnowURL = nil
            settledLoadSessionKey = loadSessionKey
            lastSettledVisualMode = .media
            model.markPrimaryVisualMediaReady()
            return
        }

        let keyChanged = lastSettledAssetId != nil && lastSettledAssetId != media.id
        if let snow = await GifCache.shared.randomCachedStatic() {
            transitionSnowURL = snow
        } else if transitionSnowURL == nil {
            transitionSnowURL = GifCache.bundledSnowOverlayURL()
        }
        TransitionSnowStyle.fadeInSnowOpacity { transitionSnowOpacity = $0 }

        do {
            let source = try await media.resolveStageMetalSource()
            guard !Task.isCancelled else { return }
            localURL = source.mediaURL
            visualMediaStageSource = source
            lastSettledAssetId = media.id
            loadError = nil
            settledLoadSessionKey = loadSessionKey
            lastSettledVisualMode = .media
            DiagnosticLog.appendPlayback(
                "visualMedia.bongoResolved id=\"\(media.id)\" kind=\(media.kind.rawValue) url=\"\(source.mediaURL.path)\""
            )
            model.markPrimaryVisualMediaReady()
        } catch {
            guard !Task.isCancelled else { return }
            localURL = cachedSource?.mediaURL
            visualMediaStageSource = cachedSource
            lastSettledAssetId = media.id
            loadError = cachedSource == nil ? "Media unavailable" : nil
            DiagnosticLog.appendPlayback(
                "visualMedia.bongoResolveFailed id=\"\(media.id)\" kind=\(media.kind.rawValue) cached=\(cachedSource != nil) error=\"\(error.localizedDescription)\""
            )
            if cachedSource != nil {
                settledLoadSessionKey = loadSessionKey
                lastSettledVisualMode = .media
            } else {
                lastSettledVisualMode = nil
            }
            model.markPrimaryVisualMediaReady()
        }

        guard !Task.isCancelled, loadError == nil else {
            darkFieldOpacity = 0
            transitionSnowOpacity = 1
            transitionSnowURL = nil
            return
        }

        if keyChanged {
            try? await Task.sleep(
                nanoseconds: UInt64(TransitionSnowStyle.plateauAfterContentChange * 1_000_000_000)
            )
        }
        guard !Task.isCancelled else { return }
        await TransitionSnowStyle.darkFieldCoverThenClearSnow(
            setDarkField: { darkFieldOpacity = $0 },
            clearSnowURL: { transitionSnowURL = nil },
            resetSnowOpacity: { transitionSnowOpacity = 1 }
        )
    }

    @MainActor
    private func loadSceneVideo() async {
        let asset = model.currentScene
        let variant = model.currentVariant
        let cacheKey = "\(asset.id)/\(variant.rawValue)"
        loadError = nil

        if let cached = SceneVideoCache.cachedURLIfAvailable(for: asset, variant: variant),
           localURL == cached,
           lastSettledVideoKey == cacheKey,
           transitionSnowURL == nil {
            darkFieldOpacity = 0
            transitionSnowOpacity = 1
            transitionSnowURL = nil
            settledLoadSessionKey = loadSessionKey
            lastSettledVisualMode = .scene
            model.markPrimaryVisualMediaReady()
            return
        }

        if let snow = await GifCache.shared.randomCachedStatic() {
            transitionSnowURL = snow
        } else if transitionSnowURL == nil {
            transitionSnowURL = GifCache.bundledSnowOverlayURL()
        }
        TransitionSnowStyle.fadeInSnowOpacity { transitionSnowOpacity = $0 }

        let keyChanged = lastSettledVideoKey != nil && lastSettledVideoKey != cacheKey

        if let cached = SceneVideoCache.cachedURLIfAvailable(for: asset, variant: variant) {
            if localURL != cached {
                var tx = Transaction()
                tx.disablesAnimations = true
                withTransaction(tx) {
                    localURL = cached
                }
            }
            loadError = nil
            settledLoadSessionKey = loadSessionKey
            lastSettledVisualMode = .scene
        } else {
            localURL = nil
            loadError = nil
            do {
                let url = try await SceneVideoCache.shared.ensureLocalVideo(for: asset, variant: variant)
                guard !Task.isCancelled else {
                    darkFieldOpacity = 0
                    transitionSnowOpacity = 1
                    transitionSnowURL = nil
                    return
                }
                localURL = url
                settledLoadSessionKey = loadSessionKey
                lastSettledVisualMode = .scene
            } catch {
                guard !Task.isCancelled else {
                    darkFieldOpacity = 0
                    transitionSnowOpacity = 1
                    transitionSnowURL = nil
                    return
                }
                localURL = nil
                loadError = "Scene unavailable"
                settledLoadSessionKey = nil
                lastSettledVisualMode = nil
            }
        }

        guard !Task.isCancelled else {
            darkFieldOpacity = 0
            transitionSnowOpacity = 1
            transitionSnowURL = nil
            return
        }

        model.markPrimaryVisualMediaReady()

        if loadError != nil {
            darkFieldOpacity = 0
            transitionSnowOpacity = 1
            transitionSnowURL = nil
            return
        }

        if keyChanged {
            try? await Task.sleep(
                nanoseconds: UInt64(TransitionSnowStyle.plateauAfterContentChange * 1_000_000_000)
            )
        }
        guard !Task.isCancelled else {
            darkFieldOpacity = 0
            transitionSnowOpacity = 1
            transitionSnowURL = nil
            return
        }
        await TransitionSnowStyle.darkFieldCoverThenClearSnow(
            setDarkField: { darkFieldOpacity = $0 },
            clearSnowURL: { transitionSnowURL = nil },
            resetSnowOpacity: { transitionSnowOpacity = 1 }
        )
        lastSettledVideoKey = cacheKey
    }

    @MainActor
    private func loadDirectLiveVideo(_ url: URL) async {
        let cacheKey = "direct-video/\(url.absoluteString)"
        localURL = url
        loadError = nil
        darkFieldOpacity = 0
        transitionSnowOpacity = 1
        transitionSnowURL = nil
        lastSettledVideoKey = cacheKey
        settledLoadSessionKey = loadSessionKey
        lastSettledVisualMode = .live
        model.markPrimaryVisualMediaReady()
    }

    @MainActor
    private func loadCoverArtwork() async {
        guard let artworkURL = model.currentTrack?.image else {
            localURL = nil
            lastSettledAssetId = nil
            loadError = nil
            settledLoadSessionKey = loadSessionKey
            lastSettledVisualMode = .live
            model.markPrimaryVisualMediaReady()
            return
        }

        loadError = nil
        let diskCached = TrackArtworkCache.cachedURLIfAvailable(for: artworkURL)

        if let diskCached,
           localURL == diskCached,
           lastSettledAssetId == artworkURL.absoluteString,
           transitionSnowURL == nil {
            darkFieldOpacity = 0
            transitionSnowOpacity = 1
            transitionSnowURL = nil
            settledLoadSessionKey = loadSessionKey
            lastSettledVisualMode = .live
            model.markPrimaryVisualMediaReady()
            return
        }

        let keyChanged = lastSettledAssetId != nil && lastSettledAssetId != artworkURL.absoluteString
        if let snow = await GifCache.shared.randomCachedStatic() {
            transitionSnowURL = snow
        } else if transitionSnowURL == nil {
            transitionSnowURL = GifCache.bundledSnowOverlayURL()
        }
        TransitionSnowStyle.fadeInSnowOpacity { transitionSnowOpacity = $0 }

        do {
            let url = try await TrackArtworkCache.ensureLocal(for: artworkURL)
            guard !Task.isCancelled else { return }
            localURL = url
            lastSettledAssetId = artworkURL.absoluteString
            loadError = nil
            settledLoadSessionKey = loadSessionKey
            lastSettledVisualMode = .live
            model.markPrimaryVisualMediaReady()
        } catch {
            guard !Task.isCancelled else { return }
            localURL = diskCached
            lastSettledAssetId = artworkURL.absoluteString
            loadError = diskCached == nil ? "Cover unavailable" : nil
            if diskCached != nil {
                settledLoadSessionKey = loadSessionKey
                lastSettledVisualMode = .live
            } else {
                lastSettledVisualMode = nil
            }
            model.markPrimaryVisualMediaReady()
        }

        guard !Task.isCancelled, loadError == nil else {
            darkFieldOpacity = 0
            transitionSnowOpacity = 1
            transitionSnowURL = nil
            return
        }

        if keyChanged {
            try? await Task.sleep(
                nanoseconds: UInt64(TransitionSnowStyle.plateauAfterContentChange * 1_000_000_000)
            )
        }
        guard !Task.isCancelled else { return }
        await TransitionSnowStyle.darkFieldCoverThenClearSnow(
            setDarkField: { darkFieldOpacity = $0 },
            clearSnowURL: { transitionSnowURL = nil },
            resetSnowOpacity: { transitionSnowOpacity = 1 }
        )
    }
}

/// `MTKView` subclass so wheel-hit passthrough on the Live2D stage still gets volume scroll and the same context menu as the overlay.
/// Live2D tap uses `mouseDown`/`mouseUp` (not `NSClickGestureRecognizer`), which is reliable on Metal views.
private final class BongoStageMTKView: MTKView {
    var artworkScrollWheel: ((Double) -> Void)?
    var artworkContextMenu: (() -> NSMenu)?
    /// Point in this view’s bounds; return whether it lies in the fitted Live2D model rect.
    var stageContainsPoint: ((CGPoint) -> Bool)?
    var onStageTap: (() -> Void)?
    var onStageDrag: ((_ currentPoint: CGPoint, _ startPoint: CGPoint) -> Void)?
    var onStageDragEnded: (() -> Void)?
    var isStageDragLocked = true

    private var pendingStageInteraction: (origin: CGPoint, time: TimeInterval, mouseDownEvent: NSEvent, isDragging: Bool, didMoveStage: Bool)?
    private let stageTapMaxMove: CGFloat = 10
    private let stageTapMaxDuration: TimeInterval = 0.45

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The SwiftUI wheel/context catcher only passes primary clicks through
        // over the fitted Live2D stage rectangle. That rectangle is larger than
        // the visible model, so keep receiving those clicks and decide in
        // `mouseDown`: model pixels move the model; empty stage space drags the
        // window. Returning nil here drops the event onto non-draggable Metal
        // background views.
        return super.hitTest(point)
    }

    override func scrollWheel(with event: NSEvent) {
        artworkScrollWheel?(Double(event.scrollingDeltaY))
        super.scrollWheel(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        artworkContextMenu?() ?? super.menu(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0 else {
            pendingStageInteraction = nil
            super.mouseDown(with: event)
            return
        }
        let p = convert(event.locationInWindow, from: nil)
        let contains = stageContainsPoint?(p) == true
        NSLog(
            "[BongoTap] mouseDown point=(%.1f, %.1f) contains=%@ dragLocked=%@",
            Double(p.x),
            Double(p.y),
            contains ? "true" : "false",
            isStageDragLocked ? "true" : "false"
        )
        if contains {
            pendingStageInteraction = (p, event.timestamp, event, false, false)
            return
        }
        pendingStageInteraction = nil
        NSLog("[BongoTap] mouseDown outside model; forwarding to window drag")
        window?.performDrag(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        guard var interaction = pendingStageInteraction else {
            return
        }
        let p = convert(event.locationInWindow, from: nil)
        let dx = p.x - interaction.origin.x
        let dy = p.y - interaction.origin.y
        let distance = hypot(dx, dy)
        if !interaction.isDragging {
            guard distance > stageTapMaxMove else { return }
            interaction.isDragging = true
        }
        if isStageDragLocked {
            NSLog("[BongoTap] drag threshold exceeded while drag is locked; forwarding to window drag")
            pendingStageInteraction = nil
            window?.performDrag(with: interaction.mouseDownEvent)
            return
        }
        interaction.didMoveStage = true
        pendingStageInteraction = interaction
        onStageDrag?(p, interaction.origin)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard event.buttonNumber == 0 else {
            return
        }
        defer {
            if pendingStageInteraction?.didMoveStage == true {
                onStageDragEnded?()
            }
            pendingStageInteraction = nil
        }
        guard let start = pendingStageInteraction else {
            NSLog("[BongoTap] mouseUp ignored: no pending interaction")
            return
        }
        guard !start.isDragging else {
            NSLog("[BongoTap] mouseUp ignored: interaction became drag")
            return
        }
        guard event.clickCount <= 1 else {
            NSLog("[BongoTap] mouseUp ignored: clickCount=%ld", event.clickCount)
            return
        }
        let p = convert(event.locationInWindow, from: nil)
        let dx = p.x - start.origin.x
        let dy = p.y - start.origin.y
        let distance = hypot(dx, dy)
        guard distance <= stageTapMaxMove else {
            NSLog("[BongoTap] mouseUp ignored: moved %.2f > %.2f", Double(distance), Double(stageTapMaxMove))
            return
        }
        let duration = event.timestamp - start.time
        guard duration <= stageTapMaxDuration else {
            NSLog("[BongoTap] mouseUp ignored: duration %.3f > %.3f", duration, stageTapMaxDuration)
            return
        }
        let contains = stageContainsPoint?(p) == true
        guard contains else {
            NSLog("[BongoTap] mouseUp ignored: ended outside model")
            return
        }
        NSLog("[BongoTap] accepted tap; starting random motion")
        onStageTap?()
    }
}

private struct AgentCompanionBubbleStack: View {
    let bubbles: [AgentCompanionBubble]
    let position: AgentCompanionBubblePosition
    let stageScaleTier: BongoStageScaleTier
    let containerSize: CGSize
    let maxStageSize: CGSize
    let placement: BongoStagePlacement
    let edgeInset: CGFloat
    let maxFittedStageHeightFraction: CGFloat

    private var anchor: CGPoint? {
        guard containerSize.width > 0, containerSize.height > 0 else { return nil }
        let stage = BongoStageLayout.fittedStageSize(
            in: containerSize,
            maxStageSize: maxStageSize,
            maxFittedStageHeightFractionOfContainer: maxFittedStageHeightFraction
        )
        guard stage.width > 0, stage.height > 0 else { return nil }
        let origin = BongoStageLayout.stageOrigin(
            in: containerSize,
            stage: stage,
            placement: placement,
            edgeInset: edgeInset
        )
        let proposed: CGPoint
        let inset = max(bubbleFrameSize.width, bubbleFrameSize.height) * 0.5
        switch position {
        case .topRight:
            proposed = CGPoint(x: origin.x + stage.width - inset * 0.35, y: origin.y + inset * 0.35)
        case .topLeft:
            proposed = CGPoint(x: origin.x + inset * 0.35, y: origin.y + inset * 0.35)
        case .above:
            proposed = CGPoint(x: origin.x + stage.width * 0.5, y: origin.y - inset * 0.15)
        case .right:
            proposed = CGPoint(x: origin.x + stage.width + inset * 0.35, y: origin.y + stage.height * 0.28)
        }

        return CGPoint(
            x: min(max(proposed.x, inset), max(containerSize.width - inset, inset)),
            y: min(max(proposed.y, inset), max(containerSize.height - inset, inset))
        )
    }

    private var bubbleSize: CGFloat {
        stageScaleTier.agentCompanionEmojiSize
    }

    private var bubbleFrameSize: CGSize {
        AgentCompanionBubbleView.frameSize(for: bubbleSize)
    }

    private var stackAlignment: HorizontalAlignment {
        switch position {
        case .topLeft:
            return .leading
        case .topRight, .above, .right:
            return .trailing
        }
    }

    private func xOffset(for index: Int) -> CGFloat {
        let amount = CGFloat(index) * bubbleFrameSize.width * 0.12
        switch position {
        case .topLeft:
            return amount
        case .topRight, .above, .right:
            return -amount
        }
    }

    var body: some View {
        if !bubbles.isEmpty, let anchor {
            VStack(alignment: stackAlignment, spacing: -bubbleFrameSize.height * 0.36) {
                ForEach(Array(bubbles.enumerated()), id: \.element.id) { index, bubble in
                    AgentCompanionBubbleView(bubble: bubble, size: bubbleSize)
                        .zIndex(Double(bubbles.count - index))
                        .offset(x: xOffset(for: index))
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: bubbles)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
            .position(anchor)
        }
    }
}

private struct AgentCompanionBubbleView: View {
    let bubble: AgentCompanionBubble
    let size: CGFloat

    @State private var appeared = false
    @State private var motionPhase = false

    var body: some View {
        ZStack {
            bubbleBackground
                .frame(width: bubbleFrameSize.width, height: bubbleFrameSize.height)

            icon
                .frame(width: size, height: size)
                .offset(y: -bubbleFrameSize.height * 0.08)
        }
            .frame(width: bubbleFrameSize.width, height: bubbleFrameSize.height)
            .shadow(color: Color.black.opacity(0.36), radius: max(2, size * 0.10), x: 0, y: max(1, size * 0.05))
            .scaleEffect(appeared ? motionScale : 0.42)
            .opacity(appeared ? motionOpacity : 0)
            .rotationEffect(.degrees(motionPhase ? motion.rotationDegrees : -motion.rotationDegrees))
            .offset(
                x: appeared ? (motionPhase ? motion.x : -motion.x) : 0,
                y: appeared ? (motionPhase ? motion.y : -motion.y) : size * 0.24
            )
            .onAppear(perform: startMotion)
            .id("\(bubble.id)-\(bubble.assetName)")
    }

    static func frameSize(for emojiSize: CGFloat) -> CGSize {
        AgentCompanionBubbleMetrics.frameSize(for: emojiSize)
    }

    private var bubbleFrameSize: CGSize {
        Self.frameSize(for: size)
    }

    private var motionScale: CGFloat {
        let waitingScale: CGFloat = bubble.state == .waiting ? 1.06 : 1
        let breathingScale: CGFloat = motionPhase ? 1.025 : 0.985
        return waitingScale * breathingScale
    }

    private var motionOpacity: Double {
        motionPhase ? 0.94 : 1
    }

    private var motion: BubbleMotion {
        BubbleMotion(seed: "\(bubble.id):\(bubble.assetName)", size: size)
    }

    private var bubbleStyle: AgentCompanionBubbleStyle {
        AgentCompanionBubbleStyle.style(for: bubble)
    }

    private func startMotion() {
        appeared = false
        motionPhase = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.68, blendDuration: 0.05)) {
            appeared = true
        }
        withAnimation(.easeInOut(duration: motion.duration).repeatForever(autoreverses: true)) {
            motionPhase = true
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if let image = Self.image(named: bubbleStyle.resourceName, withExtension: "svg") {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .renderingMode(.original)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let image = Self.image(named: bubble.assetName, withExtension: "png") {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Text(bubble.fallbackIcon)
                .font(.system(size: size))
        }
    }

    private static func image(named name: String, withExtension fileExtension: String) -> NSImage? {
        guard let url = LofiiResources.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "AgentCompanion"
        ) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

}

private enum AgentCompanionBubbleMetrics {
    static func frameSize(for emojiSize: CGFloat) -> CGSize {
        CGSize(width: emojiSize * 2.2, height: emojiSize * 1.9)
    }
}

enum AgentCompanionBubbleStyle: String, CaseIterable {
    case speech = "agent-bubble-speech-short"
    case thought = "agent-bubble-thought-short"
    case noise = "agent-bubble-noise-short"

    var resourceName: String { rawValue }

    static func style(for bubble: AgentCompanionBubble) -> AgentCompanionBubbleStyle {
        random(for: bubble.id)
    }

    static func random(for seed: String) -> AgentCompanionBubbleStyle {
        let styles = allCases
        let index = Int(AgentCompanionStableHash.value(for: seed) % UInt32(styles.count))
        return styles[index]
    }
}

private struct BubbleMotion {
    let x: CGFloat
    let y: CGFloat
    let rotationDegrees: Double
    let duration: Double

    init(seed: String, size: CGFloat) {
        let value = AgentCompanionStableHash.value(for: seed)
        let xSign: CGFloat = value & 1 == 0 ? 1 : -1
        let ySign: CGFloat = value & 2 == 0 ? 1 : -1
        let xMagnitude = 0.018 + CGFloat(value % 5) * 0.004
        let yMagnitude = 0.020 + CGFloat((value >> 3) % 6) * 0.004
        x = xSign * size * xMagnitude
        y = ySign * size * yMagnitude
        rotationDegrees = 1.2 + Double((value >> 7) % 18) / 10
        duration = 1.15 + Double((value >> 11) % 70) / 100
    }
}

private enum AgentCompanionStableHash {
    static func value(for seed: String) -> UInt32 {
        seed.unicodeScalars.reduce(UInt32(2_166_136_261)) { hash, scalar in
            (hash ^ scalar.value) &* 16_777_619
        }
    }
}

private extension BongoStageScaleTier {
    var agentCompanionEmojiSize: CGFloat {
        switch self {
        case .small: return 24
        case .medium: return 32
        case .large: return 40
        }
    }
}

private struct BongoUnifiedMetalView: NSViewRepresentable {
    let background: StageMetalSource?
    let rendersVisualBackground: Bool
    let isPlaying: Bool
    let renderFramesPerSecond: Int
    let bongoCoordinator: BongoCoordinator
    let pack: BongoCatPack
    let bongoPackReloadToken: UInt
    /// User-tier cap (`pack.maxLogicalStageSize` × scale); drives fit, mask, and Live2D viewport.
    let maxLogicalStageSize: CGSize
    let stagePlacement: BongoStagePlacement
    let isStageDragLocked: Bool
    let backgroundTransitionSnowURL: URL?
    let backgroundTransitionSnowOpacity: Double
    let backgroundDarkFieldOpacity: Double
    let desktopTint: BongoDesktopMaskTint
    let pressedKeyImages: Set<String>
    let agentCompanionBubbles: [AgentCompanionBubble]
    let agentCompanionBubblePosition: AgentCompanionBubblePosition
    let agentCompanionEmojiSize: CGFloat
    let agentCompanionBubbleFlipped: Bool
    let artworkScrollWheel: ((Double) -> Void)?
    let artworkContextMenu: (() -> NSMenu)?
    let crt: CRTSettings
    let curvationFactor: Double
    let curvationOverscan: Double
    let curvationBorderSize: Double
    let vignetteAlpha: Double
    let motionBlurEnabled: Bool
    let motionBlurStrength: Double
    let chromaticAberrationEnabled: Bool
    let chromaticAberrationStrength: Double
    let scanlinesEnabled: Bool
    let scanlineOpacity: Double
    let scanlineDensity: Double
    let shatteredGlassOpacity: Double
    let shatteredGlassRefraction: Double
    let shatteredGlassHighlight: Double
    let shatteredGlassFlipX: Double
    let maxFittedStageHeightFraction: CGFloat
    /// SwiftUI-proposed size for the stage (points). Prefer over `NSView.bounds` so layout matches `GeometryReader` during resize.
    let layoutContainerSize: CGSize
    let onStagePlacementRatioChanged: (BongoStageOriginRatio) -> Void
    /// Mirrors `StageMetalPlayerView.onFirstFrameReady`: supplied by SwiftUI so `attach` never races `onAppear`.
    let onLive2DWorkspaceReady: () -> Void

    func makeCoordinator() -> BongoUnifiedMetalRenderer {
        BongoUnifiedMetalRenderer(bongoCoordinator: bongoCoordinator)
    }

    func makeNSView(context: Context) -> MTKView {
        let view = BongoStageMTKView()
        // Install render state (including `onLive2DWorkspaceReady`) before `attach`, which calls
        // `ensureModelReadyFromNative(workspaceReady:)` — same ordering contract as passing
        // callbacks through `NSViewRepresentable` values rather than mutating a coordinator later.
        update(renderer: context.coordinator)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        update(renderer: context.coordinator)
    }

    static func dismantleNSView(_ nsView: MTKView, coordinator: BongoUnifiedMetalRenderer) {
        coordinator.tearDown()
    }

    private func update(renderer: BongoUnifiedMetalRenderer) {
        renderer.update(
            background: background,
            rendersVisualBackground: rendersVisualBackground,
            isPlaying: isPlaying,
            renderFramesPerSecond: renderFramesPerSecond,
            pack: pack,
            bongoPackReloadToken: bongoPackReloadToken,
            maxLogicalStageSize: maxLogicalStageSize,
            stagePlacement: stagePlacement,
            isStageDragLocked: isStageDragLocked,
            backgroundTransitionSnowURL: backgroundTransitionSnowURL,
            backgroundTransitionSnowOpacity: backgroundTransitionSnowOpacity,
            backgroundDarkFieldOpacity: backgroundDarkFieldOpacity,
            desktopTint: desktopTint,
            pressedKeyImages: pressedKeyImages,
            agentCompanionBubbles: agentCompanionBubbles,
            agentCompanionBubblePosition: agentCompanionBubblePosition,
            agentCompanionEmojiSize: agentCompanionEmojiSize,
            agentCompanionBubbleFlipped: agentCompanionBubbleFlipped,
            artworkScrollWheel: artworkScrollWheel,
            artworkContextMenu: artworkContextMenu,
            crt: crt,
            curvationFactor: curvationFactor,
            curvationOverscan: curvationOverscan,
            curvationBorderSize: curvationBorderSize,
            vignetteAlpha: vignetteAlpha,
            motionBlurEnabled: motionBlurEnabled,
            motionBlurStrength: motionBlurStrength,
            chromaticAberrationEnabled: chromaticAberrationEnabled,
            chromaticAberrationStrength: chromaticAberrationStrength,
            scanlinesEnabled: scanlinesEnabled,
            scanlineOpacity: scanlineOpacity,
            scanlineDensity: scanlineDensity,
            shatteredGlassOpacity: shatteredGlassOpacity,
            shatteredGlassRefraction: shatteredGlassRefraction,
            shatteredGlassHighlight: shatteredGlassHighlight,
            shatteredGlassFlipX: shatteredGlassFlipX,
            maxFittedStageHeightFraction: maxFittedStageHeightFraction,
            layoutContainerSize: layoutContainerSize,
            onStagePlacementRatioChanged: onStagePlacementRatioChanged,
            onLive2DWorkspaceReady: onLive2DWorkspaceReady
        )
    }
}

@MainActor
private final class BongoUnifiedMetalRenderer: NSObject, MTKViewDelegate {
    private struct StageUniforms {
        var viewportSize: SIMD2<Float> = .zero
        var sourceSize: SIMD2<Float> = .zero
        var curvationFactor: Float = 0
        var opacity: Float = 1
        var overscan: Float = 1
        var scanlineAmount: Float = 0
        var scanlinePitch: Float = 3
        var borderSize: Float = 0
        var vignetteAlpha: Float = 0
        var motionBlurStrength: Float = 0
        var chromaticAberrationStrength: Float = 0
        var zfastBlurScaleX: Float = 0.30
        var zfastLowLumScan: Float = 6.0
        var zfastHighLumScan: Float = 8.0
        var zfastBrightBoost: Float = 1.25
        var zfastMaskDark: Float = 0.25
        var zfastMaskFade: Float = 0.8
        var glassOpacity: Float = 0
        var glassRefractionPixels: Float = 0
        var glassHighlightStrength: Float = 0
        var glassFlipX: Float = 0
        var glassTextureSize: SIMD2<Float> = .zero
    }

    private struct QuadUniforms {
        var viewportSize: SIMD2<Float> = .zero
        var rectOrigin: SIMD2<Float> = .zero
        var rectSize: SIMD2<Float> = .zero
        var opacity: Float = 1
    }

    private struct MaskUniforms {
        var color: SIMD4<Float> = .zero
        var viewportSize: SIMD2<Float> = .zero
        var leftY: Float = 0
        var rightY: Float = 0
    }

    private struct AgentCompanionPresentation {
        let key: String
        let bubble: AgentCompanionBubble
        let index: Int
    }

    private static let agentCompanionExitDuration: CFTimeInterval = 0.28

    private let bongoCoordinator: BongoCoordinator
    /// Latest handler from SwiftUI (`BongoUnifiedMetalView.onLive2DWorkspaceReady`); set in `update` before `attach`.
    private var onLive2DWorkspaceReady: () -> Void = {}
    private weak var view: MTKView?
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var textureLoader: MTKTextureLoader?
    private var videoTextureCache: CVMetalTextureCache?
    private var shatteredGlassTextures: ShatteredGlassTextureSet?
    private var stagePipelineState: MTLRenderPipelineState?
    private var quadPipelineState: MTLRenderPipelineState?
    private var maskPipelineState: MTLRenderPipelineState?
    private var offscreenTexture: MTLTexture?
    private var depthTexture: MTLTexture?
    private var offscreenSize: CGSize = .zero

    private var backgroundSource: StageMetalSource?
    private var rendersVisualBackground = true
    private var isPlaying = true
    private var pack: BongoCatPack = .bundled(.standard)
    private var maxLogicalStageSize: CGSize = .zero
    private var stagePlacement: BongoStagePlacement = .default
    private var desktopTint: BongoDesktopMaskTint = .black
    private var pressedKeyImages: Set<String> = []
    private var agentCompanionBubbles: [AgentCompanionBubble] = []
    private var agentCompanionBubblePosition: AgentCompanionBubblePosition = .topRight
    private var agentCompanionEmojiSize: CGFloat = 32
    private var agentCompanionBubbleFlipped = false
    private var agentCompanionTextures: [String: MTLTexture] = [:]
    private var agentCompanionFirstSeen: [String: CFTimeInterval] = [:]
    private var agentCompanionExitStarted: [String: CFTimeInterval] = [:]
    private var agentCompanionSnapshotBubbles: [String: AgentCompanionBubble] = [:]
    private var agentCompanionLastIndices: [String: Int] = [:]
    private var crtSettings: CRTSettings = CRTSettings()
    private var curvationFactor: Double = 0
    private var curvationOverscan: Double = 1
    private var curvationBorderSize: Double = 0
    private var vignetteAlpha: Double = 0
    private var motionBlurEnabled = false
    private var motionBlurStrength: Double = MotionBlurStrength.balanced.resolvedStrength
    private var chromaticAberrationEnabled = false
    private var chromaticAberrationStrength: Double = ChromaticAberrationStrength.balanced.resolvedStrength
    private var scanlinesEnabled = false
    private var scanlineOpacity: Double = 0
    private var scanlineDensity: Double = ScanlineDensity.balanced.pitch
    private var shatteredGlassOpacity: Double = 0
    private var shatteredGlassRefraction: Double = 0
    private var shatteredGlassHighlight: Double = 0
    private var shatteredGlassFlipX: Double = 0
    private var maxFittedStageHeightFraction: CGFloat = 1
    private var layoutContainerSize: CGSize = .zero

    private var gifCache: GifFrameCache?
    private let gifTextureFrameCache = GifMetalTextureFrameCache()
    private var currentGifTexture: MTLTexture?
    private var currentGifSize: CGSize = .zero
    private var gifFrameIndex = 0
    private var nextGifFrameTime: CFTimeInterval = 0
    private var currentImageTexture: MTLTexture?
    private var currentImageSize: CGSize = .zero

    private var player: AVPlayer?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var videoEndObserver: NSObjectProtocol?
    private var currentVideoCVTexture: CVMetalTexture?
    private var currentVideoTexture: MTLTexture?
    private var currentVideoSize: CGSize = .zero
    private var videoNoFrameLogDeadline: CFTimeInterval = 0
    private var videoTextureFailureLogged = false
    private var bongoBackgroundTexture: MTLTexture?
    private var bongoBackgroundPack: BongoCatPack?
    private var keyTextures: [String: MTLTexture] = [:]
    private var keyTexturePack: BongoCatPack?
    private var backgroundTransitionSnowURL: URL?
    private var backgroundTransitionSnowOpacity: Double = 0
    private var backgroundDarkFieldOpacity: Double = 0
    private var transitionSnowGifCache: GifFrameCache?
    private let transitionSnowTextureFrameCache = GifMetalTextureFrameCache()
    private var currentTransitionSnowTexture: MTLTexture?
    private var currentTransitionSnowSize: CGSize = .zero
    private var transitionSnowFrameIndex = 0
    private var nextTransitionSnowFrameTime: CFTimeInterval = 0
    private var desktopLayout: BongoDesktopLayout = .fallback
    private var desktopLayoutPack: BongoCatPack?
    private var desktopLayoutReloadToken: UInt = 0
    private var dynamicDesktopColor = BongoDesktopMaskTint.dynamic.metalColor
    private var hasDynamicDesktopColor = false
    private var modelDesktopColor = BongoDesktopMaskTint.modelDynamic.metalColor
    private var hasModelDesktopColor = false
    private var modelDesktopColorPack: BongoCatPack?
    private var modelDesktopColorReloadToken: UInt = 0
    private var lastFrameTime: CFTimeInterval = 0
    private var renderFramesPerSecond = 60
    private var nativeRendererSize: CGSize = .zero
    private var onStagePlacementRatioChanged: (BongoStageOriginRatio) -> Void = { _ in }
    private var activeStageDragStartPoint: CGPoint?
    private var activeStageDragStartOrigin: CGPoint?
    private var activeDragStagePlacement: BongoStagePlacement?
    private var pendingDragCommitRatio: BongoStageOriginRatio?
    private var isDraggingStage = false

    private var effectiveStagePlacement: BongoStagePlacement {
        activeDragStagePlacement ?? stagePlacement
    }

    private var hasVisibleAgentCompanionBubbles: Bool {
        !agentCompanionBubbles.isEmpty || !agentCompanionExitStarted.isEmpty
    }

    private var shouldRunDrawLoop: Bool {
        isPlaying || needsVideoFirstFramePreroll || hasVisibleAgentCompanionBubbles || isDraggingStage
    }

    init(bongoCoordinator: BongoCoordinator) {
        self.bongoCoordinator = bongoCoordinator
    }

    func attach(to view: MTKView) {
        let metalDevice = MTLCreateSystemDefaultDevice()
        self.view = view
        self.device = metalDevice
        view.device = metalDevice
        view.delegate = self
        StageMetalMTKRuntime.applyBasePresentation(to: view, framebufferOnly: false)
        applyLayerOpacityPolicy(to: view)

        guard let metalDevice else { return }
        commandQueue = metalDevice.makeCommandQueue()
        textureLoader = MTKTextureLoader(device: metalDevice)
        if let textureLoader {
            shatteredGlassTextures = ShatteredGlassTextureSet.load(using: textureLoader)
        }
        CVMetalTextureCacheCreate(nil, nil, metalDevice, nil, &videoTextureCache)
        buildPipelines(device: metalDevice, pixelFormat: view.colorPixelFormat)
        _ = bongoCoordinator.ensureNativeRenderer(device: metalDevice)
        bongoCoordinator.ensureModelReadyFromNative(workspaceReady: onLive2DWorkspaceReady)
        if let backgroundSource, case .image = backgroundSource {
            configureBackground(backgroundSource)
        }
        if let backgroundTransitionSnowURL {
            configureBackgroundTransitionSnow(url: backgroundTransitionSnowURL)
        }
    }

    func update(
        background: StageMetalSource?,
        rendersVisualBackground: Bool,
        isPlaying: Bool,
        renderFramesPerSecond: Int,
        pack: BongoCatPack,
        bongoPackReloadToken: UInt,
        maxLogicalStageSize: CGSize,
        stagePlacement: BongoStagePlacement,
        isStageDragLocked: Bool,
        backgroundTransitionSnowURL: URL?,
        backgroundTransitionSnowOpacity: Double,
        backgroundDarkFieldOpacity: Double,
        desktopTint: BongoDesktopMaskTint,
        pressedKeyImages: Set<String>,
        agentCompanionBubbles: [AgentCompanionBubble],
        agentCompanionBubblePosition: AgentCompanionBubblePosition,
        agentCompanionEmojiSize: CGFloat,
        agentCompanionBubbleFlipped: Bool,
        artworkScrollWheel: ((Double) -> Void)?,
        artworkContextMenu: (() -> NSMenu)?,
        crt: CRTSettings,
        curvationFactor: Double,
        curvationOverscan: Double,
        curvationBorderSize: Double,
        vignetteAlpha: Double,
        motionBlurEnabled: Bool,
        motionBlurStrength: Double,
        chromaticAberrationEnabled: Bool,
        chromaticAberrationStrength: Double,
        scanlinesEnabled: Bool,
        scanlineOpacity: Double,
        scanlineDensity: Double,
        shatteredGlassOpacity: Double,
        shatteredGlassRefraction: Double,
        shatteredGlassHighlight: Double,
        shatteredGlassFlipX: Double,
        maxFittedStageHeightFraction: CGFloat,
        layoutContainerSize: CGSize,
        onStagePlacementRatioChanged: @escaping (BongoStageOriginRatio) -> Void,
        onLive2DWorkspaceReady: @escaping () -> Void
    ) {
        self.onLive2DWorkspaceReady = onLive2DWorkspaceReady
        self.onStagePlacementRatioChanged = onStagePlacementRatioChanged
        let backgroundChanged = self.backgroundSource != background
        let visualBackgroundChanged = self.rendersVisualBackground != rendersVisualBackground
        let playbackChanged = self.isPlaying != isPlaying
        let agentCompanionChanged = self.agentCompanionBubbles != agentCompanionBubbles ||
            self.agentCompanionBubblePosition != agentCompanionBubblePosition ||
            self.agentCompanionEmojiSize != agentCompanionEmojiSize ||
            self.agentCompanionBubbleFlipped != agentCompanionBubbleFlipped
        let cappedFPS = StageMetalMTKRuntime.clampedPreferredFramesPerSecond(renderFramesPerSecond)
        let renderRateChanged = self.renderFramesPerSecond != cappedFPS
        let backgroundTransitionChanged =
            self.backgroundTransitionSnowURL != backgroundTransitionSnowURL ||
            self.backgroundTransitionSnowOpacity != backgroundTransitionSnowOpacity ||
            self.backgroundDarkFieldOpacity != backgroundDarkFieldOpacity

        self.isPlaying = isPlaying
        self.rendersVisualBackground = rendersVisualBackground
        self.renderFramesPerSecond = cappedFPS
        if renderRateChanged {
            view?.preferredFramesPerSecond = cappedFPS
        }
        if backgroundChanged {
            self.backgroundSource = background
            if let background {
                configureBackground(background)
            } else {
                clearBackgroundMediaState()
            }
        }
        if visualBackgroundChanged || backgroundChanged {
            applyLayerOpacityPolicy(to: view)
        }
        if self.backgroundTransitionSnowURL != backgroundTransitionSnowURL {
            configureBackgroundTransitionSnow(url: backgroundTransitionSnowURL)
        }
        self.backgroundTransitionSnowOpacity = backgroundTransitionSnowOpacity
        self.backgroundDarkFieldOpacity = backgroundDarkFieldOpacity
        if self.pack != pack {
            bongoBackgroundTexture = nil
            keyTextures.removeAll(keepingCapacity: true)
            bongoBackgroundPack = nil
            keyTexturePack = nil
        }
        if desktopLayoutPack != pack || desktopLayoutReloadToken != bongoPackReloadToken {
            desktopLayout = BongoDesktopLayout.load(for: pack)
            desktopLayoutPack = pack
            desktopLayoutReloadToken = bongoPackReloadToken
        }
        if modelDesktopColorPack != pack || modelDesktopColorReloadToken != bongoPackReloadToken {
            captureModelDesktopColor(for: pack)
            modelDesktopColorPack = pack
            modelDesktopColorReloadToken = bongoPackReloadToken
        }
        self.pack = pack
        self.maxLogicalStageSize = maxLogicalStageSize
        self.stagePlacement = stagePlacement
        if activeDragStagePlacement == stagePlacement {
            activeDragStagePlacement = nil
        }
        self.desktopTint = desktopTint
        self.pressedKeyImages = pressedKeyImages
        self.agentCompanionBubbles = agentCompanionBubbles
        self.agentCompanionBubblePosition = agentCompanionBubblePosition
        self.agentCompanionEmojiSize = agentCompanionEmojiSize
        self.agentCompanionBubbleFlipped = agentCompanionBubbleFlipped
        reconcileAgentCompanionAnimationState(now: CACurrentMediaTime())
        self.crtSettings = crt
        if let stageView = view as? BongoStageMTKView {
            stageView.artworkScrollWheel = artworkScrollWheel
            stageView.artworkContextMenu = artworkContextMenu
            stageView.isStageDragLocked = isStageDragLocked
            stageView.stageContainsPoint = { [weak self] point in
                guard let self, let v = self.view else { return false }
                let rect = self.modelHitRectInViewBounds(v)
                return rect.contains(point)
            }
            stageView.onStageTap = { [weak self] in
                let started = self?.bongoCoordinator.tryStartRandomTapMotionIfNotBusy() ?? false
                NSLog("[BongoTap] native tap motion requested started=%@", started ? "true" : "false")
            }
            stageView.onStageDrag = { [weak self] currentPoint, startPoint in
                self?.dragBongoStage(currentPoint: currentPoint, startPoint: startPoint)
            }
            stageView.onStageDragEnded = { [weak self] in
                self?.finishBongoStageDrag()
            }
        }
        self.curvationFactor = curvationFactor
        self.curvationOverscan = curvationOverscan
        self.curvationBorderSize = curvationBorderSize
        self.vignetteAlpha = vignetteAlpha
        self.motionBlurEnabled = motionBlurEnabled
        self.motionBlurStrength = motionBlurStrength
        self.chromaticAberrationEnabled = chromaticAberrationEnabled
        self.chromaticAberrationStrength = chromaticAberrationStrength
        self.scanlinesEnabled = scanlinesEnabled
        self.scanlineOpacity = scanlineOpacity
        self.scanlineDensity = scanlineDensity
        self.shatteredGlassOpacity = shatteredGlassOpacity
        self.shatteredGlassRefraction = shatteredGlassRefraction
        self.shatteredGlassHighlight = shatteredGlassHighlight
        self.shatteredGlassFlipX = shatteredGlassFlipX
        self.maxFittedStageHeightFraction = maxFittedStageHeightFraction
        self.layoutContainerSize = layoutContainerSize
        applyPlaybackStateForVideo()
        if backgroundChanged || playbackChanged || agentCompanionChanged || view?.isPaused != !shouldRunDrawLoop {
            syncDrawLoopToCurrentIntent()
        }
        if backgroundTransitionChanged, !isPlaying {
            view?.draw()
        }
    }

    /// Points size used for Bongo stage fitting.
    ///
    /// Prefer the logical size implied by `drawableSize` so it always matches the Metal viewport aspect.
    /// During fullscreen (and some resizes) SwiftUI `GeometryReader` can disagree with the MTKView drawable
    /// for a few frames; mixing that with `drawableSize` in `stageRectInPixels` yields unequal `scaleX`/`scaleY`
    /// and a visibly **stretched** Bongo until layouts settle.
    private func pointsLayoutContainer(view: NSView) -> CGSize {
        if let mtk = view as? MTKView {
            let dw = mtk.drawableSize.width
            let dh = mtk.drawableSize.height
            if dw > 1, dh > 1 {
                let scale = max(
                    mtk.layer.map { CGFloat($0.contentsScale) } ?? 0,
                    mtk.window.map { CGFloat($0.backingScaleFactor) } ?? 0,
                    1
                )
                return CGSize(width: dw / scale, height: dh / scale)
            }
        }
        if layoutContainerSize.width > 0, layoutContainerSize.height > 0 {
            return layoutContainerSize
        }
        return CGSize(width: max(view.bounds.width, 1), height: max(view.bounds.height, 1))
    }

    func tearDown() {
        if let stageView = view as? BongoStageMTKView {
            stageView.stageContainsPoint = nil
            stageView.onStageTap = nil
        }
        clearBackgroundMediaState()
        offscreenTexture = nil
        depthTexture = nil
        nativeRendererSize = .zero
        bongoBackgroundTexture = nil
        keyTextures.removeAll()
        agentCompanionTextures.removeAll()
        agentCompanionFirstSeen.removeAll()
        agentCompanionExitStarted.removeAll()
        agentCompanionSnapshotBubbles.removeAll()
        agentCompanionLastIndices.removeAll()
        backgroundSource = nil
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    private func applyLayerOpacityPolicy(to view: MTKView?) {
        guard let view else { return }
        let alpha: Double = rendersVisualBackground ? 1 : 0
        view.clearColor = MTLClearColorMake(0, 0, 0, alpha)
        view.layer?.isOpaque = rendersVisualBackground
        view.layer?.backgroundColor = rendersVisualBackground
            ? NSColor.black.cgColor
            : NSColor.clear.cgColor
    }

    private func stageLayout(in view: NSView) -> (container: CGSize, stage: CGSize, origin: CGPoint)? {
        let container = pointsLayoutContainer(view: view)
        guard container.width > 0, container.height > 0 else { return nil }
        let stage = BongoStageLayout.fittedStageSize(
            in: container,
            maxStageSize: maxLogicalStageSize,
            maxFittedStageHeightFractionOfContainer: maxFittedStageHeightFraction
        )
        guard stage.width > 0, stage.height > 0 else { return nil }
        let edgeInset = crtSettings.resolvedBongoStageEdgeInset(containerSize: container)
        let origin = BongoStageLayout.stageOrigin(
            in: container,
            stage: stage,
            placement: effectiveStagePlacement,
            edgeInset: edgeInset
        )
        return (container, stage, origin)
    }

    /// Live2D draw rect in view coordinates (matches `stageRectInPixels` layout in points).
    private func live2DStageRectInViewBounds(_ view: NSView) -> CGRect {
        guard let layout = stageLayout(in: view) else { return .zero }
        let topLeftRect = CGRect(origin: layout.origin, size: layout.stage)
        return CGRect(
            x: topLeftRect.minX,
            y: layout.container.height - topLeftRect.maxY,
            width: topLeftRect.width,
            height: topLeftRect.height
        )
    }

    private func modelHitRectInViewBounds(_ view: NSView) -> CGRect {
        let stageRect = live2DStageRectInViewBounds(view)
        guard !stageRect.isEmpty else { return .zero }
        let modelRect = bongoCoordinator.modelDrawRectForStageRect(stageRect)
        return modelRect.isEmpty ? stageRect : modelRect
    }

    private func dragBongoStage(currentPoint: CGPoint, startPoint: CGPoint) {
        guard let view, let layout = stageLayout(in: view) else { return }
        if activeStageDragStartPoint != startPoint || activeStageDragStartOrigin == nil {
            activeStageDragStartPoint = startPoint
            activeStageDragStartOrigin = layout.origin
            beginBongoStageDragIfNeeded()
        }
        guard let startOrigin = activeStageDragStartOrigin else { return }
        let proposedOrigin = CGPoint(
            x: startOrigin.x + currentPoint.x - startPoint.x,
            y: startOrigin.y - (currentPoint.y - startPoint.y)
        )
        let ratio = BongoStageOriginRatio(
            origin: proposedOrigin,
            container: layout.container,
            stage: layout.stage
        )
        activeDragStagePlacement = BongoStagePlacement(anchor: stagePlacement.anchor, customOriginRatio: ratio)
        pendingDragCommitRatio = ratio
    }

    private func beginBongoStageDragIfNeeded() {
        guard !isDraggingStage else { return }
        isDraggingStage = true
        view?.preferredFramesPerSecond = StageMetalMTKRuntime.displayMaximumFramesPerSecond
        view?.isPaused = false
        view?.enableSetNeedsDisplay = false
    }

    private func finishBongoStageDrag() {
        defer {
            activeStageDragStartPoint = nil
            activeStageDragStartOrigin = nil
            pendingDragCommitRatio = nil
            isDraggingStage = false
            view?.preferredFramesPerSecond = renderFramesPerSecond
            syncDrawLoopToCurrentIntent(drawWhenPaused: true)
        }
        guard let ratio = pendingDragCommitRatio else { return }
        onStagePlacementRatioChanged(ratio)
    }

    private func syncDrawLoopToCurrentIntent(drawWhenPaused: Bool = true) {
        if drawWhenPaused {
            StageMetalMTKRuntime.syncDrawLoopToPlayback(view: view, isPlaying: shouldRunDrawLoop)
            return
        }

        view?.isPaused = !shouldRunDrawLoop
        view?.enableSetNeedsDisplay = !shouldRunDrawLoop
    }

    func draw(in view: MTKView) {
        guard
            let drawable = view.currentDrawable,
            let commandQueue,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let stagePipelineState
        else { return }

        let viewportSize = CGSize(
            width: max(view.drawableSize.width, 1),
            height: max(view.drawableSize.height, 1)
        )
        ensureOffscreen(size: viewportSize)
        guard let offscreenTexture else { return }

        let (bgTexture, bgSize) = currentBackgroundTextureAndSize()
        if bgTexture != nil || rendersVisualBackground {
            drawStageTexture(
                commandBuffer: commandBuffer,
                target: offscreenTexture,
                sourceTexture: bgTexture,
                sourceSize: bgSize,
                viewportSize: viewportSize,
                clear: true,
                clearAlpha: rendersVisualBackground ? 1 : 0,
                effectsEnabled: false,
                pipelineState: stagePipelineState
            )
        } else {
            clearStageTarget(
                commandBuffer: commandBuffer,
                target: offscreenTexture,
                alpha: 0
            )
        }
        drawBackgroundTransitionEffects(
            commandBuffer: commandBuffer,
            target: offscreenTexture,
            viewportSize: viewportSize
        )

        drawBongoStaticLayers(
            commandBuffer: commandBuffer,
            target: offscreenTexture,
            viewportSize: viewportSize
        )
        drawBongoModel(commandBuffer: commandBuffer, target: offscreenTexture, viewportSize: viewportSize, view: view)
        drawPressedKeys(commandBuffer: commandBuffer, target: offscreenTexture, viewportSize: viewportSize)
        drawAgentCompanionBubbles(commandBuffer: commandBuffer, target: offscreenTexture, viewportSize: viewportSize)

        guard let descriptor = view.currentRenderPassDescriptor else { return }
        drawFinalStage(
            commandBuffer: commandBuffer,
            descriptor: descriptor,
            sourceTexture: offscreenTexture,
            viewportSize: viewportSize,
            pipelineState: stagePipelineState
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func buildPipelines(device: MTLDevice, pixelFormat: MTLPixelFormat) {
        do {
            let cached = try StageMetalPipelineCache.bongoPipelines(
                device: device,
                pixelFormat: pixelFormat
            )
            stagePipelineState = cached.stage
            quadPipelineState = cached.quad
            maskPipelineState = cached.mask
        } catch {
            print("[BongoUnifiedMetal] failed to build pipeline: \(error)")
        }
    }

    private func ensureOffscreen(size: CGSize) {
        guard let device else { return }
        let width = max(Int(size.width.rounded()), 1)
        let height = max(Int(size.height.rounded()), 1)
        if offscreenTexture?.width == width,
           offscreenTexture?.height == height,
           depthTexture?.width == width,
           depthTexture?.height == height {
            return
        }

        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        colorDescriptor.usage = [.renderTarget, .shaderRead]
        colorDescriptor.storageMode = .private
        offscreenTexture = device.makeTexture(descriptor: colorDescriptor)

        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        depthDescriptor.usage = [.renderTarget]
        depthDescriptor.storageMode = .private
        depthTexture = device.makeTexture(descriptor: depthDescriptor)
        offscreenSize = size
    }

    private func drawStageTexture(
        commandBuffer: MTLCommandBuffer,
        target: MTLTexture,
        sourceTexture: MTLTexture?,
        sourceSize: CGSize,
        viewportSize: CGSize,
        clear: Bool,
        clearAlpha: Double = 1,
        effectsEnabled: Bool,
        pipelineState: MTLRenderPipelineState
    ) {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = clear ? .clear : .load
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, clearAlpha)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.setFragmentTexture(shatteredGlassTextures?.pattern, index: 1)
        encoder.setFragmentTexture(shatteredGlassTextures?.background, index: 2)
        var uniforms = stageUniforms(
            viewportSize: viewportSize,
            sourceSize: sourceSize,
            effectsEnabled: effectsEnabled,
            hasTexture: sourceTexture != nil
        )
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<StageUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func clearStageTarget(
        commandBuffer: MTLCommandBuffer,
        target: MTLTexture,
        alpha: Double
    ) {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, alpha)
        commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)?.endEncoding()
    }

    private func drawFinalStage(
        commandBuffer: MTLCommandBuffer,
        descriptor: MTLRenderPassDescriptor,
        sourceTexture: MTLTexture,
        viewportSize: CGSize,
        pipelineState: MTLRenderPipelineState
    ) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.setFragmentTexture(shatteredGlassTextures?.pattern, index: 1)
        encoder.setFragmentTexture(shatteredGlassTextures?.background, index: 2)
        var uniforms = stageUniforms(
            viewportSize: viewportSize,
            sourceSize: viewportSize,
            effectsEnabled: true,
            hasTexture: true
        )
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<StageUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func drawBackgroundTransitionEffects(
        commandBuffer: MTLCommandBuffer,
        target: MTLTexture,
        viewportSize: CGSize
    ) {
        let snowTexture = backgroundTransitionSnowOpacity > 0.001 ? transitionSnowTexture() : nil
        guard let encoder = makeLoadEncoder(commandBuffer: commandBuffer, target: target) else { return }

        if backgroundTransitionSnowOpacity > 0.001,
           let quadPipelineState,
           let texture = snowTexture {
            encoder.setRenderPipelineState(quadPipelineState)
            drawTextureAspectFill(
                texture: texture,
                sourceSize: currentTransitionSnowSize,
                encoder: encoder,
                viewportSize: viewportSize,
                opacity: Float(backgroundTransitionSnowOpacity)
            )
        }

        if backgroundDarkFieldOpacity > 0.001,
           let maskPipelineState {
            encoder.setRenderPipelineState(maskPipelineState)
            var uniforms = MaskUniforms(
                color: SIMD4<Float>(0, 0, 0, Float(backgroundDarkFieldOpacity)),
                viewportSize: SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height)),
                leftY: 0,
                rightY: 0
            )
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MaskUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }

        encoder.endEncoding()
    }

    private func stageUniforms(
        viewportSize: CGSize,
        sourceSize: CGSize,
        effectsEnabled: Bool,
        hasTexture: Bool
    ) -> StageUniforms {
        let resolvedOverscan: Float = {
            guard effectsEnabled else { return 1 }
            let o = CRTStageViewportShaping.resolvedOverscan(
                curvationFactor: curvationFactor,
                presetOverscan: curvationOverscan
            )
            return Float(o)
        }()
        return StageUniforms(
            viewportSize: SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height)),
            sourceSize: SIMD2<Float>(Float(max(sourceSize.width, 1)), Float(max(sourceSize.height, 1))),
            curvationFactor: effectsEnabled ? Float(curvationFactor) : 0,
            opacity: hasTexture ? 1 : 0,
            overscan: resolvedOverscan,
            scanlineAmount: effectsEnabled && scanlinesEnabled ? Float(scanlineOpacity) : 0,
            scanlinePitch: Float(scanlineDensity),
            borderSize: effectsEnabled ? Float(curvationBorderSize) : 0,
            vignetteAlpha: effectsEnabled ? Float(vignetteAlpha) : 0,
            motionBlurStrength: effectsEnabled && motionBlurEnabled ? Float(motionBlurStrength) : 0,
            chromaticAberrationStrength: effectsEnabled && chromaticAberrationEnabled ? Float(chromaticAberrationStrength) : 0,
            zfastBlurScaleX: 0.30,
            zfastLowLumScan: 6.0,
            zfastHighLumScan: 8.0,
            zfastBrightBoost: 1.25,
            zfastMaskDark: 0.25,
            zfastMaskFade: 0.8,
            glassOpacity: effectsEnabled && shatteredGlassTextures != nil ? Float(shatteredGlassOpacity) : 0,
            glassRefractionPixels: Float(shatteredGlassRefraction),
            glassHighlightStrength: Float(shatteredGlassHighlight),
            glassFlipX: Float(shatteredGlassFlipX),
            glassTextureSize: SIMD2<Float>(
                Float(shatteredGlassTextures?.background.width ?? 1),
                Float(shatteredGlassTextures?.background.height ?? 1)
            )
        )
    }

    private func drawBongoStaticLayers(
        commandBuffer: MTLCommandBuffer,
        target: MTLTexture,
        viewportSize: CGSize
    ) {
        guard
            let maskPipelineState,
            let quadPipelineState,
            let encoder = makeLoadEncoder(commandBuffer: commandBuffer, target: target)
        else { return }

        if desktopTint != .hidden,
           let endpoints = cutLineEndpointsInPixels(viewportSize: viewportSize) {
            encoder.setRenderPipelineState(maskPipelineState)
            var uniforms = MaskUniforms(
                color: resolvedDesktopMaskColor,
                viewportSize: SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height)),
                leftY: Float(endpoints.leftY),
                rightY: Float(endpoints.rightY)
            )
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MaskUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }

        if let texture = backgroundTexture() {
            encoder.setRenderPipelineState(quadPipelineState)
            drawStageTextureQuad(texture: texture, encoder: encoder, viewportSize: viewportSize)
        }

        encoder.endEncoding()
    }

    private var resolvedDesktopMaskColor: SIMD4<Float> {
        switch desktopTint {
        case .dynamic:
            return hasDynamicDesktopColor ? dynamicDesktopColor : desktopTint.metalColor
        case .modelDynamic:
            return hasModelDesktopColor ? modelDesktopColor : desktopTint.metalColor
        default:
            return desktopTint.metalColor
        }
    }

    private func drawPressedKeys(commandBuffer: MTLCommandBuffer, target: MTLTexture, viewportSize: CGSize) {
        guard
            !pressedKeyImages.isEmpty,
            let quadPipelineState,
            let encoder = makeLoadEncoder(commandBuffer: commandBuffer, target: target)
        else { return }

        encoder.setRenderPipelineState(quadPipelineState)
        for key in pressedKeyImages.sorted() {
            if let texture = keyTexture(id: key) {
                drawStageTextureQuad(texture: texture, encoder: encoder, viewportSize: viewportSize)
            }
        }
        encoder.endEncoding()
    }

    private func drawAgentCompanionBubbles(commandBuffer: MTLCommandBuffer, target: MTLTexture, viewportSize: CGSize) {
        let now = CACurrentMediaTime()
        reconcileAgentCompanionAnimationState(now: now)
        let presentations = agentCompanionPresentations()
        if presentations.isEmpty {
            syncDrawLoopToCurrentIntent(drawWhenPaused: false)
            return
        }
        guard
            let quadPipelineState,
            let encoder = makeLoadEncoder(commandBuffer: commandBuffer, target: target)
        else { return }

        encoder.setRenderPipelineState(quadPipelineState)
        for presentation in presentations.sorted(by: { $0.index > $1.index }) {
            guard let drawState = agentCompanionDrawState(
                for: presentation.bubble,
                key: presentation.key,
                index: presentation.index,
                now: now,
                viewportSize: viewportSize
            ),
                  let texture = agentCompanionTexture(for: presentation.bubble, frameSize: drawState.frameSize)
            else { continue }
            drawTextureQuad(
                texture: texture,
                rect: drawState.rect,
                encoder: encoder,
                viewportSize: viewportSize,
                opacity: drawState.opacity
            )
        }
        encoder.endEncoding()
    }

    private func agentCompanionDrawState(
        for bubble: AgentCompanionBubble,
        key: String,
        index: Int,
        now: CFTimeInterval,
        viewportSize: CGSize
    ) -> (rect: CGRect, frameSize: CGSize, opacity: Float)? {
        guard let view, let layout = stageLayout(in: view) else { return nil }
        let scaleX = viewportSize.width / max(layout.container.width, 1)
        let scaleY = viewportSize.height / max(layout.container.height, 1)
        let emojiSize = max(agentCompanionEmojiSize, 1)
        let framePoints = AgentCompanionBubbleMetrics.frameSize(for: emojiSize)
        let frameSize = CGSize(
            width: max(1, (framePoints.width * scaleX).rounded()),
            height: max(1, (framePoints.height * scaleY).rounded())
        )
        let anchor = agentCompanionAnchor(
            layout: layout,
            frameSize: framePoints
        )
        let stackXOffset = agentCompanionStackXOffset(for: index, frameWidth: framePoints.width)
        let stackYOffset = -CGFloat(index) * framePoints.height * 0.36
        let animation = agentCompanionAnimation(for: bubble, key: key, now: now, size: framePoints.width)
        let center = CGPoint(
            x: anchor.x + stackXOffset + animation.x,
            y: anchor.y + stackYOffset + animation.y + animation.entryYOffset
        )
        let scaledFramePoints = CGSize(
            width: framePoints.width * animation.scale,
            height: framePoints.height * animation.scale
        )
        let scaledFrameSize = CGSize(
            width: max(1, (scaledFramePoints.width * scaleX).rounded()),
            height: max(1, (scaledFramePoints.height * scaleY).rounded())
        )
        let originPoints = CGPoint(
            x: center.x - scaledFramePoints.width * 0.5,
            y: center.y - scaledFramePoints.height * 0.5
        )
        return (
            CGRect(
                x: originPoints.x * scaleX,
                y: originPoints.y * scaleY,
                width: scaledFrameSize.width,
                height: scaledFrameSize.height
            ),
            frameSize,
            animation.opacity
        )
    }

    private func agentCompanionAnchor(
        layout: (container: CGSize, stage: CGSize, origin: CGPoint),
        frameSize: CGSize
    ) -> CGPoint {
        let inset = max(frameSize.width, frameSize.height) * 0.5
        let proposed: CGPoint
        switch agentCompanionBubblePosition {
        case .topRight:
            proposed = CGPoint(x: layout.origin.x + layout.stage.width - inset * 0.35, y: layout.origin.y + inset * 0.35)
        case .topLeft:
            proposed = CGPoint(x: layout.origin.x + inset * 0.35, y: layout.origin.y + inset * 0.35)
        case .above:
            proposed = CGPoint(x: layout.origin.x + layout.stage.width * 0.5, y: layout.origin.y - inset * 0.15)
        case .right:
            proposed = CGPoint(x: layout.origin.x + layout.stage.width + inset * 0.35, y: layout.origin.y + layout.stage.height * 0.28)
        }
        return CGPoint(
            x: min(max(proposed.x, inset), max(layout.container.width - inset, inset)),
            y: min(max(proposed.y, inset), max(layout.container.height - inset, inset))
        )
    }

    private func agentCompanionStackXOffset(for index: Int, frameWidth: CGFloat) -> CGFloat {
        let amount = CGFloat(index) * frameWidth * 0.12
        switch agentCompanionBubblePosition {
        case .topLeft:
            return amount
        case .topRight, .above, .right:
            return -amount
        }
    }

    private func agentCompanionAnimation(
        for bubble: AgentCompanionBubble,
        key: String,
        now: CFTimeInterval,
        size: CGFloat
    ) -> (x: CGFloat, y: CGFloat, entryYOffset: CGFloat, scale: CGFloat, opacity: Float) {
        let firstSeen = agentCompanionFirstSeen[key] ?? now
        let age = max(0, now - firstSeen)
        let entrance = min(age / 0.32, 1)
        let easedEntrance = 1 - pow(1 - entrance, 3)
        let motion = BubbleMotion(seed: "\(bubble.id):\(bubble.assetName)", size: size)
        let phase = sin(now * (2 * .pi / motion.duration))
        let opacityPulse = 0.97 + 0.03 * cos(now * (2 * .pi / (motion.duration * 1.18)))
        let entryYOffset = size * 0.24 * (1 - easedEntrance)
        let entryScale = 0.70 + 0.30 * easedEntrance

        if let exitStarted = agentCompanionExitStarted[key] {
            let exitProgress = min(max((now - exitStarted) / Self.agentCompanionExitDuration, 0), 1)
            let easedExit = 1 - pow(1 - exitProgress, 2)
            return (
                x: motion.x * phase,
                y: motion.y * phase - size * 0.18 * easedExit,
                entryYOffset: entryYOffset,
                scale: entryScale * (1 - 0.22 * easedExit),
                opacity: Float(min(max((1 - easedExit) * opacityPulse, 0), 1))
            )
        }

        return (
            x: motion.x * phase,
            y: motion.y * phase,
            entryYOffset: entryYOffset,
            scale: entryScale,
            opacity: Float(min(max(easedEntrance * opacityPulse, 0), 1))
        )
    }

    private func reconcileAgentCompanionAnimationState(now: CFTimeInterval) {
        let activePairs = agentCompanionBubbles.enumerated().map { index, bubble in
            (key: agentCompanionAnimationKey(for: bubble), index: index, bubble: bubble)
        }
        let activeKeys = Set(activePairs.map(\.key))

        for pair in activePairs {
            agentCompanionSnapshotBubbles[pair.key] = pair.bubble
            agentCompanionLastIndices[pair.key] = pair.index
            agentCompanionExitStarted[pair.key] = nil
        }

        for key in activeKeys where agentCompanionFirstSeen[key] == nil {
            agentCompanionFirstSeen[key] = now
        }

        for key in agentCompanionSnapshotBubbles.keys where !activeKeys.contains(key) && agentCompanionExitStarted[key] == nil {
            agentCompanionExitStarted[key] = now
        }

        let visibleKeys = Set(agentCompanionSnapshotBubbles.keys.filter { key in
            if activeKeys.contains(key) {
                return true
            }
            guard let exitStarted = agentCompanionExitStarted[key] else {
                return false
            }
            return now - exitStarted < Self.agentCompanionExitDuration
        })

        agentCompanionFirstSeen = agentCompanionFirstSeen.filter { visibleKeys.contains($0.key) }
        agentCompanionExitStarted = agentCompanionExitStarted.filter { visibleKeys.contains($0.key) }
        agentCompanionSnapshotBubbles = agentCompanionSnapshotBubbles.filter { visibleKeys.contains($0.key) }
        agentCompanionLastIndices = agentCompanionLastIndices.filter { visibleKeys.contains($0.key) }
    }

    private func agentCompanionAnimationKey(for bubble: AgentCompanionBubble) -> String {
        "\(bubble.id):\(bubble.assetName)"
    }

    private func agentCompanionPresentations() -> [AgentCompanionPresentation] {
        var presentations: [AgentCompanionPresentation] = []
        let activeKeys = Set(agentCompanionBubbles.map(agentCompanionAnimationKey))

        for (index, bubble) in agentCompanionBubbles.enumerated() {
            let key = agentCompanionAnimationKey(for: bubble)
            presentations.append(AgentCompanionPresentation(key: key, bubble: bubble, index: index))
        }

        for (key, bubble) in agentCompanionSnapshotBubbles where !activeKeys.contains(key) {
            presentations.append(AgentCompanionPresentation(
                key: key,
                bubble: bubble,
                index: agentCompanionLastIndices[key] ?? presentations.count
            ))
        }
        return presentations
    }

    private func makeLoadEncoder(commandBuffer: MTLCommandBuffer, target: MTLTexture) -> MTLRenderCommandEncoder? {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .load
        descriptor.colorAttachments[0].storeAction = .store
        return commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
    }

    private func drawStageTextureQuad(texture: MTLTexture, encoder: MTLRenderCommandEncoder, viewportSize: CGSize) {
        let rect = stageRectInPixels(viewportSize: viewportSize)
        guard rect.width > 0, rect.height > 0 else { return }
        drawTextureQuad(texture: texture, rect: rect, encoder: encoder, viewportSize: viewportSize, opacity: 1)
    }

    private func drawTextureAspectFill(
        texture: MTLTexture,
        sourceSize: CGSize,
        encoder: MTLRenderCommandEncoder,
        viewportSize: CGSize,
        opacity: Float
    ) {
        let sourceWidth = max(sourceSize.width, 1)
        let sourceHeight = max(sourceSize.height, 1)
        let scale = max(viewportSize.width / sourceWidth, viewportSize.height / sourceHeight)
        let drawnSize = CGSize(width: sourceWidth * scale, height: sourceHeight * scale)
        let rect = CGRect(
            x: (viewportSize.width - drawnSize.width) / 2,
            y: (viewportSize.height - drawnSize.height) / 2,
            width: drawnSize.width,
            height: drawnSize.height
        )
        drawTextureQuad(texture: texture, rect: rect, encoder: encoder, viewportSize: viewportSize, opacity: opacity)
    }

    private func drawTextureQuad(
        texture: MTLTexture,
        rect: CGRect,
        encoder: MTLRenderCommandEncoder,
        viewportSize: CGSize,
        opacity: Float
    ) {
        guard rect.width > 0, rect.height > 0, opacity > 0 else { return }
        var uniforms = QuadUniforms(
            viewportSize: SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height)),
            rectOrigin: SIMD2<Float>(Float(rect.minX), Float(rect.minY)),
            rectSize: SIMD2<Float>(Float(rect.width), Float(rect.height)),
            opacity: opacity
        )
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<QuadUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<QuadUniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    private func drawBongoModel(
        commandBuffer: MTLCommandBuffer,
        target: MTLTexture,
        viewportSize: CGSize,
        view: MTKView
    ) {
        guard let depthTexture else { return }
        let rect = stageRectInPixels(viewportSize: viewportSize)
        guard rect.width > 0, rect.height > 0 else { return }

        let rendererWidth = max(Int(rect.width.rounded()), 1)
        let rendererHeight = max(Int(rect.height.rounded()), 1)
        let rendererSize = CGSize(width: rendererWidth, height: rendererHeight)
        if nativeRendererSize != rendererSize {
            bongoCoordinator.resizeNativeRenderer(width: rendererWidth, height: rendererHeight)
            nativeRendererSize = rendererSize
        }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .load
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.depthAttachment.texture = depthTexture
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.storeAction = .dontCare
        descriptor.depthAttachment.clearDepth = 1.0

        let now = CACurrentMediaTime()
        let delta = lastFrameTime > 0 ? now - lastFrameTime : 1.0 / 60.0
        lastFrameTime = now

        let viewport = MTLViewport(
            originX: rect.minX,
            originY: rect.minY,
            width: rect.width,
            height: rect.height,
            znear: 0,
            zfar: 1
        )
        bongoCoordinator.drawNativeRenderer(
            commandBuffer: commandBuffer,
            renderPassDescriptor: descriptor,
            viewport: viewport,
            deltaTime: isPlaying ? delta : 0
        )
    }

    private func configureBackground(_ source: StageMetalSource) {
        clearBackgroundMediaState()
        currentVideoSize = .zero
        videoNoFrameLogDeadline = 0
        videoTextureFailureLogged = false
        dynamicDesktopColor = BongoDesktopMaskTint.dynamic.metalColor
        hasDynamicDesktopColor = false
        currentGifSize = .zero
        gifFrameIndex = 0
        nextGifFrameTime = 0
        currentImageTexture = nil
        currentImageSize = .zero

        switch source {
        case .video(let url):
            configureVideo(url: url)
        case .gif(let url):
            configureGif(url: url)
        case .image(let url):
            configureImage(url: url)
        }
    }

    private func clearBackgroundMediaState() {
        player?.pause()
        if let videoEndObserver {
            NotificationCenter.default.removeObserver(videoEndObserver)
        }
        if let item = player?.currentItem, let videoOutput {
            item.remove(videoOutput)
        }
        videoEndObserver = nil
        player = nil
        videoOutput = nil
        currentVideoCVTexture = nil
        currentVideoTexture = nil
        if let videoTextureCache {
            CVMetalTextureCacheFlush(videoTextureCache, 0)
        }
        gifCache = nil
        gifTextureFrameCache.clear()
        currentGifTexture = nil
        currentImageTexture = nil
    }

    private func configureVideo(url: URL) {
        let item = AVPlayerItem(url: url)
        let pixelBufferAttributes: [String: any Sendable] = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: String](),
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelBufferAttributes)
        item.add(output)

        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.isMuted = true
        avPlayer.volume = 0
        avPlayer.actionAtItemEnd = .none
        avPlayer.automaticallyWaitsToMinimizeStalling = false
        videoEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loopVideoIfNeeded()
            }
        }
        player = avPlayer
        videoOutput = output
    }

    private func configureGif(url: URL) {
        gifCache = GifFrameCachePool.shared.cache(for: url) ?? GifFrameCache(url: url)
        currentGifSize = gifCache?.pixelSize ?? .zero
        gifTextureFrameCache.reset(url: url, frameCache: gifCache)
        gifFrameIndex = 0
        nextGifFrameTime = 0
        uploadGifFrame(at: 0)
    }

    private func configureImage(url: URL) {
        guard let textureLoader else { return }
        do {
            let texture = try textureLoader.newTexture(
                URL: url,
                options: [
                    MTKTextureLoader.Option.SRGB: false,
                    MTKTextureLoader.Option.origin: MTKTextureLoader.Origin.topLeft,
                ]
            )
            currentImageTexture = texture
            currentImageSize = CGSize(width: texture.width, height: texture.height)
            if let image = NSImage(contentsOf: url),
               let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                captureDynamicDesktopColorIfNeeded(from: cgImage)
            }
        } catch {
            print("[BongoUnifiedMetal] failed to load image texture: \(error)")
        }
    }

    private func configureBackgroundTransitionSnow(url: URL?) {
        backgroundTransitionSnowURL = url
        transitionSnowGifCache = nil
        transitionSnowTextureFrameCache.clear()
        currentTransitionSnowTexture = nil
        currentTransitionSnowSize = .zero
        transitionSnowFrameIndex = 0
        nextTransitionSnowFrameTime = 0

        guard let url else { return }
        transitionSnowGifCache = GifFrameCachePool.shared.cache(for: url) ?? GifFrameCache(url: url)
        if let transitionSnowGifCache {
            currentTransitionSnowSize = transitionSnowGifCache.pixelSize
        }
        transitionSnowTextureFrameCache.reset(url: url, frameCache: transitionSnowGifCache)
        uploadTransitionSnowFrame(at: 0)
    }

    private func applyPlaybackStateForVideo() {
        guard case .video = backgroundSource else { return }
        if isPlaying || needsVideoFirstFramePreroll {
            player?.play()
        } else {
            player?.pause()
        }
    }

    private var needsVideoFirstFramePreroll: Bool {
        guard case .video = backgroundSource else { return false }
        return currentVideoTexture == nil
    }

    private func settlePausedVideoPrerollIfNeeded() {
        guard case .video = backgroundSource, !isPlaying else { return }
        player?.pause()
        syncDrawLoopToCurrentIntent(drawWhenPaused: false)
    }

    private func loopVideoIfNeeded() {
        guard case .video = backgroundSource, let player else { return }
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        if isPlaying {
            player.play()
        }
    }

    private func currentBackgroundTextureAndSize() -> (MTLTexture?, CGSize) {
        switch backgroundSource {
        case .video:
            updateVideoTexture()
            return (currentVideoTexture, currentVideoSize)
        case .gif:
            updateGifTexture()
            return (currentGifTexture, currentGifSize)
        case .image:
            return (currentImageTexture, currentImageSize)
        case nil:
            return (nil, .zero)
        }
    }

    private func transitionSnowTexture() -> MTLTexture? {
        guard backgroundTransitionSnowURL != nil else { return nil }
        guard isPlaying || currentTransitionSnowTexture == nil else { return currentTransitionSnowTexture }
        let now = CACurrentMediaTime()
        guard nextTransitionSnowFrameTime <= 0 || now >= nextTransitionSnowFrameTime else {
            return currentTransitionSnowTexture
        }
        uploadTransitionSnowFrame(at: transitionSnowFrameIndex)
        return currentTransitionSnowTexture
    }

    private func updateVideoTexture() {
        guard
            let output = videoOutput,
            let cache = videoTextureCache
        else { return }

        let itemTime = preferredVideoItemTime(output: output)
        let pixelBuffer: CVPixelBuffer?
        if output.hasNewPixelBuffer(forItemTime: itemTime) {
            pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
        } else if currentVideoTexture == nil {
            pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
        } else {
            pixelBuffer = nil
        }
        guard let pixelBuffer else {
            logVideoNoFrameIfNeeded(itemTime: itemTime)
            return
        }
        videoNoFrameLogDeadline = 0

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        guard status == kCVReturnSuccess, let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else {
            if !videoTextureFailureLogged {
                videoTextureFailureLogged = true
                print("[BongoUnifiedMetal] video CVMetalTexture creation failed status=\(status) size=\(width)x\(height)")
            }
            return
        }
        currentVideoCVTexture = cvTexture
        currentVideoTexture = texture
        currentVideoSize = CGSize(width: width, height: height)
        captureDynamicDesktopColorIfNeeded(from: pixelBuffer)
        settlePausedVideoPrerollIfNeeded()
    }

    private func logVideoNoFrameIfNeeded(itemTime: CMTime) {
        guard currentVideoTexture == nil else { return }
        let now = CACurrentMediaTime()
        if videoNoFrameLogDeadline == 0 {
            videoNoFrameLogDeadline = now + 1.0
            return
        }
        guard now >= videoNoFrameLogDeadline else { return }
        videoNoFrameLogDeadline = now + 2.0

        let status: String
        switch player?.currentItem?.status {
        case .readyToPlay?: status = "ready"
        case .failed?: status = "failed"
        case .unknown?: status = "unknown"
        case nil: status = "nil"
        @unknown default: status = "other"
        }
        let error = player?.currentItem?.error?.localizedDescription ?? "nil"
        print(
            "[BongoUnifiedMetal] video waiting for first frame status=\(status) rate=\(player?.rate ?? -1) itemTime=\(String(format: "%.3f", itemTime.seconds)) error=\(error)"
        )
    }

    private func preferredVideoItemTime(output: AVPlayerItemVideoOutput) -> CMTime {
        let hostTime = CACurrentMediaTime()
        let hostItemTime = output.itemTime(forHostTime: hostTime)
        if hostItemTime.isValid && !hostItemTime.isIndefinite {
            return hostItemTime
        }
        if let currentTime = player?.currentTime(), currentTime.isValid && !currentTime.isIndefinite {
            return currentTime
        }
        return .zero
    }

    private func updateGifTexture() {
        guard isPlaying || currentGifTexture == nil else { return }
        let now = CACurrentMediaTime()
        guard nextGifFrameTime <= 0 || now >= nextGifFrameTime else { return }
        uploadGifFrame(at: gifFrameIndex)
    }

    private func uploadGifFrame(at index: Int) {
        guard
            let cache = gifCache,
            let textureLoader,
            cache.frameCount > 0
        else { return }

        do {
            let frame = try gifTextureFrameCache.texture(
                at: index,
                frameCache: cache,
                textureLoader: textureLoader,
                onImageDecoded: { [weak self] image in
                    self?.captureDynamicDesktopColorIfNeeded(from: image)
                }
            )
            guard let texture = frame.texture else { return }
            currentGifTexture = texture
            currentGifSize = frame.size
            let safeIndex = index % cache.frameCount
            gifFrameIndex = (safeIndex + 1) % cache.frameCount
            nextGifFrameTime = CACurrentMediaTime() + max(frame.delay, 0.016)
        } catch {
            print("[BongoUnifiedMetal] failed to upload GIF frame: \(error)")
            nextGifFrameTime = CACurrentMediaTime() + 0.25
        }
    }

    private func uploadTransitionSnowFrame(at index: Int) {
        guard
            let cache = transitionSnowGifCache,
            let textureLoader,
            cache.frameCount > 0
        else { return }

        do {
            let frame = try transitionSnowTextureFrameCache.texture(
                at: index,
                frameCache: cache,
                textureLoader: textureLoader
            )
            guard let texture = frame.texture else { return }
            currentTransitionSnowTexture = texture
            currentTransitionSnowSize = frame.size
            let safeIndex = index % cache.frameCount
            transitionSnowFrameIndex = (safeIndex + 1) % cache.frameCount
            nextTransitionSnowFrameTime = CACurrentMediaTime() + max(frame.delay, 0.016)
        } catch {
            print("[BongoUnifiedMetal] failed to upload transition snow frame: \(error)")
            nextTransitionSnowFrameTime = CACurrentMediaTime() + 0.25
        }
    }

    private func captureModelDesktopColor(for pack: BongoCatPack) {
        modelDesktopColor = BongoDesktopMaskTint.modelDynamic.metalColor
        hasModelDesktopColor = false
        guard let url = pack.resourcesDirectoryURL?.appendingPathComponent("background.png"),
              let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return
        }
        modelDesktopColor = averageDesktopColor(from: cgImage, fallback: BongoDesktopMaskTint.modelDynamic.metalColor)
        hasModelDesktopColor = true
    }

    private func captureDynamicDesktopColorIfNeeded(from image: CGImage) {
        guard !hasDynamicDesktopColor else { return }
        dynamicDesktopColor = averageDesktopColor(from: image, fallback: BongoDesktopMaskTint.dynamic.metalColor)
        hasDynamicDesktopColor = true
    }

    private func averageDesktopColor(from image: CGImage, fallback: SIMD4<Float>) -> SIMD4<Float> {
        let rep = NSBitmapImageRep(cgImage: image)
        let width = max(rep.pixelsWide, 1)
        let height = max(rep.pixelsHigh, 1)
        return averageDynamicDesktopColor(width: width, height: height, fallback: fallback) { x, y in
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                return nil
            }
            guard color.alphaComponent > 0.1 else { return nil }
            return SIMD3<Float>(
                Float(color.redComponent),
                Float(color.greenComponent),
                Float(color.blueComponent)
            )
        }
    }

    private func captureDynamicDesktopColorIfNeeded(from pixelBuffer: CVPixelBuffer) {
        guard !hasDynamicDesktopColor else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        dynamicDesktopColor = averageDynamicDesktopColor(
            width: width,
            height: height,
            fallback: BongoDesktopMaskTint.dynamic.metalColor
        ) { x, y in
            let offset = y * rowBytes + x * 4
            return SIMD3<Float>(
                Float(bytes[offset + 2]) / 255.0,
                Float(bytes[offset + 1]) / 255.0,
                Float(bytes[offset]) / 255.0
            )
        }
        hasDynamicDesktopColor = true
    }

    private func averageDynamicDesktopColor(
        width: Int,
        height: Int,
        fallback: SIMD4<Float>,
        sample: (Int, Int) -> SIMD3<Float>?
    ) -> SIMD4<Float> {
        let taps: [SIMD2<Float>] = [
            SIMD2<Float>(0.22, 0.58),
            SIMD2<Float>(0.50, 0.58),
            SIMD2<Float>(0.78, 0.58),
            SIMD2<Float>(0.28, 0.76),
            SIMD2<Float>(0.50, 0.78),
            SIMD2<Float>(0.72, 0.76),
        ]

        var sum = SIMD3<Float>(repeating: 0)
        var count: Float = 0
        for tap in taps {
            let x = min(max(Int((tap.x * Float(width - 1)).rounded()), 0), width - 1)
            let y = min(max(Int((tap.y * Float(height - 1)).rounded()), 0), height - 1)
            guard let color = sample(x, y) else { continue }
            sum += color
            count += 1
        }

        guard count > 0 else { return fallback }
        let average = sum / count
        let rgb = SIMD3<Float>(
            min(max(average.x, 0), 1),
            min(max(average.y, 0), 1),
            min(max(average.z, 0), 1)
        )
        return SIMD4<Float>(rgb.x, rgb.y, rgb.z, 1)
    }

    private func backgroundTexture() -> MTLTexture? {
        if bongoBackgroundPack == pack {
            return bongoBackgroundTexture
        }
        bongoBackgroundPack = pack
        bongoBackgroundTexture = loadPNG(resource: "background", baseDirectory: pack.resourcesDirectoryURL)
        return bongoBackgroundTexture
    }

    private func keyTexture(id: String) -> MTLTexture? {
        if keyTexturePack != pack {
            keyTextures.removeAll(keepingCapacity: true)
            keyTexturePack = pack
        }
        if let cached = keyTextures[id] {
            return cached
        }
        let texture: MTLTexture?
        if let overlay = BongoKeyOverlay(id: id) {
            texture = loadPNG(resource: overlay.stem, baseDirectory: pack.keyDirectoryURL(for: overlay.side))
        } else {
            texture = loadPNG(resource: id, baseDirectory: pack.leftKeysDirectoryURL)
        }
        keyTextures[id] = texture
        return texture
    }

    private func agentCompanionTexture(for bubble: AgentCompanionBubble, frameSize: CGSize) -> MTLTexture? {
        guard let textureLoader else { return nil }
        let frameWidth = max(Int(frameSize.width.rounded()), 1)
        let frameHeight = max(Int(frameSize.height.rounded()), 1)
        let style = AgentCompanionBubbleStyle.style(for: bubble)
        let key = "\(style.resourceName):\(bubble.assetName):flip-\(agentCompanionBubbleFlipped):\(frameWidth)x\(frameHeight)"
        if let cached = agentCompanionTextures[key] {
            return cached
        }
        guard let cgImage = makeAgentCompanionImage(
            bubble: bubble,
            style: style,
            frameSize: CGSize(width: frameWidth, height: frameHeight)
        )
        else {
            return nil
        }
        do {
            let texture = try textureLoader.newTexture(
                cgImage: cgImage,
                options: [
                    MTKTextureLoader.Option.SRGB: false,
                    MTKTextureLoader.Option.origin: MTKTextureLoader.Origin.topLeft,
                ]
            )
            agentCompanionTextures[key] = texture
            return texture
        } catch {
            print("[BongoUnifiedMetal] failed to load Agent companion texture \(key): \(error)")
            return nil
        }
    }

    private func makeAgentCompanionImage(
        bubble: AgentCompanionBubble,
        style: AgentCompanionBubbleStyle,
        frameSize: CGSize
    ) -> CGImage? {
        guard let bubbleImage = agentCompanionResourceImage(named: style.resourceName, withExtension: "svg") else {
            return nil
        }
        let pixelWidth = max(Int(frameSize.width.rounded()), 1)
        let pixelHeight = max(Int(frameSize.height.rounded()), 1)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: pixelWidth * 4,
            bitsPerPixel: 32
        ),
              let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        defer { NSGraphicsContext.restoreGraphicsState() }

        let drawRect = CGRect(origin: .zero, size: CGSize(width: pixelWidth, height: pixelHeight))
        graphicsContext.cgContext.clear(drawRect)
        graphicsContext.cgContext.interpolationQuality = .none
        if agentCompanionBubbleFlipped {
            graphicsContext.cgContext.saveGState()
            graphicsContext.cgContext.translateBy(x: CGFloat(pixelWidth), y: 0)
            graphicsContext.cgContext.scaleBy(x: -1, y: 1)
            bubbleImage.draw(
                in: drawRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            graphicsContext.cgContext.restoreGState()
        } else {
            bubbleImage.draw(
                in: drawRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        }

        let iconSize = min(CGFloat(pixelWidth) / 2.2, CGFloat(pixelHeight) / 1.9)
        let iconRect = CGRect(
            x: (CGFloat(pixelWidth) - iconSize) * 0.5,
            y: (CGFloat(pixelHeight) - iconSize) * 0.5 + CGFloat(pixelHeight) * 0.08,
            width: iconSize,
            height: iconSize
        )
        if let iconImage = agentCompanionResourceImage(named: bubble.assetName, withExtension: "png") {
            iconImage.draw(
                in: iconRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        } else {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: iconSize),
                .foregroundColor: NSColor.white,
            ]
            NSString(string: bubble.fallbackIcon).draw(in: iconRect, withAttributes: attributes)
        }
        return bitmap.cgImage
    }

    private func agentCompanionResourceImage(named name: String, withExtension fileExtension: String) -> NSImage? {
        guard let url = LofiiResources.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "AgentCompanion"
        ) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private func loadPNG(resource: String, baseDirectory: URL?) -> MTLTexture? {
        guard let textureLoader, let baseDirectory else { return nil }
        let url = baseDirectory.appendingPathComponent("\(resource).png", isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try textureLoader.newTexture(
                URL: url,
                options: [
                    MTKTextureLoader.Option.SRGB: false,
                    MTKTextureLoader.Option.origin: MTKTextureLoader.Origin.topLeft,
                ]
            )
        } catch {
            print("[BongoUnifiedMetal] failed to load \(resource).png: \(error)")
            return nil
        }
    }

    private func stageRectInPixels(viewportSize: CGSize) -> CGRect {
        guard let view else { return .zero }
        guard let layout = stageLayout(in: view) else { return .zero }
        let scaleX = viewportSize.width / max(layout.container.width, 1)
        let scaleY = viewportSize.height / max(layout.container.height, 1)
        return CGRect(
            x: layout.origin.x * scaleX,
            y: layout.origin.y * scaleY,
            width: layout.stage.width * scaleX,
            height: layout.stage.height * scaleY
        )
    }

    private func cutLineEndpointsInPixels(viewportSize: CGSize) -> (leftY: CGFloat, rightY: CGFloat)? {
        guard let view else { return nil }
        let container = pointsLayoutContainer(view: view)
        guard container.width > 0, container.height > 0 else { return nil }
        let edgeInset = crtSettings.resolvedBongoStageEdgeInset(containerSize: container)
        guard let endpoints = BongoStageLayout.cutLineEndpoints(
            in: container,
            maxStageSize: maxLogicalStageSize,
            placement: effectiveStagePlacement,
            desktopLayout: desktopLayout,
            maxFittedStageHeightFractionOfContainer: maxFittedStageHeightFraction,
            edgeInset: edgeInset
        ) else { return nil }
        let scaleY = viewportSize.height / max(container.height, 1)
        return (endpoints.left.y * scaleY, endpoints.right.y * scaleY)
    }
}

private extension BongoDesktopMaskTint {
    var metalColor: SIMD4<Float> {
        switch self {
        case .black:
            return SIMD4<Float>(5.0 / 255.0, 5.0 / 255.0, 5.0 / 255.0, 1)
        case .ink:
            return SIMD4<Float>(255.0 / 255.0, 255.0 / 255.0, 255.0 / 255.0, 1)
        case .dynamic:
            return SIMD4<Float>(5.0 / 255.0, 5.0 / 255.0, 5.0 / 255.0, 1)
        case .modelDynamic:
            return SIMD4<Float>(5.0 / 255.0, 5.0 / 255.0, 5.0 / 255.0, 1)
        case .hidden:
            return .zero
        }
    }
}

private extension BongoCatPack {
    func keyDirectoryURL(for side: BongoKeyOverlaySide) -> URL? {
        switch side {
        case .left:
            return leftKeysDirectoryURL
        case .right:
            return rightKeysDirectoryURL
        }
    }
}

private struct BongoDesktopLayout: Sendable {
    static let fallback = BongoDesktopLayout(cutLineMidYRatio: 0.5510, cutLineAngleDeg: 9.1)

    let cutLineMidYRatio: CGFloat
    let cutLineAngleDeg: CGFloat

    static func load(for pack: BongoCatPack) -> BongoDesktopLayout {
        guard let url = pack.resourcesDirectoryURL?.appendingPathComponent("desktop-layout.json") else {
            return fallback
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return fallback
        }

        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(File.self, from: data)
            return file.layout ?? fallback
        } catch {
            print("[BongoUnifiedMetal] failed to load desktop-layout.json for \(pack.cacheTag): \(error)")
            return fallback
        }
    }

    private struct File: Decodable {
        let cutLineMidYRatio: Double?
        let cutLineAngleDeg: Double?

        var layout: BongoDesktopLayout? {
            guard
                let cutLineMidYRatio,
                let cutLineAngleDeg,
                cutLineMidYRatio.isFinite,
                cutLineAngleDeg.isFinite,
                (-89.0...89.0).contains(cutLineAngleDeg)
            else {
                return nil
            }
            return BongoDesktopLayout(
                cutLineMidYRatio: CGFloat(cutLineMidYRatio),
                cutLineAngleDeg: CGFloat(cutLineAngleDeg)
            )
        }
    }
}

private enum BongoStageLayout {
    /// Stage coords are stored as ratios so the cut-line slope is constant
    /// across resizes.
    static func cutLineAngleN(for maxStageSize: CGSize, desktopLayout: BongoDesktopLayout) -> CGFloat {
        guard maxStageSize.width > 0, maxStageSize.height > 0 else { return 0 }
        let stageRatio = maxStageSize.width / maxStageSize.height
        return stageRatio * CGFloat(tan(Double(desktopLayout.cutLineAngleDeg) * .pi / 180.0))
    }

    static func fittedStageSize(
        in container: CGSize,
        maxStageSize: CGSize,
        maxFittedStageHeightFractionOfContainer: CGFloat = 1
    ) -> CGSize {
        guard container.width > 0, container.height > 0 else { return .zero }
        guard maxStageSize.width > 0, maxStageSize.height > 0 else { return .zero }

        let hFrac = min(max(maxFittedStageHeightFractionOfContainer, 0), 1)
        let fitHeight = container.height * hFrac
        guard fitHeight > 0 else { return .zero }
        let fitContainer = CGSize(width: container.width, height: fitHeight)

        let stageRatio = maxStageSize.width / maxStageSize.height
        var width: CGFloat
        var height: CGFloat

        if fitContainer.width / fitContainer.height >= stageRatio {
            height = fitContainer.height
            width = height * stageRatio
        } else {
            width = fitContainer.width
            height = width / stageRatio
        }

        if width > maxStageSize.width || height > maxStageSize.height {
            let cap = min(maxStageSize.width / width, maxStageSize.height / height, 1)
            width *= cap
            height *= cap
        }

        // Fit inside the SwiftUI height budget × width (guards float / branch edge cases).
        let sx = fitContainer.width > 0 ? fitContainer.width / max(width, .leastNonzeroMagnitude) : 1
        let sy = fitHeight > 0 ? fitHeight / max(height, .leastNonzeroMagnitude) : 1
        let fitBox = min(sx, sy, 1)
        width *= fitBox
        height *= fitBox

        return CGSize(width: round(width), height: round(height))
    }

    static func stageOrigin(in container: CGSize, stage: CGSize, anchor: BongoStageAnchor, edgeInset: CGFloat) -> CGPoint {
        let m = max(0, edgeInset)
        let maxX = max(0, container.width - stage.width)
        let maxY = max(0, container.height - stage.height)
        let cx = maxX / 2
        let cy = maxY / 2
        switch anchor {
        case .leading:
            return CGPoint(x: min(m, maxX), y: cy)
        case .center:
            return CGPoint(x: cx, y: cy)
        case .trailing:
            return CGPoint(x: max(0, maxX - m), y: cy)
        case .bottomLeading:
            return CGPoint(x: min(m, maxX), y: max(0, maxY - m))
        case .bottom:
            return CGPoint(x: cx, y: max(0, maxY - m))
        case .bottomTrailing:
            return CGPoint(x: max(0, maxX - m), y: max(0, maxY - m))
        }
    }

    static func stageOrigin(in container: CGSize, stage: CGSize, placement: BongoStagePlacement, edgeInset: CGFloat) -> CGPoint {
        if let customOriginRatio = placement.customOriginRatio {
            return customOriginRatio.resolvedOrigin(in: container, stage: stage)
        }
        return stageOrigin(in: container, stage: stage, anchor: placement.anchor, edgeInset: edgeInset)
    }

    static func stageCenter(in container: CGSize, stage: CGSize, anchor: BongoStageAnchor, edgeInset: CGFloat) -> CGPoint {
        let origin = stageOrigin(in: container, stage: stage, anchor: anchor, edgeInset: edgeInset)
        return CGPoint(
            x: origin.x + stage.width / 2,
            y: origin.y + stage.height / 2
        )
    }

    /// Returns the cut-line endpoints in *container* coordinates, extended to the
    /// container's full width so the mask polygon meets the viewport sides when
    /// the stage is narrower than the container.
    static func cutLineEndpoints(
        in container: CGSize,
        maxStageSize: CGSize,
        placement: BongoStagePlacement,
        desktopLayout: BongoDesktopLayout,
        maxFittedStageHeightFractionOfContainer: CGFloat = 1,
        edgeInset: CGFloat
    ) -> (left: CGPoint, right: CGPoint)? {
        let stage = fittedStageSize(
            in: container,
            maxStageSize: maxStageSize,
            maxFittedStageHeightFractionOfContainer: maxFittedStageHeightFractionOfContainer
        )
        guard stage.width > 0, stage.height > 0 else { return nil }

        let stageOrigin = stageOrigin(in: container, stage: stage, placement: placement, edgeInset: edgeInset)
        let halfDy = (cutLineAngleN(for: maxStageSize, desktopLayout: desktopLayout) * stage.height) / 2
        let midY = desktopLayout.cutLineMidYRatio * stage.height
        // Stage-local cut-line endpoints (left edge x=0, right edge x=stageW).
        let stageY0 = midY - halfDy
        let stageY1 = midY + halfDy
        // Lift to container coords.
        let vx0 = stageOrigin.x
        let vy0 = stageOrigin.y + stageY0
        let vx1 = stageOrigin.x + stage.width
        let vy1 = stageOrigin.y + stageY1
        let dx = vx1 - vx0
        if abs(dx) < 1e-6 {
            return (CGPoint(x: 0, y: vy0), CGPoint(x: container.width, y: vy0))
        }
        let m = (vy1 - vy0) / dx
        let yLeft = vy0 + m * (0 - vx0)
        let yRight = vy0 + m * (container.width - vx0)
        return (CGPoint(x: 0, y: yLeft), CGPoint(x: container.width, y: yRight))
    }

    /// Live2D stage rectangle in the same coordinate system as `container` (typically a widget `bounds.size`).
    static func live2DStageFrame(
        in container: CGSize,
        maxStageSize: CGSize,
        placement: BongoStagePlacement,
        maxFittedStageHeightFractionOfContainer: CGFloat = 1,
        edgeInset: CGFloat
    ) -> CGRect {
        let stage = fittedStageSize(
            in: container,
            maxStageSize: maxStageSize,
            maxFittedStageHeightFractionOfContainer: maxFittedStageHeightFractionOfContainer
        )
        let origin = stageOrigin(in: container, stage: stage, placement: placement, edgeInset: edgeInset)
        return CGRect(origin: origin, size: stage)
    }
}

/// Exposes Live2D stage geometry to other modules (e.g. wheel hit-through) without widening `BongoStageLayout` visibility.
enum BongoLive2DHitGeometry {
    static func live2DStageFrame(
        in container: CGSize,
        maxStageSize: CGSize,
        placement: BongoStagePlacement,
        maxFittedStageHeightFractionOfContainer: CGFloat = 1,
        crt: CRTSettings
    ) -> CGRect {
        let edgeInset = crt.resolvedBongoStageEdgeInset(containerSize: container)
        return BongoStageLayout.live2DStageFrame(
            in: container,
            maxStageSize: maxStageSize,
            placement: placement,
            maxFittedStageHeightFractionOfContainer: maxFittedStageHeightFractionOfContainer,
            edgeInset: edgeInset
        )
    }

    /// AppKit `NSView.hitTest(_:)` uses a bottom-left coordinate space here, while
    /// Bongo stage layout is expressed in the top-left render/layout space.
    static func appKitLive2DStageFrame(
        in container: CGSize,
        maxStageSize: CGSize,
        placement: BongoStagePlacement,
        maxFittedStageHeightFractionOfContainer: CGFloat = 1,
        crt: CRTSettings
    ) -> CGRect {
        let frame = live2DStageFrame(
            in: container,
            maxStageSize: maxStageSize,
            placement: placement,
            maxFittedStageHeightFractionOfContainer: maxFittedStageHeightFractionOfContainer,
            crt: crt
        )
        guard container.height > 0 else { return frame }
        return CGRect(
            x: frame.minX,
            y: container.height - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }
}

// MARK: - BongoCoordinator

@MainActor
final class BongoCoordinator: ObservableObject {
    private var nativeRenderer: CubismNativeMetalRenderer?
    private let modelDirectory: URL?
    private let modelJSON: String

    /// Image stems (e.g. "KeyQ", "Space") of keys currently held down; drawn by `BongoUnifiedMetalRenderer`.
    @Published var pressedKeyImages: Set<String> = []

    private let supportedKeyImages: Set<BongoKeyOverlay>
    /// Optional `resources/bongo-parameter-map.json`: maps app-side IDs (e.g. `CatParamRightHandDown`) to this model’s Live2D parameter `Id` strings when imported MOCs use different names.
    private let parameterRemap: [String: String]
    /// Optional `resources/bongo-arrow-overlay-params.json`: key stem -> extra MOC param Id while that overlay is held.
    private let arrowOverlayAccessoryParamByStem: [String: String]
    private var monitor: BongoInputMonitor?
    private var isModelLoaded = false
    private var pendingPlay = true
    private var pendingParamValues: [String: Double] = [:]
    /// Repeating timer: mouse reconciliation + cursor ratios, then batched Live2D params.
    private var inputTickTimer: Timer?
    private var inputTickInterval: TimeInterval
    /// How pointer position maps to `ParamMouseX` / `ParamMouseY` (single display vs full desktop).
    private var mouseCursorSpace: BongoMouseCursorSpace
    /// Random motions while the overlay is live.
    private var randomIdleMotionTimer: Timer?

    var bongoModelIsReady: Bool { isNativeReady || isModelLoaded }
    var isNativeReady: Bool { nativeRenderer?.isCubismReady ?? false }

    init(
        pack: BongoCatPack,
        inputTickInterval: TimeInterval = 1.0 / 60.0,
        mouseCursorSpace: BongoMouseCursorSpace = .allDisplays
    ) {
        self.inputTickInterval = max(1.0 / 120.0, min(inputTickInterval, 0.5))
        self.mouseCursorSpace = mouseCursorSpace
        supportedKeyImages = Self.loadSupportedKeyImages(for: pack)
        parameterRemap = Self.loadParameterRemap(for: pack)
        arrowOverlayAccessoryParamByStem = Self.loadArrowOverlayAccessoryMap(for: pack)

        switch pack {
        case .bundled(let kind):
            modelJSON = BongoCatModelKind.modelSettingFileName
            let mocURL = LofiiResources.bundle.url(
                forResource: kind.mocStem,
                withExtension: "moc3",
                subdirectory: "BongoCat/\(kind.bundleFolderName)"
            )
            _ = CubismNativeBootstrap.prepareBundledBongoModel(mocURL: mocURL)
            modelDirectory = LofiiResources.bundle.url(
                forResource: kind.bundleFolderName,
                withExtension: nil,
                subdirectory: "BongoCat"
            )

        case .imported(let folderName):
            let root = BongoCatPack.importedPackRoot(folderName: folderName)
            let jsonName = pack.resolvedModel3JSONFileName() ?? BongoCatModelKind.modelSettingFileName
            modelJSON = jsonName
            let mocURL = BongoCatPack.mocURL(modelRoot: root, model3FileName: jsonName)
            _ = CubismNativeBootstrap.prepareBundledBongoModel(mocURL: mocURL)
            modelDirectory = root
        }
    }

    func ensureNativeRenderer(device: MTLDevice) -> CubismNativeMetalRenderer? {
        if let nativeRenderer {
            return nativeRenderer
        }
        guard let modelDirectory else { return nil }
        let renderer = CubismNativeMetalRenderer(
            device: device,
            modelDirectory: modelDirectory.path,
            modelJSON: modelJSON
        )
        nativeRenderer = renderer
        return renderer
    }

    func resizeNativeRenderer(width: Int, height: Int) {
        nativeRenderer?.resize(toWidth: UInt(max(width, 1)), height: UInt(max(height, 1)))
    }

    func modelDrawRectForStageRect(_ stageRect: CGRect) -> CGRect {
        nativeRenderer?.modelDrawRect(forStageRect: stageRect) ?? stageRect
    }

    func drawNativeRenderer(
        commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        viewport: MTLViewport,
        deltaTime: TimeInterval
    ) {
        nativeRenderer?.draw(
            with: commandBuffer,
            renderPassDescriptor: renderPassDescriptor,
            viewport: viewport,
            deltaTime: deltaTime
        )
    }

    /// Starts a random Live2D motion on tap. Returns `false` if a motion is already playing or Cubism is not ready.
    @discardableResult
    func tryStartRandomTapMotionIfNotBusy() -> Bool {
        guard let nativeRenderer else {
            NSLog("[BongoTap] native renderer missing")
            return false
        }
        let started = nativeRenderer.tryStartRandomTapMotion()
        NSLog("[BongoTap] native renderer tryStartRandomTapMotion returned %@", started ? "true" : "false")
        return started
    }

    /// Starts an idle Live2D motion. Imported packs use their declared `idle`/`Idle` group when present;
    /// otherwise the native renderer falls back to any recognized `.motion3.json`.
    @discardableResult
    func tryStartRandomIdleMotionIfNotBusy() -> Bool {
        guard let nativeRenderer else { return false }
        return nativeRenderer.tryStartRandomIdleMotion()
    }

    /// Called from `BongoUnifiedMetalRenderer.attach` once the Metal device exists.
    /// `workspaceReady` comes from SwiftUI (`BongoUnifiedMetalView.onLive2DWorkspaceReady`), same idea as
    /// `StageMetalPlayerView.onFirstFrameReady` — never rely on a coordinator property assigned in `onAppear`.
    ///
    /// **Always** invokes `workspaceReady` even when `isModelLoaded` is already true: SwiftUI can tear down
    /// and recreate the `MTKView` while this coordinator stays alive (`StateObject`), and `AppModel` may have
    /// just called `markBongoLive2DPending()` for a pack swap — the gate must be lifted again on every attach.
    func ensureModelReadyFromNative(workspaceReady: @escaping () -> Void) {
        if !isModelLoaded {
            isModelLoaded = true
            if pendingPlay {
                startMonitor()
            }
        }
        workspaceReady()
    }

    func setPlaying(_ playing: Bool) {
        pendingPlay = playing
        guard isModelLoaded else { return }
        if playing {
            startMonitor()
        } else {
            stopMonitor()
        }
    }

    /// Call when `AppModel.bongoInputTickRate` changes while the input monitor may be active.
    func applyInputTickRate(_ rate: BongoInputTickRate) {
        let next = max(1.0 / 120.0, min(rate.timeInterval, 0.5))
        guard abs(next - inputTickInterval) > 1e-9 else { return }
        inputTickInterval = next
        guard inputTickTimer != nil else { return }
        stopInputTickTimer()
        startInputTickTimer()
    }

    func applyMouseCursorSpace(_ space: BongoMouseCursorSpace) {
        guard mouseCursorSpace != space else { return }
        mouseCursorSpace = space
    }

    func tearDown() {
        stopMonitor()
        pendingParamValues.removeAll(keepingCapacity: false)
        nativeRenderer = nil
        isModelLoaded = false
    }

    // MARK: Private

    private func startMonitor() {
        guard monitor == nil else { return }
        let m = BongoInputMonitor(
            paramCallback: { [weak self] params in self?.sendParams(params) },
            keyCallback:   { [weak self] name, pressed in self?.sendKeyEvent(name, pressed: pressed) },
            supportedKeyImages: supportedKeyImages,
            overlayAccessoryLive2DParamByStem: arrowOverlayAccessoryParamByStem
        )
        m.start()
        monitor = m
        startInputTickTimer()
        scheduleRandomIdleMotionTimer()
    }

    private func stopMonitor() {
        cancelRandomIdleMotionTimer()
        stopInputTickTimer()
        monitor?.stop()
        monitor = nil
        flushPendingParams()
        if !pressedKeyImages.isEmpty {
            pressedKeyImages.removeAll()
        }
    }

    private func sendParams(_ params: [(String, Double)]) {
        guard !params.isEmpty else { return }
        for (id, value) in params {
            pendingParamValues[id] = value
        }
        if inputTickTimer == nil {
            flushPendingParams()
        }
    }

    private func startInputTickTimer() {
        guard inputTickTimer == nil else { return }
        runInputTick()
        let timer = Timer(timeInterval: inputTickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.runInputTick()
            }
        }
        timer.tolerance = min(inputTickInterval * 0.2, 0.01)
        RunLoop.main.add(timer, forMode: .common)
        inputTickTimer = timer
    }

    private func stopInputTickTimer() {
        inputTickTimer?.invalidate()
        inputTickTimer = nil
    }

    private static let randomIdleMotionMinInterval: TimeInterval = 300
    private static let randomIdleMotionMaxInterval: TimeInterval = 420

    private func scheduleRandomIdleMotionTimer() {
        cancelRandomIdleMotionTimer()
        let delay = TimeInterval.random(in: Self.randomIdleMotionMinInterval ... Self.randomIdleMotionMaxInterval)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fireRandomIdleMotionIfEligible()
                self?.scheduleRandomIdleMotionTimer()
            }
        }
        timer.tolerance = delay * 0.12
        RunLoop.main.add(timer, forMode: .common)
        randomIdleMotionTimer = timer
        NSLog("[BongoIdle] scheduled random idle motion in %.1fs", delay)
    }

    private func cancelRandomIdleMotionTimer() {
        randomIdleMotionTimer?.invalidate()
        randomIdleMotionTimer = nil
    }

    /// Random autoplay only when input monitor is active, keys are not showing overlays, and Cubism can accept a motion.
    private func fireRandomIdleMotionIfEligible() {
        guard monitor != nil else {
            NSLog("[BongoIdle] skipped: monitor inactive")
            return
        }
        guard pressedKeyImages.isEmpty else {
            NSLog("[BongoIdle] skipped: key overlay active")
            return
        }
        let started = tryStartRandomIdleMotionIfNotBusy()
        NSLog("[BongoIdle] fired random idle motion started=%@", started ? "true" : "false")
    }

    private func runInputTick() {
        pollMouseCursor()
        flushPendingParams()
    }

    private func pollMouseCursor() {
        monitor?.reconcilePressedMouseButtons()

        guard isNativeReady else { return }

        let pos = NSEvent.mouseLocation
        switch mouseCursorSpace {
        case .allDisplays:
            guard let desktop = Self.unifiedDesktopFrame(), desktop.width > 0, desktop.height > 0 else { return }
            let xRatio = max(0.0, min(1.0, (pos.x - desktop.minX) / desktop.width))
            let yRatio = max(0.0, min(1.0, 1.0 - ((pos.y - desktop.minY) / desktop.height)))
            nativeRenderer?.applyMouseCursorXRatio(Double(xRatio), yRatio: Double(yRatio), mouseMirror: false)
        case .currentDisplay:
            guard let screen = Self.screenForGlobalMouseLocation(pos),
                  screen.frame.width > 0, screen.frame.height > 0
            else { return }
            let frame = screen.frame
            let xRatio = max(0.0, min(1.0, (pos.x - frame.minX) / frame.width))
            // AppKit screen coordinates are bottom-left; upstream BongoCat maps
            // mouse input in top-left monitor coordinates.
            let yRatio = max(0.0, min(1.0, 1.0 - ((pos.y - frame.minY) / frame.height)))
            nativeRenderer?.applyMouseCursorXRatio(Double(xRatio), yRatio: Double(yRatio), mouseMirror: false)
        }
    }

    /// Bounding box of every online display in global desktop coords (`NSEvent.mouseLocation` space).
    private static func unifiedDesktopFrame() -> CGRect? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return NSScreen.main?.frame }
        return screens.reduce(CGRect.null) { $0.union($1.frame) }
    }

    /// Display under the cursor for per-screen normalization (`BongoMouseCursorSpace.currentDisplay`).
    private static func screenForGlobalMouseLocation(_ location: NSPoint) -> NSScreen? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 1)
        var displayCount: UInt32 = 0
        let cgPoint = CGPoint(x: location.x, y: location.y)
        if CGGetDisplaysWithPoint(cgPoint, 1, &displays, &displayCount) == .success, displayCount > 0 {
            let id = displays[0]
            if let match = NSScreen.screens.first(where: { screenDirectDisplayID($0) == id }) {
                return match
            }
        }
        if let match = NSScreen.screens.first(where: { $0.frame.contains(location) }) {
            return match
        }
        return nearestScreen(to: location) ?? NSScreen.main
    }

    private static func screenDirectDisplayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        return CGDirectDisplayID(num.uint32Value)
    }

    private static func nearestScreen(to location: NSPoint) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        return screens.min {
            squaredDistance(from: location, to: $0.frame) < squaredDistance(from: location, to: $1.frame)
        }
    }

    private static func squaredDistance(from point: NSPoint, to rect: CGRect) -> CGFloat {
        let dx: CGFloat
        if point.x < rect.minX { dx = rect.minX - point.x }
        else if point.x > rect.maxX { dx = point.x - rect.maxX }
        else { dx = 0 }
        let dy: CGFloat
        if point.y < rect.minY { dy = rect.minY - point.y }
        else if point.y > rect.maxY { dy = point.y - rect.maxY }
        else { dy = 0 }
        return dx * dx + dy * dy
    }

    private func flushPendingParams() {
        guard !pendingParamValues.isEmpty else { return }
        guard isNativeReady else { return }
        let nativeParams = pendingParamValues.reduce(into: [String: NSNumber]()) { partialResult, entry in
            let key = parameterRemap[entry.key] ?? entry.key
            partialResult[key] = NSNumber(value: entry.value)
        }
        pendingParamValues.removeAll(keepingCapacity: true)
        nativeRenderer?.applyParameterValues(nativeParams)
    }

    private func sendKeyEvent(_ imageName: String, pressed: Bool) {
        if pressed {
            pressedKeyImages.removeAll(keepingCapacity: true)
            if pressedKeyImages.insert(imageName).inserted == false { return }
        } else {
            if pressedKeyImages.remove(imageName) == nil { return }
        }
    }

    private static func loadSupportedKeyImages(for pack: BongoCatPack) -> Set<BongoKeyOverlay> {
        var overlays = Set<BongoKeyOverlay>()
        for side in [BongoKeyOverlaySide.left, .right] {
            guard let directoryURL = pack.keyDirectoryURL(for: side) else { continue }
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []

            for url in urls where url.pathExtension == "png" {
                overlays.insert(BongoKeyOverlay(side: side, stem: url.deletingPathExtension().lastPathComponent))
            }
        }
        return overlays
    }

    /// JSON object of string → string, e.g. `{ "CatParamRightHandDown": "YourModelParamId" }`.
    private static func loadParameterRemap(for pack: BongoCatPack) -> [String: String] {
        guard let url = pack.resourcesDirectoryURL?.appendingPathComponent("bongo-parameter-map.json", isDirectory: false),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded
    }

    /// JSON object: key overlay stem → MOC parameter Id to drive while overlay key is held.
    private static func loadArrowOverlayAccessoryMap(for pack: BongoCatPack) -> [String: String] {
        guard let url = pack.resourcesDirectoryURL?.appendingPathComponent("bongo-arrow-overlay-params.json", isDirectory: false),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded
    }
}
