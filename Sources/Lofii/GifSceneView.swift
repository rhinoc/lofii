import SwiftUI
import AppKit
@preconcurrency import ImageIO

// MARK: - GifSceneView

struct GifSceneView: View {
    let asset: GifAsset
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
    /// Called when the animated GIF file is ready to reveal (snow may still
    /// be visible for a forced beat after a catalog switch).
    var onAnimatedGifReady: (() -> Void)? = nil

    @State private var localURL: URL?
    @State private var transitionSnowURL: URL?
    @State private var transitionSnowOpacity: Double = 1
    @State private var darkFieldOpacity: Double = 0
    @State private var startupSnowURL: URL?
    @State private var startupSnowOpacity: Double = 1
    @State private var startupSnowClearing = false
    @State private var firstFrameReadyURL: URL?
    /// Last `asset.id` for which `loadGif()` finished successfully.
    @State private var lastSettledAssetId: String?
    @State private var loadError: String?

    init(
        asset: GifAsset,
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
        shatteredGlassFlipX: Double = 0,
        onAnimatedGifReady: (() -> Void)? = nil
    ) {
        self.asset = asset
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
        self.onAnimatedGifReady = onAnimatedGifReady
        let cached = GifCache.cachedURLIfAvailable(for: asset)
        _localURL = State(initialValue: cached)
        _lastSettledAssetId = State(initialValue: nil)
        _transitionSnowURL = State(initialValue: cached == nil ? GifCache.startupSnowOverlayURL : nil)
        _startupSnowURL = State(initialValue: cached != nil ? GifCache.startupSnowOverlayURL : nil)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.05), Color(white: 0.12)],
                startPoint: .top,
                endPoint: .bottom
            )

            if let localURL {
                StageMetalPlayerView(
                    source: .gif(localURL),
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
                        markAnimatedGifFirstFrameReady(for: localURL)
                    }
                )
                    .id(localURL)
            }

            if let startupSnowURL {
                SnowOverlayView(url: startupSnowURL)
                    .opacity(startupSnowOpacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }

            // Snow uses `isPlaying: true` so multi-frame “static” GIFs still
            // decode (same as legacy `AnimatedImageView`); `isPlaying: false`
            // skips `startDecodeLoop()` for frameCount > 1 → black layer.
            if let transitionSnowURL {
                SnowOverlayView(url: transitionSnowURL)
                    .opacity(transitionSnowOpacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }

            Color.black
                .opacity(darkFieldOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            if let loadError {
                VStack(spacing: 4) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 16, weight: .bold))
                    Text(loadError)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding(10)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .task(id: asset.id) {
            await loadGif()
        }
    }

    @MainActor
    private func markAnimatedGifFirstFrameReady(for url: URL) {
        guard firstFrameReadyURL != url else { return }
        firstFrameReadyURL = url
        onAnimatedGifReady?()
        clearStartupSnowAfterFirstFrame()
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

    @MainActor
    private func waitForAnimatedGifFirstFrame(url: URL) async {
        while firstFrameReadyURL != url && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
    }

    @MainActor
    private func loadGif() async {
        loadError = nil
        let diskCached = GifCache.cachedURLIfAvailable(for: asset)

        if let diskCached,
           localURL == diskCached,
           lastSettledAssetId == asset.id {
            darkFieldOpacity = 0
            transitionSnowOpacity = 1
            transitionSnowURL = nil
            return
        }

        if let diskCached,
           localURL == diskCached,
           lastSettledAssetId == nil {
            lastSettledAssetId = asset.id
            darkFieldOpacity = 0
            transitionSnowOpacity = 1
            transitionSnowURL = nil
            return
        }

        let keyChanged = lastSettledAssetId != nil && lastSettledAssetId != asset.id

        if transitionSnowURL == nil {
            if let snow = await GifCache.shared.randomCachedStatic() {
                transitionSnowURL = snow
            } else {
                transitionSnowURL = GifCache.startupSnowOverlayURL
            }
        }
        TransitionSnowStyle.fadeInSnowOpacity { transitionSnowOpacity = $0 }

        if let diskCached {
            localURL = diskCached
            lastSettledAssetId = asset.id
            loadError = nil
        } else {
            localURL = nil
            loadError = nil
            do {
                let url = try await GifCache.shared.ensureLocal(for: asset)
                guard !Task.isCancelled else {
                    darkFieldOpacity = 0
                    transitionSnowOpacity = 1
                    transitionSnowURL = nil
                    return
                }
                localURL = url
                lastSettledAssetId = asset.id
            } catch {
                guard !Task.isCancelled else {
                    darkFieldOpacity = 0
                    transitionSnowOpacity = 1
                    transitionSnowURL = nil
                    return
                }
                localURL = nil
                loadError = "GIF unavailable"
                onAnimatedGifReady?()
            }
        }

        guard !Task.isCancelled else {
            darkFieldOpacity = 0
            transitionSnowOpacity = 1
            transitionSnowURL = nil
            return
        }

        if loadError != nil {
            darkFieldOpacity = 0
            transitionSnowOpacity = 1
            transitionSnowURL = nil
            return
        }

        if let localURL {
            await waitForAnimatedGifFirstFrame(url: localURL)
        }
        guard !Task.isCancelled else {
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
    }
}

// MARK: - SnowOverlayView

/// Synchronous first-frame fallback underneath the bundled static GIF. The GIF
/// animation can take a frame or two to decode, but its first image is loaded
/// immediately from the same local file so the startup cover never exposes the
/// black player fallback.
struct SnowOverlayView: View {
    let url: URL?
    @State private var firstFrameDimmed = false

    var body: some View {
        ZStack {
            if let url {
                GifFirstFrameView(url: url)
                GifPlayerView(url: url, isPlaying: true)
                    .id(url)
            }
        }
        .opacity(firstFrameDimmed ? 0.68 : 1)
        .onAppear {
            startBreathing()
        }
        .onChange(of: url) { _, _ in
            startBreathing()
        }
    }

    private func startBreathing() {
        firstFrameDimmed = false
        withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) {
            firstFrameDimmed = true
        }
    }
}

private struct GifFirstFrameView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> GifFirstFrameHostView {
        let view = GifFirstFrameHostView()
        view.load(url: url)
        return view
    }

    func updateNSView(_ nsView: GifFirstFrameHostView, context: Context) {
        if nsView.currentURL != url {
            nsView.load(url: url)
        }
    }
}

