import SwiftUI

struct SceneView: View {
    let asset: SceneAsset
    let variant: SceneVariant
    let isPlaying: Bool
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

    @State private var localURL: URL?
    @State private var loadError: String?
    /// A random pre-cached "snow" frame from `GifCache` that we lay on top
    /// of the video while a new variant is swapping in. Same idiom as the
    /// gif mode — turns scene/variant changes into a tv-style channel flip
    /// instead of a hard cut to the gradient backdrop.
    @State private var transitionStaticURL: URL?
    @State private var transitionSnowOpacity: Double = 1
    @State private var darkFieldOpacity: Double = 0
    @State private var startupSnowURL: URL?
    @State private var startupSnowOpacity: Double = 1
    @State private var startupSnowClearing = false
    /// Tracks which `cacheKey` we last saw so we know to fire the snow
    /// transition exactly once per real swap (not on every body re-render).
    @State private var lastSeenKey: String?

    init(
        asset: SceneAsset,
        variant: SceneVariant,
        isPlaying: Bool,
        curvationFactor: Double = 0,
        curvationOverscan: Double = 1,
        curvationBorderSize: Double = 0,
        vignetteAlpha: Double = 0,
        motionBlurEnabled: Bool = false,
        motionBlurStrength: Double = MotionBlurStrength.balanced.resolvedStrength,
        chromaticAberrationEnabled: Bool = false,
        chromaticAberrationStrength: Double = ChromaticAberrationStrength.balanced.resolvedStrength,
        scanlinesEnabled: Bool = false,
        scanlineOpacity: Double = 0,
        scanlineDensity: Double = ScanlineDensity.balanced.pitch,
        shatteredGlassOpacity: Double = 0,
        shatteredGlassRefraction: Double = 0,
        shatteredGlassHighlight: Double = 0,
        shatteredGlassFlipX: Double = 0
    ) {
        self.asset = asset
        self.variant = variant
        self.isPlaying = isPlaying
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
        // Pre-fill `localURL` synchronously from the on-disk cache so the
        // first rendered frame already has the video in it. Without this,
        // SwiftUI's `.task` is scheduled for the next runloop tick — which
        // means the very first body() call paints the gradient backdrop
        // alone, and only the *second* frame gets the video. Cross-faded
        // through `.animation(value: localURL)` that produced a visible
        // "bright → dark" flash whenever the user toggled from gif → video
        // mode (because the backdrop colors are typically much brighter
        // than the dim cinematic frames).
        let cached = SceneVideoCache.cachedURLIfAvailable(for: asset, variant: variant)
        _localURL = State(initialValue: cached)
        // `nil` on first launch so `loadVideoCoveringWithSnow` does not hit the
        // fast-return while startup snow is still waiting for Metal/AV — that
        // path matches `GifSceneView` / Bongo background loading.
        _lastSeenKey = State(initialValue: nil)
        // No video on disk yet: show bundled snow immediately (no empty frame
        // before `.task` runs) instead of a spinner or bare gradient.
        _transitionStaticURL = State(
            initialValue: cached == nil ? GifCache.startupSnowOverlayURL : nil
        )
        // A cached video can still draw one or more empty Metal frames before
        // AVPlayerItemVideoOutput provides its first pixel buffer. Cover that
        // startup gap with TV snow instead of exposing the player's black fallback.
        _startupSnowURL = State(
            initialValue: cached != nil ? GifCache.startupSnowOverlayURL : nil
        )
    }

