import Foundation
import Metal
import MetalKit
import simd
import JawAtlasCore

enum RendererError: Error {
    case deviceUnavailable
    case libraryUnavailable
    case pipelineFailed(String)
    case textureAllocationFailed

    var userMessage: String {
        switch self {
        case .deviceUnavailable, .libraryUnavailable, .textureAllocationFailed:
            return "3D rendering is not available on this device."
        case .pipelineFailed:
            return "The 3D view could not be prepared."
        }
    }
}

@MainActor
final class VolumeRenderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    private var rayMarchPipeline: MTLRenderPipelineState?
    private var crossSectionPipeline: MTLRenderPipelineState?
    private var panoramicPipeline: MTLRenderPipelineState?
    private var cameraBackgroundPipeline: MTLRenderPipelineState?
    private(set) var volumeTexture: MTLTexture?
    private(set) var geometry: VolumeGeometry?

    static let stagingBudgetBytes = 32 << 20

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RendererError.deviceUnavailable }
        guard let queue = device.makeCommandQueue() else { throw RendererError.deviceUnavailable }
        guard let library = device.makeDefaultLibrary() else { throw RendererError.libraryUnavailable }
        self.device = device
        self.commandQueue = queue
        self.library = library
    }

    func preparePipelines(colorFormat: MTLPixelFormat, includeCameraBackground: Bool = false) throws {
        if rayMarchPipeline == nil {
            rayMarchPipeline = try makePipeline(fragment: "volumeRayMarchFragment", colorFormat: colorFormat)
        }
        if crossSectionPipeline == nil {
            crossSectionPipeline = try makePipeline(fragment: "crossSectionFragment", colorFormat: colorFormat)
        }
        if panoramicPipeline == nil {
            panoramicPipeline = try makePipeline(fragment: "panoramicFragment", colorFormat: colorFormat)
        }
        if includeCameraBackground && cameraBackgroundPipeline == nil {
            cameraBackgroundPipeline = try makePipeline(
                vertex: "cameraBackgroundVertex",
                fragment: "cameraBackgroundFragment",
                colorFormat: colorFormat,
                blending: false
            )
        }
    }

    private func makePipeline(
        vertex: String = "fullscreenVertex",
        fragment: String,
        colorFormat: MTLPixelFormat,
        blending: Bool = true
    ) throws -> MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: vertex),
              let fragmentFunction = library.makeFunction(name: fragment) else {
            throw RendererError.pipelineFailed(fragment)
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = colorFormat
        descriptor.colorAttachments[0].isBlendingEnabled = blending
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw RendererError.pipelineFailed(fragment)
        }
    }

    private func makeVolumeTexture(geometry: VolumeGeometry) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .r16Snorm
        descriptor.width = geometry.width
        descriptor.height = geometry.height
        descriptor.depth = geometry.depth
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.textureAllocationFailed
        }
        return texture
    }

    func upload(voxels: [Int16], geometry: VolumeGeometry) throws {
        guard voxels.count == geometry.width * geometry.height * geometry.depth else {
            throw RendererError.textureAllocationFailed
        }
        let texture = try makeVolumeTexture(geometry: geometry)
        voxels.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake3D(0, 0, 0, geometry.width, geometry.height, geometry.depth),
                mipmapLevel: 0,
                slice: 0,
                withBytes: base,
                bytesPerRow: geometry.width * 2,
                bytesPerImage: geometry.width * geometry.height * 2
            )
        }
        volumeTexture = texture
        self.geometry = geometry
    }

    func upload(handle: VolumeHandle, geometry: VolumeGeometry) throws {
        let texture = try makeVolumeTexture(geometry: geometry)
        let bytesPerRow = geometry.width * 2
        let bytesPerImage = bytesPerRow * geometry.height
        let slabDepth = max(1, min(geometry.depth, VolumeRenderer.stagingBudgetBytes / max(bytesPerImage, 1)))
        var start = 0
        while start < geometry.depth {
            let count = min(slabDepth, geometry.depth - start)
            let region = MTLRegionMake3D(0, 0, start, geometry.width, geometry.height, count)
            let offset = start * bytesPerImage
            texture.replace(
                region: region,
                mipmapLevel: 0,
                slice: 0,
                withBytes: handle.huBuffer.advanced(by: offset),
                bytesPerRow: bytesPerRow,
                bytesPerImage: bytesPerImage
            )
            start += count
        }
        volumeTexture = texture
        self.geometry = geometry
    }

    func discardVolume() {
        volumeTexture = nil
        geometry = nil
    }

    var boundingRadiusMM: Float {
        guard let geometry else { return 100 }
        return Float(geometry.diagonalMM / 2)
    }

    func baseUniforms(window: WindowLevel, presentation: VolumePresentation) -> VolumeUniforms {
        var uniforms = VolumeUniforms()
        guard let geometry else { return uniforms }
        let extent = geometry.extentMM
        uniforms.halfExtentMM = SIMD3<Float>(Float(extent.x / 2), Float(extent.y / 2), Float(extent.z / 2))
        uniforms.windowLow = Float(window.center - window.width / 2)
        uniforms.windowWidth = Float(window.width)
        uniforms.voxelStepTexture = SIMD3<Float>(
            1 / Float(geometry.width),
            1 / Float(geometry.height),
            1 / Float(geometry.depth)
        )
        let smallestSpacing = min(geometry.spacingMM.x, min(geometry.spacingMM.y, geometry.spacingMM.z))
        let coverageStep = geometry.diagonalMM / 700
        uniforms.stepMM = Float(max(max(smallestSpacing * 0.9, coverageStep), 0.18))
        uniforms.maximumSteps = Float(min(768, Int(geometry.diagonalMM / Double(uniforms.stepMM)) + 8))
        uniforms.tintColor = presentation.tint
        uniforms.surfaceThreshold = presentation.surfaceThresholdHU
        uniforms.surfaceSoftness = presentation.surfaceSoftnessHU
        uniforms.opacityScale = presentation.opacityScale
        return uniforms
    }

    func drawRayMarch(
        into encoder: MTLRenderCommandEncoder,
        camera: OrbitCamera,
        aspect: Float,
        window: WindowLevel,
        presentation: VolumePresentation,
        shaded: Bool = true,
        mip: Bool = false
    ) {
        let viewProjection = camera.viewProjection(aspect: aspect, radius: boundingRadiusMM)
        let light = simd_normalize(camera.eye - camera.target + SIMD3<Float>(0.25, 0, 0.35) * boundingRadiusMM)
        drawRayMarch(
            into: encoder,
            viewProjection: viewProjection,
            cameraLocal: camera.eye,
            lightDirection: light,
            window: window,
            presentation: presentation,
            clip: nil,
            shaded: shaded,
            mip: mip
        )
    }

    func drawRayMarch(
        into encoder: MTLRenderCommandEncoder,
        viewProjection: simd_float4x4,
        cameraLocal: SIMD3<Float>,
        lightDirection: SIMD3<Float>,
        window: WindowLevel,
        presentation: VolumePresentation,
        clip: (point: SIMD3<Float>, normal: SIMD3<Float>)?,
        shaded: Bool = true,
        mip: Bool = false,
        globalAlpha: Float = 1,
        emptyAlpha: Float = 0
    ) {
        guard let pipeline = rayMarchPipeline, let texture = volumeTexture else { return }
        var uniforms = baseUniforms(window: window, presentation: presentation)
        uniforms.globalAlpha = globalAlpha
        uniforms.emptyAlpha = emptyAlpha
        uniforms.shadingEnabled = shaded ? 1 : 0
        uniforms.mipEnabled = mip ? 1 : 0
        if mip {
            uniforms.windowWidth = Float(window.width) * 2.5
        }
        uniforms.inverseViewProjection = viewProjection.inverse
        uniforms.cameraLocal = cameraLocal
        uniforms.lightDirection = lightDirection
        if let clip {
            uniforms.clipEnabled = 1
            uniforms.clipPlanePoint = clip.point
            uniforms.clipPlaneNormal = clip.normal
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<VolumeUniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    static let panoramicPointLimit = 240

    func drawPanoramic(
        into encoder: MTLRenderCommandEncoder,
        archPointsLocalMM: [SIMD3<Float>],
        window: WindowLevel,
        slabMM: Float
    ) {
        guard let pipeline = panoramicPipeline, let texture = volumeTexture,
              archPointsLocalMM.count >= 2 else { return }
        var uniforms = baseUniforms(window: window, presentation: .bone)
        let points = Array(archPointsLocalMM.prefix(VolumeRenderer.panoramicPointLimit))
        uniforms.panoPointCount = Float(points.count)
        uniforms.panoSlabMM = slabMM
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<VolumeUniforms>.stride, index: 0)
        points.withUnsafeBytes { raw in
            encoder.setFragmentBytes(raw.baseAddress!, length: raw.count, index: 1)
        }
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    func drawCameraBackground(
        into encoder: MTLRenderCommandEncoder,
        luma: MTLTexture,
        chroma: MTLTexture,
        transform: simd_float4x4
    ) {
        guard let pipeline = cameraBackgroundPipeline else { return }
        var matrix = transform
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&matrix, length: MemoryLayout<simd_float4x4>.stride, index: 0)
        encoder.setFragmentTexture(luma, index: 0)
        encoder.setFragmentTexture(chroma, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    func drawCrossSection(
        into encoder: MTLRenderCommandEncoder,
        planeToLocal: simd_float4x4,
        window: WindowLevel,
        alpha: Float,
        airThresholdHU: Float = -10000
    ) {
        guard let pipeline = crossSectionPipeline, let texture = volumeTexture else { return }
        var uniforms = baseUniforms(window: window, presentation: .bone)
        uniforms.planeToLocal = planeToLocal
        uniforms.crossSectionAlpha = alpha
        uniforms.crossSectionAirHU = airThresholdHU
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<VolumeUniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}
