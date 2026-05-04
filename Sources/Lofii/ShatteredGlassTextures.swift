import Metal
import MetalKit

struct ShatteredGlassTextureSet {
    let pattern: MTLTexture
    let background: MTLTexture

    static func load(using loader: MTKTextureLoader) -> ShatteredGlassTextureSet? {
        guard
            let patternURL = LofiiResources.bundle.url(
                forResource: "shattered_glass_over",
                withExtension: "png",
                subdirectory: "ShatteredGlass"
            ),
            let backgroundURL = LofiiResources.bundle.url(
                forResource: "shattered_glass_bg",
                withExtension: "png",
                subdirectory: "ShatteredGlass"
            ),
            let pattern = try? loader.newTexture(
                URL: patternURL,
                options: [
                    .SRGB: false,
                    .origin: MTKTextureLoader.Origin.topLeft,
                ]
            ),
            let background = try? loader.newTexture(
                URL: backgroundURL,
                options: [
                    .SRGB: false,
                    .origin: MTKTextureLoader.Origin.topLeft,
                ]
            )
        else { return nil }

        return ShatteredGlassTextureSet(pattern: pattern, background: background)
    }
}