    var body: some View {
        ZStack {
            // Dim palette behind video / snow — only visible in gaps between layers.
            LinearGradient(
                colors: [asset.palette.backdropTop, asset.palette.backdropBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            if let localURL {
                StageMetalPlayerView(
                    source: .video(localURL),
                    isPlaying: isPlaying,
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
                    onFirstFrameReady: {
                        clearStartupSnowAfterFirstFrame()
                    }
                )
                    .transition(.opacity)
            }

            if let startupSnowURL {
                SnowOverlayView(url: startupSnowURL)
                    .opacity(startupSnowOpacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }

            // Random static snow until the target mp4 is ready (and a short
            // minimum beat on fast cache hits — TV channel-flip, not a spinner).
            if let transitionStaticURL {
                SnowOverlayView(url: transitionStaticURL)
                    .opacity(transitionSnowOpacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }

            Color.black
                .opacity(darkFieldOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            if let loadError {
                VStack(spacing: 6) {
                    // Pixel-style error glyph + readout to match the rest
                    // of the chrome. `cellularSignalOff` is the closest
                    // pixelarticons has to "no network".
                    PixelIcon(.signalOff, size: 18)
                    Text(loadError)
                        .font(.pixel(size: 12))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding(10)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .animation(.easeInOut(duration: 0.45), value: localURL)
        .task(id: cacheKey) {
            await loadVideoCoveringWithSnow()
        }
    }

    private var cacheKey: String {
        "\(asset.id)/\(variant.rawValue)"
    }

    @MainActor
    private func clearStartupSnowAfterFirstFrame() {
        guard startupSnowURL != nil, !startupSnowClearing else { return }
        startupSnowClearing = true
        withAnimation(.easeOut(duration: TransitionSnowStyle.fadeInDuration)) {
            startupSnowOpacity = 0
        }
        Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64(TransitionSnowStyle.fadeInDuration * 1_000_000_000)
            )
            startupSnowURL = nil
            startupSnowOpacity = 1
            startupSnowClearing = false
        }
    }

    /// Snow stays up until the scene mp4 for `cacheKey` is local; no separate
    /// loading indicator. After a cache hit, holds snow briefly for a channel-flip read.
    @MainActor
    private func loadVideoCoveringWithSnow() async {
        if let cached = SceneVideoCache.cachedURLIfAvailable(for: asset, variant: variant),
           localURL == cached,
           lastSeenKey == cacheKey {
            loadError = nil
            darkFieldOpacity = 0
            transitionSnowOpacity = 1
            transitionStaticURL = nil
            return
        }

        if let snow = await GifCache.shared.randomCachedStatic() {
            transitionStaticURL = snow
        } else if transitionStaticURL == nil {
            transitionStaticURL = GifCache.bundledSnowOverlayURL()
        }
        TransitionSnowStyle.fadeInSnowOpacity { transitionSnowOpacity = $0 }

        let keyChanged = lastSeenKey != nil && lastSeenKey != cacheKey
        lastSeenKey = cacheKey

        if let cached = SceneVideoCache.cachedURLIfAvailable(for: asset, variant: variant) {
            if localURL != cached {
                var tx = Transaction()
                tx.disablesAnimations = true
                withTransaction(tx) {
                    self.localURL = cached
                }
            }
            loadError = nil
        } else {
            self.localURL = nil
            loadError = nil
            do {
                let url = try await SceneVideoCache.shared.ensureLocalVideo(for: asset, variant: variant)
                guard !Task.isCancelled else {
                    darkFieldOpacity = 0
                    transitionSnowOpacity = 1
                    transitionStaticURL = nil
                    return
                }
                self.localURL = url
            } catch {
                guard !Task.isCancelled else {
                    darkFieldOpacity = 0
                    transitionSnowOpacity = 1
                    transitionStaticURL = nil
                    return
                }
                self.localURL = nil
                self.loadError = "Scene unavailable"
            }
        }

        guard !Task.isCancelled else {
            darkFieldOpacity = 0
            transitionSnowOpacity = 1
            transitionStaticURL = nil
            return
        }

        if loadError != nil {
            darkFieldOpacity = 0
            transitionSnowOpacity = 1
            transitionStaticURL = nil
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
            transitionStaticURL = nil
            return
        }
        await TransitionSnowStyle.darkFieldCoverThenClearSnow(
            setDarkField: { darkFieldOpacity = $0 },
            clearSnowURL: { transitionStaticURL = nil },
            resetSnowOpacity: { transitionSnowOpacity = 1 }
        )
    }
}
