import AppKit
@preconcurrency import AVFoundation
import CoreVideo
import Metal
import MetalKit
import SwiftUI

enum StageMetalSource: Equatable {
    case video(URL)
    case gif(URL)
}

struct StageMetalPlayerView: NSViewRepresentable {
    let source: StageMetalSource
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
    let onFirstFrameReady: (@MainActor () -> Void)?

    init(
        source: StageMetalSource,
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
        onFirstFrameReady: (@MainActor () -> Void)? = nil
    ) {
        self.source = source
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
        self.onFirstFrameReady = onFirstFrameReady
    }

    func makeCoordinator() -> StageMetalRenderer {
        StageMetalRenderer()
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        context.coordinator.attach(to: view)
        context.coordinator.update(
            source: source,
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
            onFirstFrameReady: onFirstFrameReady
        )
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.update(
            source: source,
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
            onFirstFrameReady: onFirstFrameReady
        )
    }

    static func dismantleNSView(_ nsView: MTKView, coordinator: StageMetalRenderer) {
        coordinator.tearDown()
    }
}

@MainActor
final class StageMetalRenderer: NSObject, MTKViewDelegate {
    private struct Uniforms {
        var viewportSize: SIMD2<Float> = .zero
        var sourceSize: SIMD2<Float> = .zero
        var curvationFactor: Float = 0
        var opacity: Float = 1
        var overscan: Float = 1
        var scanlineAmount: Float = 0
        var scanlinePitch: Float = 3
        var borderSize: Float = 0.01
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

    private weak var view: MTKView?
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var textureLoader: MTKTextureLoader?
    private var videoTextureCache: CVMetalTextureCache?
    private var blackTexture: MTLTexture?
    private var shatteredGlassTextures: ShatteredGlassTextureSet?

    private var source: StageMetalSource?
    private var isPlaying = true
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
    private var onFirstFrameReady: (@MainActor () -> Void)?
    private var deliveredFirstFrame = false

    private var player: AVPlayer?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var videoEndObserver: NSObjectProtocol?
    private var currentVideoCVTexture: CVMetalTexture?
    private var currentVideoTexture: MTLTexture?
    private var currentVideoSize: CGSize = .zero
    private var videoNoFrameLogDeadline: CFTimeInterval = 0
    private var videoTextureFailureLogged = false

    private var gifCache: GifFrameCache?
    private let gifTextureFrameCache = GifMetalTextureFrameCache()
    private var currentGifTexture: MTLTexture?
    private var currentGifSize: CGSize = .zero
    private var gifFrameIndex = 0
    private var nextGifFrameTime: CFTimeInterval = 0

    func attach(to view: MTKView) {
        let metalDevice = MTLCreateSystemDefaultDevice()
        self.view = view
        self.device = metalDevice
        view.device = metalDevice
        view.delegate = self
        StageMetalMTKRuntime.applyBasePresentation(to: view, framebufferOnly: true)

        guard let metalDevice else { return }
        commandQueue = metalDevice.makeCommandQueue()
        textureLoader = MTKTextureLoader(device: metalDevice)
        if let textureLoader {
            shatteredGlassTextures = ShatteredGlassTextureSet.load(using: textureLoader)
        }
        blackTexture = Self.makeBlackTexture(device: metalDevice)
        CVMetalTextureCacheCreate(nil, nil, metalDevice, nil, &videoTextureCache)
        buildPipeline(device: metalDevice, pixelFormat: view.colorPixelFormat)
    }

    func update(source: StageMetalSource, isPlaying: Bool, curvationEnabled: Bool) {
        let factor = curvationEnabled ? CurvationStrength.balanced.resolvedCurvationFactor : 0
        let overscan = curvationEnabled ? CurvationStrength.balanced.resolvedOverscan : 1
        let border = curvationEnabled ? CurvationStrength.balanced.resolvedBorderSize : 0
        update(
            source: source,
            isPlaying: isPlaying,
            curvationFactor: factor,
            curvationOverscan: overscan,
            curvationBorderSize: border,
            vignetteAlpha: 0,
            motionBlurEnabled: false,
            motionBlurStrength: MotionBlurStrength.balanced.resolvedStrength,
            chromaticAberrationEnabled: false,
            chromaticAberrationStrength: ChromaticAberrationStrength.balanced.resolvedStrength,
            scanlinesEnabled: false,
            scanlineOpacity: 0,
            scanlineDensity: ScanlineDensity.balanced.pitch,
            shatteredGlassOpacity: 0,
            shatteredGlassRefraction: 0,
            shatteredGlassHighlight: 0,
            shatteredGlassFlipX: 0,
            onFirstFrameReady: nil
        )
    }

    func update(
        source: StageMetalSource,
        isPlaying: Bool,
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
        onFirstFrameReady: (@MainActor () -> Void)? = nil
    ) {
        let sourceChanged = self.source != source
        let playbackChanged = self.isPlaying != isPlaying

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
        self.onFirstFrameReady = onFirstFrameReady
        if sourceChanged {
            self.source = source
            configureSource(source)
        }
        if sourceChanged || playbackChanged {
            applyDrawLoopState()
            applyPlaybackState()
        }
    }