final class GifFirstFrameHostView: NSView {
    private(set) var currentURL: URL?
    private let imageLayer = CALayer()
    private var imagePixelSize: CGSize = .zero
    private var lastLayoutBounds: CGRect = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    override var intrinsicContentSize: NSSize { .zero }

    private func setUp() {
        wantsLayer = true
        let root = CALayer()
        root.backgroundColor = NSColor.clear.cgColor
        root.masksToBounds = true
        layer = root

        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.addSublayer(imageLayer)
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        guard bounds != lastLayoutBounds else { return }
        lastLayoutBounds = bounds
        updateImageFrame()
    }

    func load(url: URL) {
        currentURL = url
        let firstFrame = Self.firstFrameImage(url: url)
        imagePixelSize = firstFrame.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
        imageLayer.contents = firstFrame
        updateImageFrame()
    }

    private func updateImageFrame() {
        let container = bounds.size
        guard container.width > 0, container.height > 0 else { return }

        let target: CGSize
        if imagePixelSize.width > 0, imagePixelSize.height > 0 {
            let scale = max(
                container.width / imagePixelSize.width,
                container.height / imagePixelSize.height
            )
            target = CGSize(width: imagePixelSize.width * scale, height: imagePixelSize.height * scale)
        } else {
            target = container
        }

        let origin = CGPoint(
            x: (container.width - target.width) / 2,
            y: (container.height - target.height) / 2
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = CGRect(origin: origin, size: target)
        CATransaction.commit()
    }

    private static func firstFrameImage(url: URL) -> CGImage? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCache: true,
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary)
        else { return nil }
        return cgImage
    }
}

// MARK: - GifPlayerView

/// SwiftUI wrapper for the CALayer-based GIF player. Each instance owns
/// exactly one `GifPlayerLayer`, which decodes frames on a background
/// thread and blits CGImages onto the CALayer. No NSImageView involved.
struct GifPlayerView: NSViewRepresentable {
    let url: URL
    let isPlaying: Bool

