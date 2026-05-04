import Foundation
import Metal

@MainActor
enum StageMetalPipelineCache {
    private struct PipelineKey: Hashable {
        let device: ObjectIdentifier
        let pixelFormat: UInt
        let kind: Kind

        enum Kind: Hashable {
            case stage
            case bongoQuad
            case bongoMask
        }
    }

    private static var libraries: [ObjectIdentifier: MTLLibrary] = [:]
    private static var pipelines: [PipelineKey: MTLRenderPipelineState] = [:]

    static func stagePipeline(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat
    ) throws -> MTLRenderPipelineState {
        try pipeline(
            device: device,
            pixelFormat: pixelFormat,
            kind: .stage,
            vertexName: "stageVertex",
            fragmentName: "stageFragment",
            configure: nil
        )
    }

    static func bongoPipelines(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat
    ) throws -> (
        stage: MTLRenderPipelineState,
        quad: MTLRenderPipelineState,
        mask: MTLRenderPipelineState
    ) {
        let stage = try stagePipeline(device: device, pixelFormat: pixelFormat)
        let quad = try pipeline(
            device: device,
            pixelFormat: pixelFormat,
            kind: .bongoQuad,
            vertexName: "bongoQuadVertex",
            fragmentName: "bongoTextureFragment",
            configure: configurePremultipliedAlphaBlend
        )
        let mask = try pipeline(
            device: device,
            pixelFormat: pixelFormat,
            kind: .bongoMask,
            vertexName: "stageVertex",
            fragmentName: "bongoDesktopMaskFragment",
            configure: configurePremultipliedAlphaBlend
        )
        return (stage, quad, mask)
    }

    private static func pipeline(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat,
        kind: PipelineKey.Kind,
        vertexName: String,
        fragmentName: String,
        configure: ((MTLRenderPipelineColorAttachmentDescriptor?) -> Void)?
    ) throws -> MTLRenderPipelineState {
        let key = PipelineKey(
            device: ObjectIdentifier(device),
            pixelFormat: UInt(pixelFormat.rawValue),
            kind: kind
        )
        if let cached = pipelines[key] {
            return cached
        }

        let library = try shaderLibrary(device: device)
        guard
            let vertex = library.makeFunction(name: vertexName),
            let fragment = library.makeFunction(name: fragmentName)
        else {
            throw StageMetalPipelineCacheError.missingFunction("\(vertexName)/\(fragmentName)")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        configure?(descriptor.colorAttachments[0])

        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        pipelines[key] = pipeline
        return pipeline
    }

    private static func shaderLibrary(device: MTLDevice) throws -> MTLLibrary {
        let key = ObjectIdentifier(device)
        if let cached = libraries[key] {
            return cached
        }

        if let compiled = try? device.makeDefaultLibrary(bundle: LofiiResources.bundle) {
            libraries[key] = compiled
            return compiled
        }

        if let sourceURL = LofiiResources.bundle.url(
            forResource: "StageMetalShaders",
            withExtension: "metal"
        ) {
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            let compiled = try device.makeLibrary(source: source, options: nil)
            libraries[key] = compiled
            return compiled
        }

        throw StageMetalPipelineCacheError.missingLibrary
    }

    private static func configurePremultipliedAlphaBlend(
        _ attachment: MTLRenderPipelineColorAttachmentDescriptor?
    ) {
        attachment?.isBlendingEnabled = true
        attachment?.rgbBlendOperation = .add
        attachment?.alphaBlendOperation = .add
        attachment?.sourceRGBBlendFactor = .one
        attachment?.sourceAlphaBlendFactor = .one
        attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    }
}

private enum StageMetalPipelineCacheError: LocalizedError {
    case missingLibrary
    case missingFunction(String)

    var errorDescription: String? {
        switch self {
        case .missingLibrary:
            return "Stage Metal shader library is unavailable."
        case .missingFunction(let name):
            return "Stage Metal shader function is unavailable: \(name)."
        }
    }
}