    func tearDown() {
        clearMediaState()
        source = nil
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else {
            return
        }
        guard let descriptor = view.currentRenderPassDescriptor else {
            return
        }
        guard let commandQueue else {
            return
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        guard let pipelineState else {
            return
        }

        let textureAndSize = currentTexture()
        notifyFirstFrameReadyIfNeeded(texture: textureAndSize.texture)
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(textureAndSize.texture ?? blackTexture, index: 0)
        encoder.setFragmentTexture(shatteredGlassTextures?.pattern, index: 1)
        encoder.setFragmentTexture(shatteredGlassTextures?.background, index: 2)

        let resolvedOverscan = CRTStageViewportShaping.resolvedOverscan(
            curvationFactor: curvationFactor,
            presetOverscan: curvationOverscan
        )

        var uniforms = Uniforms(
            viewportSize: SIMD2<Float>(
                Float(max(view.drawableSize.width, 1)),
                Float(max(view.drawableSize.height, 1))
            ),
            sourceSize: SIMD2<Float>(
                Float(max(textureAndSize.size.width, 1)),
                Float(max(textureAndSize.size.height, 1))
            ),
            curvationFactor: Float(curvationFactor),
            opacity: textureAndSize.texture == nil ? 0 : 1,
            overscan: Float(resolvedOverscan),
            scanlineAmount: scanlinesEnabled ? Float(scanlineOpacity) : 0,
            scanlinePitch: Float(scanlineDensity),
            borderSize: Float(curvationBorderSize),
            vignetteAlpha: Float(vignetteAlpha),
            motionBlurStrength: motionBlurEnabled ? Float(motionBlurStrength) : 0,
            chromaticAberrationStrength: chromaticAberrationEnabled ? Float(chromaticAberrationStrength) : 0,
            zfastBlurScaleX: 0.30,
            zfastLowLumScan: 6.0,
            zfastHighLumScan: 8.0,
            zfastBrightBoost: 1.25,
            zfastMaskDark: 0.25,
            zfastMaskFade: 0.8,
            glassOpacity: Float(shatteredGlassTextures == nil ? 0 : shatteredGlassOpacity),
            glassRefractionPixels: Float(shatteredGlassRefraction),
            glassHighlightStrength: Float(shatteredGlassHighlight),
            glassFlipX: Float(shatteredGlassFlipX),
            glassTextureSize: SIMD2<Float>(
                Float(shatteredGlassTextures?.background.width ?? 1),
                Float(shatteredGlassTextures?.background.height ?? 1)
            )
        )
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func buildPipeline(device: MTLDevice, pixelFormat: MTLPixelFormat) {
        do {
            pipelineState = try StageMetalPipelineCache.stagePipeline(
                device: device,
                pixelFormat: pixelFormat
            )
        } catch {
            print("[StageMetal] failed to build pipeline: \(error)")
        }
    }

    private static func makeBlackTexture(device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        var pixel: UInt32 = 0xFF000000
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &pixel,
            bytesPerRow: 4
        )
        return texture
    }

    private func configureSource(_ source: StageMetalSource) {
        clearMediaState()
        currentVideoSize = .zero
        videoNoFrameLogDeadline = 0
        videoTextureFailureLogged = false
        currentGifSize = .zero
        gifFrameIndex = 0
        nextGifFrameTime = 0
        deliveredFirstFrame = false

        switch source {
        case .video(let url):
            configureVideo(url: url)
        case .gif(let url):
            configureGif(url: url)
        }
        applyPlaybackState()
    }

    private func clearMediaState() {
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
    }

    private func notifyFirstFrameReadyIfNeeded(texture: MTLTexture?) {
        guard texture != nil, !deliveredFirstFrame else { return }
        deliveredFirstFrame = true
        onFirstFrameReady?()
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
        uploadGifFrame(at: 0)
        // `draw(in:)` may not run immediately (MTKView paused, pipeline not ready,
        // or zero-size layout). `GifSceneView` waits on this callback to lift snow;
        // signal as soon as the first GPU texture exists.
        notifyFirstFrameReadyIfNeeded(texture: currentGifTexture)
    }

    private func applyPlaybackState() {
        guard case .video = source else { return }
        if isPlaying {
            player?.play()
        } else {
            player?.pause()
        }
    }

    private func applyDrawLoopState() {
        StageMetalMTKRuntime.syncDrawLoopToPlayback(view: view, isPlaying: isPlaying)
    }

    private func loopVideoIfNeeded() {
        guard case .video = source, let player else { return }
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        if isPlaying {
            player.play()
        }
    }

    private func currentTexture() -> (texture: MTLTexture?, size: CGSize) {
        switch source {
        case .video:
            updateVideoTexture()
            return (currentVideoTexture, currentVideoSize)
        case .gif:
            updateGifTexture()
            return (currentGifTexture, currentGifSize)
        case nil:
            return (nil, .zero)
        }
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
                print("[StageMetal] video CVMetalTexture creation failed status=\(status) size=\(width)x\(height)")
            }
            return
        }
        currentVideoCVTexture = cvTexture
        currentVideoTexture = texture
        currentVideoSize = CGSize(width: width, height: height)
        // Same idea as `configureGif`: `SceneView` startup snow waits on this
        // callback; do not rely solely on `draw(in:)` committing first.
        notifyFirstFrameReadyIfNeeded(texture: texture)
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
            "[StageMetal] video waiting for first frame status=\(status) rate=\(player?.rate ?? -1) itemTime=\(String(format: "%.3f", itemTime.seconds)) error=\(error)"
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
        guard isPlaying else { return }
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
                textureLoader: textureLoader
            )
            guard let texture = frame.texture else { return }
            currentGifTexture = texture
            currentGifSize = frame.size
            let safeIndex = index % cache.frameCount
            gifFrameIndex = (safeIndex + 1) % cache.frameCount
            nextGifFrameTime = CACurrentMediaTime() + max(frame.delay, 0.016)
        } catch {
            print("[StageMetal] failed to upload GIF frame: \(error)")
            nextGifFrameTime = CACurrentMediaTime() + 0.25
        }
    }
}