    func makeNSView(context: Context) -> GifHostView {
        let view = GifHostView()
        view.load(url: url)
        view.setPlaying(isPlaying)
        return view
    }

    func updateNSView(_ nsView: GifHostView, context: Context) {
        // `url` never changes for a given instance because GifSceneView
        // uses `.id(url)` — but guard anyway for correctness.
        if nsView.currentURL != url {
            nsView.load(url: url)
        }
        // Diff-guard: avoid touching the player on every SwiftUI pass.
        if nsView.isPlaying != isPlaying {
            nsView.setPlaying(isPlaying)
        }
    }

    static func dismantleNSView(_ nsView: GifHostView, coordinator: ()) {
        nsView.tearDown()
    }
}

// MARK: - GifHostView

/// NSView that hosts a `GifPlayerLayer` and handles aspect-fill layout.
/// Layout is recomputed only when `bounds` actually changes, not on every
/// GIF frame tick.
final class GifHostView: NSView {
    private let playerLayer = GifPlayerLayer()
    private var lastLayoutBounds: CGRect = .zero

    private(set) var currentURL: URL?
    private(set) var isPlaying: Bool = false
    /// Tracks whether the hosting window is currently visible (not occluded
    /// or miniaturised). When the window is hidden, we still honour the
    /// caller-driven `isPlaying` flag, but pause the underlying decode loop
    /// so we don't spend CPU producing frames nobody can see.
    private var windowVisible: Bool = true
    private var occlusionObserver: NSObjectProtocol?
    private var miniaturizeObserver: NSObjectProtocol?
    private var deminiaturizeObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    override var intrinsicContentSize: NSSize { .zero }
    override var mouseDownCanMoveWindow: Bool { true }

    private func setUp() {
        wantsLayer = true
        let root = CALayer()
        root.backgroundColor = NSColor.clear.cgColor
        root.masksToBounds = true
        layer = root

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.addSublayer(playerLayer)
        CATransaction.commit()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        // Remove observers that target the *current* window before re-parenting,
        // so we don't leave dangling observers on a window we're leaving.
        removeWindowObservers()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            windowVisible = false
            applyEffectivePlayState()
            return
        }
        let center = NotificationCenter.default
        occlusionObserver = center.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshWindowVisibility()
            }
        }
        miniaturizeObserver = center.addObserver(
            forName: NSWindow.didMiniaturizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshWindowVisibility()
            }
        }
        deminiaturizeObserver = center.addObserver(
            forName: NSWindow.didDeminiaturizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshWindowVisibility()
            }
        }
        refreshWindowVisibility()
    }

    private func removeWindowObservers() {
        let center = NotificationCenter.default
        if let occlusionObserver { center.removeObserver(occlusionObserver) }
        if let miniaturizeObserver { center.removeObserver(miniaturizeObserver) }
        if let deminiaturizeObserver { center.removeObserver(deminiaturizeObserver) }
        occlusionObserver = nil
        miniaturizeObserver = nil
        deminiaturizeObserver = nil
    }

    private func refreshWindowVisibility() {
        let visible: Bool
        if let window {
            visible = window.occlusionState.contains(.visible) && !window.isMiniaturized
        } else {
            visible = false
        }
        guard visible != windowVisible else { return }
        windowVisible = visible
        applyEffectivePlayState()
    }

    private func applyEffectivePlayState() {
        playerLayer.setPlaying(isPlaying && windowVisible)
    }

    override func layout() {
        super.layout()
        guard bounds != lastLayoutBounds else { return }
        lastLayoutBounds = bounds
        updatePlayerFrame()
    }

    private func updatePlayerFrame() {
        let container = bounds.size
        guard container.width > 0, container.height > 0 else { return }

        let gifSize = playerLayer.gifPixelSize
        let target: CGSize
        if gifSize.width > 0, gifSize.height > 0 {
            let scale = max(
                container.width / gifSize.width,
                container.height / gifSize.height
            )
            target = CGSize(width: gifSize.width * scale, height: gifSize.height * scale)
        } else {
            target = container
        }

        let origin = CGPoint(
            x: (container.width - target.width) / 2,
            y: (container.height - target.height) / 2
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = CGRect(origin: origin, size: target)
        CATransaction.commit()
    }

    func load(url: URL) {
        currentURL = url
        let weakHost = WeakObjectBox(self)
        playerLayer.load(url: url) {
            DispatchQueue.main.async { weakHost.value?.updatePlayerFrame() }
        }
    }

    func setPlaying(_ playing: Bool) {
        isPlaying = playing
        applyEffectivePlayState()
    }

    func tearDown() {
        removeWindowObservers()
        playerLayer.tearDown()
    }
}

