import CoreGraphics
import Foundation
import Metal
import MetalKit

@MainActor
final class GifMetalTextureFrameCache {
    private static let maxCacheableTotalBytes = 48 * 1024 * 1024
    private static let textureOptions: [MTKTextureLoader.Option: Any] = [
        .SRGB: false,
        .origin: MTKTextureLoader.Origin.topLeft,
    ]

    private var sourceURL: URL?
    private var textures: [Int: MTLTexture] = [:]
    private var cachingEnabled = false

    func reset(url: URL, frameCache: GifFrameCache?) {
        guard sourceURL != url else { return }

        sourceURL = url
        textures.removeAll(keepingCapacity: true)

        guard let frameCache else {
            cachingEnabled = false
            return
        }

        let width = Int(frameCache.pixelSize.width.rounded(.up))
        let height = Int(frameCache.pixelSize.height.rounded(.up))
        let estimatedBytes = width * height * 4 * frameCache.frameCount
        cachingEnabled = estimatedBytes > 0 && estimatedBytes <= Self.maxCacheableTotalBytes
    }

    func clear() {
        sourceURL = nil
        textures.removeAll(keepingCapacity: true)
        cachingEnabled = false
    }

    func texture(
        at index: Int,
        frameCache: GifFrameCache,
        textureLoader: MTKTextureLoader,
        onImageDecoded: ((CGImage) -> Void)? = nil
    ) throws -> (texture: MTLTexture?, size: CGSize, delay: Double) {
        guard frameCache.frameCount > 0 else {
            return (nil, .zero, 0.1)
        }

        let safeIndex = index % frameCache.frameCount
        let delay = frameCache.delay(at: safeIndex)

        if cachingEnabled, let texture = textures[safeIndex] {
            return (
                texture,
                CGSize(width: texture.width, height: texture.height),
                delay
            )
        }

        let (image, imageDelay) = frameCache.frame(at: safeIndex)
        guard let image else {
            return (nil, .zero, imageDelay)
        }
        onImageDecoded?(image)

        let texture = try textureLoader.newTexture(
            cgImage: image,
            options: Self.textureOptions
        )
        if cachingEnabled {
            textures[safeIndex] = texture
        }
        return (
            texture,
            CGSize(width: image.width, height: image.height),
            imageDelay
        )
    }
}