// MARK: - GifPlayerLayer

/// CALayer subclass that decodes GIF frames on a dedicated background
/// DispatchQueue and pushes `CGImage` snapshots to `contents` on the main
/// thread via `DispatchQueue.main.async`.
///
/// We deliberately avoid Swift Concurrency (Task/await) here because
/// GifPlayerLayer is a CALayer subclass and therefore not Sendable;
/// crossing actor isolation boundaries would require @unchecked Sendable
/// gymnastics that make the code harder to audit. The DispatchQueue +
/// semaphore approach is straightforward, well-understood, and avoids
/// every Swift 6 data-race warning.
final class GifPlayerLayer: CALayer, @unchecked Sendable {

    /// Reported pixel size of the GIF (used by the host view for layout).
    private(set) var gifPixelSize: CGSize = .zero

    private var frameCache: GifFrameCache?
    private var playing: Bool = false
    private var isActive: Bool = true

    /// Serial queue that runs the frame-decode loop.
    private let decodeQueue = DispatchQueue(label: "gif.decode", qos: .userInitiated)
    /// Incremented each time `startDecodeLoop` is called; the running loop
    /// captures the value at start time and exits when it no longer matches.
    private var generation: Int = 0

    private var onSizeReady: (@Sendable () -> Void)?

    override init() {
        super.init()
        contentsGravity = .resizeAspectFill
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func load(url: URL, onSizeReady: @escaping @Sendable () -> Void) {
        generation += 1
        contents = nil
        gifPixelSize = .zero
        self.onSizeReady = onSizeReady

        guard let cache = GifFrameCachePool.shared.cache(for: url) else { return }
        self.frameCache = cache

        if playing {
            startDecodeLoop()
        } else if cache.frameCount <= 1 {
            // Static snow / placeholders: still need one decode pass even when
            // the layer is logically paused — otherwise `contents` stays nil
            // and the black `GifHostView` root shows through.
            startDecodeLoop()
        }
    }

    func setPlaying(_ play: Bool) {
        guard play != playing else { return }
        playing = play
        if play {
            startDecodeLoop()
        } else {
            // Bumping the generation causes the running loop to exit at its
            // next iteration without needing an explicit cancel token.
            generation += 1
        }
    }

    func tearDown() {
        isActive = false
        generation += 1
        frameCache = nil
        contents = nil
    }

    private func startDecodeLoop() {
        guard let cache = frameCache else { return }
        let sizeReady = onSizeReady
        onSizeReady = nil

        let myGen = generation
        let weakSelf = WeakObjectBox(self)

        // Static (single-frame) GIFs: render once and never schedule another
        // tick. Previously the loop would Thread.sleep+wake up at the GIF's
        // delay (often 0.1s) forever, decoding & blitting the same image
        // 10 times per second — pure idle CPU.
        if cache.frameCount <= 1 {
            decodeQueue.async {
                let (image, _) = cache.frame(at: 0)
                guard let image, let layer = weakSelf.value else { return }
                let gifSize = cache.pixelSize
                DispatchQueue.main.async {
                    guard let layer = weakSelf.value, layer.isActive, layer.generation == myGen else { return }
                    layer.gifPixelSize = gifSize
                    sizeReady?()
                    layer.contents = image
                }
                _ = layer
            }
            return
        }

        // Multi-frame: schedule the next tick via `asyncAfter` so the
        // decode queue thread is free to be reaped between frames instead
        // of holding a worker hostage with `Thread.sleep`. This also lets
        // QoS demotion happen between ticks when the system is busy.
        scheduleNextTick(
            cache: cache,
            myGen: myGen,
            frameIndex: 0,
            sizeReported: false,
            weakSelfBox: weakSelf,
            sizeReady: sizeReady
        )
    }

    private func scheduleNextTick(
        cache: GifFrameCache,
        myGen: Int,
        frameIndex: Int,
        sizeReported: Bool,
        weakSelfBox: WeakObjectBox<GifPlayerLayer>,
        sizeReady: (@Sendable () -> Void)?
    ) {
        decodeQueue.async {
            guard let layer = weakSelfBox.value, layer.isActive, layer.generation == myGen else { return }

            let (image, frameDelay) = cache.frame(at: frameIndex)
            guard let image else { return }

            let firstFrame = !sizeReported
            let gifSize = cache.pixelSize

            DispatchQueue.main.async {
                guard let layer = weakSelfBox.value, layer.isActive, layer.generation == myGen else { return }
                if firstFrame {
                    layer.gifPixelSize = gifSize
                    sizeReady?()
                }
                // Diff-guard: setting `contents` to the same CGImage still
                // dirties the layer and forces a CA::Render::copy_image on
                // the next commit. Comparing by object identity catches the
                // common case where the frame cache hands us the same
                // memoised CGImage as last cycle.
                if (layer.contents as AnyObject?) !== (image as AnyObject) {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    layer.contents = image
                    CATransaction.commit()
                }
            }

            let nextIndex = (frameIndex + 1) % cache.frameCount
            // Cap frame rate at 60fps; otherwise honour the GIF's own
            // delay (typically 100 ms for lofi.cafe content).
            let delay = max(frameDelay, 0.016)
            let deferredWeak = WeakObjectBox(layer)
            let queue = self.decodeQueue
            queue.asyncAfter(deadline: .now() + delay) {
                guard let layer = deferredWeak.value, layer.isActive, layer.generation == myGen else { return }
                layer.scheduleNextTick(
                    cache: cache,
                    myGen: myGen,
                    frameIndex: nextIndex,
                    sizeReported: true,
                    weakSelfBox: deferredWeak,
                    sizeReady: nil
                )
            }
        }
    }
}

private final class WeakObjectBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?

    init(_ value: T?) {
        self.value = value
    }
}

// MARK: - GifFrameCache

/// Thin wrapper around ImageIO that reads frame data on demand.
/// Does NOT pre-decode all frames — it creates CGImage for each frame
/// lazily so memory usage stays proportional to a single frame, not
/// the entire GIF film strip.
///
/// Sendable: `source`, `delays`, `pixelSize`, and `decodeOptions` are all
/// set at init and never mutated; CGImageSource is safe for concurrent reads.
final class GifFrameCache: @unchecked Sendable {
    let frameCount: Int
    /// Pixel dimensions shared by all frames (GIF spec: constant per file).
    let pixelSize: CGSize
    private let source: CGImageSource
    private let delays: [Double]
    private let decodeOptions: CFDictionary?
    /// Display color space captured at init time (main thread) so the
    /// background decode queue can use it without touching NSScreen.
    private let displayColorSpace: CGColorSpace
    /// Memoised decoded frames. Populated lazily on the decode queue and
    /// then re-served on every loop iteration so the only per-tick work
    /// is a CGImage handoff to the main thread (no vImage convert / no
    /// CGImageSource re-decode / no malloc of a fresh RGBA bitmap).
    ///
    /// Most lofi.cafe gifs in the catalog are 50–200 frames at small
    /// (~480×270) resolution, so a fully decoded film strip costs roughly
    /// 25–100 MB per gif. Two safeguards keep that bounded:
    ///   * `cacheableTotalBytes` — refuse to memoise gigantic gifs and fall
    ///     back to per-frame decode for them. The user is already paying
    ///     network + disk for those, so the CPU cost is amortised over the
    ///     much larger I/O cost.
    ///   * `GifFrameCachePool` already caps the number of live caches to
    ///     8, so the worst case stays roughly proportional to that bound.
    private let cacheLock = NSLock()
    private var decodedFrames: [CGImage?]
    private let memoiseFrames: Bool
    /// Maximum bytes-per-gif we'll keep fully decoded. 64 MB is enough to
    /// cover every shipped lofi.cafe gif at its native resolution while
    /// protecting against pathological 4K/long-form gifs that would blow
    /// up the resident set if memoised in full.
    private static let cacheableTotalBytes: Int = 64 * 1024 * 1024

    init?(url: URL) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(src)
        guard count > 0 else { return nil }

        source = src
        frameCount = count
        delays = (0..<count).map { GifFrameCache.frameDelay(source: src, at: $0) }

        // Read pixel size from the first frame's properties — cheaper than
        // decoding the full image just to call image.width/height.
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Int,
           let h = props[kCGImagePropertyPixelHeight] as? Int {
            pixelSize = CGSize(width: w, height: h)
        } else {
            pixelSize = .zero
        }

        decodeOptions = nil

        // Capture display CS on this (main) thread once. The background
        // decode queue reads it as an immutable reference — safe.
        displayColorSpace = NSScreen.main?.colorSpace?.cgColorSpace
            ?? CGColorSpace(name: CGColorSpace.sRGB)!

        let estimatedTotalBytes = Int(pixelSize.width) * Int(pixelSize.height) * 4 * count
        memoiseFrames = estimatedTotalBytes > 0 && estimatedTotalBytes <= Self.cacheableTotalBytes
        decodedFrames = memoiseFrames ? Array(repeating: nil, count: count) : []
    }

    /// Returns (CGImage, delaySeconds) for the given frame index.
    ///
    /// `CGImageSourceCreateImageAtIndex` returns a lazy CGImage whose pixels
    /// are not decoded until QuartzCore composites it — which happens on the
    /// main thread during CA::Transaction::commit. Profiling showed 252 of
    /// 4324 main-thread samples spent in `GIFReadPlugin::decodeIndexedColorFrames`
    /// triggered from inside `CA::Render::copy_image`.
    ///
    /// The fix: after obtaining the lazy CGImage we force the full LZW decode
    /// on the background queue by drawing it into a pre-allocated bitmap
    /// context. The resulting CGImage is backed by raw RGBA bytes that
    /// QuartzCore can blit without any further decompression work.
    ///
    /// Decoded frames are memoised on the first miss, so subsequent loop
    /// iterations only pay the cost of returning the cached CGImage. This
    /// dropped the gif.decode worker from ~76% busy to single-digit % in
    /// the steady state for typical 10 fps gifs.
    func frame(at index: Int) -> (CGImage?, Double) {
        guard index < frameCount else { return (nil, 0.1) }

        if memoiseFrames {
            cacheLock.lock()
            let cached = decodedFrames[index]
            cacheLock.unlock()
            if let cached {
                return (cached, delays[index])
            }
        }

        guard let lazy = CGImageSourceCreateImageAtIndex(source, index, decodeOptions) else {
            return (nil, delays[index])
        }
        let decoded = Self.forceDecode(lazy, into: displayColorSpace) ?? lazy

        if memoiseFrames {
            cacheLock.lock()
            decodedFrames[index] = decoded
            cacheLock.unlock()
        }

        return (decoded, delays[index])
    }

    func delay(at index: Int) -> Double {
        guard index < frameCount else { return 0.1 }
        return delays[index]
    }

    /// Draws `image` into a bitmap context using `targetCS` to force full
    /// pixel decompression on the calling (background) thread.
    ///
    /// Using the display color space as the target means the resulting
    /// CGImage is already in display-ready space, so QuartzCore can blit
    /// it directly without any ICC profile conversion on the main thread.
    private static func forceDecode(_ image: CGImage, into targetCS: CGColorSpace) -> CGImage? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0,
              let ctx = CGContext(
                data: nil,
                width: w, height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: targetCS,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                           | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    private static func frameDelay(source: CGImageSource, at index: Int) -> Double {
        let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gifProps = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]

        // Prefer the unclamped delay (matches browser behaviour).
        if let d = gifProps?[kCGImagePropertyGIFUnclampedDelayTime] as? Double, d > 0 {
            return d
        }
        if let d = gifProps?[kCGImagePropertyGIFDelayTime] as? Double, d > 0 {
            return d
        }
        return 0.1
    }
}

// MARK: - Workspace snow (GIF / GIF+Bongo reveal gate)

/// Random static GIF snow until the workspace is ready — no spinner state.
struct WorkspaceSnowLoadingCover: View {
    @State private var url: URL? = GifCache.startupSnowOverlayURL

    var body: some View {
        SnowOverlayView(url: url)
        .task {
            guard url == nil else { return }
            guard let picked = await GifCache.shared.randomCachedStatic() else { return }
            url = picked
        }
    }
}
