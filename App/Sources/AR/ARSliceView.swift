import SwiftUI
import ARKit
import MetalKit
import simd
import JawAtlasCore

@MainActor
@Observable
final class ARSliceModel: NSObject {
    enum Stage: Equatable {
        case unsupported
        case searching
        case placed
        case interrupted
    }

    private(set) var stage: Stage = .searching
    private(set) var trackingMessage: String?
    var isLocked = false
    var showsVolume = true
    var preset: WindowPreset = .bone

    let session = ARSession()
    private(set) var anchorTransform: simd_float4x4?
    private(set) var lastCandidate: simd_float4x4?
    private(set) var detectedPlaneCount = 0
    private(set) var placedAnchor: ARAnchor?
    var lockedViewMatrix: simd_float4x4?
    var lastFilteredView: simd_float4x4?
    var filterGeneration = 0
    var cutDepthMM: Float = 15
    var penetrationFraction: Float = 0
    var approachMM: Float = 0
    var isAimedAtVolume = true
    var captureRequested = false
    var lastCapture: UIImage?

    var window: WindowLevel { preset.level ?? .bone }

    var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    func start() {
        guard isSupported else {
            stage = .unsupported
            return
        }
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .none
        session.delegate = self
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        stage = .searching
    }

    func stop() {
        session.pause()
    }

    func reset() {
        if let placedAnchor {
            session.remove(anchor: placedAnchor)
        }
        placedAnchor = nil
        anchorTransform = nil
        lockedViewMatrix = nil
        isLocked = false
        cutDepthMM = 15
        penetrationFraction = 0
        approachMM = 0
        filterGeneration += 1
        stage = .searching
        start()
    }

    func place(geometry: VolumeGeometry, viewportSize: CGSize) {
        guard let frame = session.currentFrame else { return }
        let camera = frame.camera
        let cameraPosition = SIMD3<Float>(
            camera.transform.columns.3.x,
            camera.transform.columns.3.y,
            camera.transform.columns.3.z
        )
        let target: SIMD3<Float>
        if let candidate = lastCandidate {
            target = SIMD3<Float>(candidate.columns.3.x, candidate.columns.3.y, candidate.columns.3.z)
        } else {
            let forward = -SIMD3<Float>(
                camera.transform.columns.2.x,
                camera.transform.columns.2.y,
                camera.transform.columns.2.z
            )
            target = cameraPosition + forward * 0.35
        }
        let transform = ARSlicePlacement.uprightTransform(
            at: target,
            facing: cameraPosition,
            geometry: geometry
        )
        anchorTransform = transform
        let anchor = ARAnchor(transform: transform)
        session.add(anchor: anchor)
        placedAnchor = anchor
        cutDepthMM = 15
        filterGeneration += 1
        stage = .placed
    }

    func currentAnchorTransform(frame: ARFrame) -> simd_float4x4? {
        guard let base = anchorTransform else { return nil }
        guard let placedAnchor else { return base }
        return frame.anchors.first { $0.identifier == placedAnchor.identifier }?.transform ?? base
    }

    func toggleLock() {
        isLocked.toggle()
        if isLocked {
            lockedViewMatrix = lastFilteredView ?? session.currentFrame?.camera.viewMatrix(for: .portrait)
        } else {
            lockedViewMatrix = nil
            filterGeneration += 1
        }
    }

    fileprivate func updateCandidate(from frame: ARFrame, viewportSize: CGSize) {
        guard anchorTransform == nil else { return }
        let centre = CGPoint(x: 0.5, y: 0.5)
        let attempts: [(ARRaycastQuery.Target, ARRaycastQuery.TargetAlignment)] = [
            (.existingPlaneGeometry, .horizontal),
            (.estimatedPlane, .horizontal),
            (.estimatedPlane, .any)
        ]
        for attempt in attempts {
            let query = frame.raycastQuery(from: centre, allowing: attempt.0, alignment: attempt.1)
            if let result = session.raycast(query).first {
                lastCandidate = result.worldTransform
                detectedPlaneCount = frame.anchors.compactMap { $0 as? ARPlaneAnchor }.count
                return
            }
        }
        detectedPlaneCount = frame.anchors.compactMap { $0 as? ARPlaneAnchor }.count
        lastCandidate = nil
    }
}

extension ARSliceModel: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let message: String?
        switch camera.trackingState {
        case .normal:
            message = nil
        case .notAvailable:
            message = "Finding your surroundings…"
        case let .limited(reason):
            switch reason {
            case .excessiveMotion: message = "Moving too fast — slow down"
            case .insufficientFeatures: message = "Not enough detail here — try a textured surface"
            case .initializing: message = "Getting ready…"
            case .relocalizing: message = "Finding the jaw again…"
            @unknown default: message = "Hold steady"
            }
        @unknown default:
            message = nil
        }
        Task { @MainActor [weak self] in
            self?.trackingMessage = message
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor [weak self] in
            self?.stage = .interrupted
            self?.trackingMessage = "Session paused"
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.trackingMessage = nil
            self.stage = self.anchorTransform == nil ? .searching : .placed
        }
    }
}

struct ARSliceMetalView: UIViewRepresentable {
    let renderer: VolumeRenderer
    let model: ARSliceModel
    let geometry: VolumeGeometry

    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer, model: model, geometry: geometry)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isOpaque = true
        view.backgroundColor = .black
        view.delegate = context.coordinator
        try? renderer.preparePipelines(colorFormat: view.colorPixelFormat, includeCameraBackground: true)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.geometry = geometry
    }

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        private let renderer: VolumeRenderer
        private let model: ARSliceModel
        var geometry: VolumeGeometry
        private var poseFilter = PoseFilter()
        private var filterGenerationSeen = -1
        private var textureCache: CVMetalTextureCache?
        private var lumaReference: CVMetalTexture?
        private var chromaReference: CVMetalTexture?

        init(renderer: VolumeRenderer, model: ARSliceModel, geometry: VolumeGeometry) {
            self.renderer = renderer
            self.model = model
            self.geometry = geometry
            super.init()
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, renderer.device, nil, &textureCache)
        }

        nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        }

        nonisolated func draw(in view: MTKView) {
            MainActor.assumeIsolated {
                render(in: view)
            }
        }

        private func makeTexture(
            from buffer: CVPixelBuffer,
            plane: Int,
            format: MTLPixelFormat,
            reference: inout CVMetalTexture?
        ) -> MTLTexture? {
            guard let textureCache else { return nil }
            let width = CVPixelBufferGetWidthOfPlane(buffer, plane)
            let height = CVPixelBufferGetHeightOfPlane(buffer, plane)
            var created: CVMetalTexture?
            let status = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, textureCache, buffer, nil,
                format, width, height, plane, &created
            )
            guard status == kCVReturnSuccess, let created else { return nil }
            reference = created
            return CVMetalTextureGetTexture(created)
        }

        private func render(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor,
                  let buffer = renderer.commandQueue.makeCommandBuffer(),
                  let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                return
            }
            defer {
                encoder.endEncoding()
                finishFrame(buffer: buffer, drawable: drawable)
            }

            guard let frame = model.session.currentFrame else { return }
            let viewportPoints = view.bounds.size
            model.updateCandidate(from: frame, viewportSize: viewportPoints)

            let pixelBuffer = frame.capturedImage
            if let luma = makeTexture(from: pixelBuffer, plane: 0, format: .r8Unorm, reference: &lumaReference),
               let chroma = makeTexture(from: pixelBuffer, plane: 1, format: .rg8Unorm, reference: &chromaReference) {
                let display = frame.displayTransform(for: .portrait, viewportSize: viewportPoints).inverted()
                renderer.drawCameraBackground(
                    into: encoder,
                    luma: luma,
                    chroma: chroma,
                    transform: ARSliceModel.matrix(from: display)
                )
            }

            guard let anchorTransform = model.currentAnchorTransform(frame: frame) else { return }

            if filterGenerationSeen != model.filterGeneration {
                poseFilter.reset()
                filterGenerationSeen = model.filterGeneration
            }
            let rawView = frame.camera.viewMatrix(for: .portrait)
            let sliceView: simd_float4x4
            if model.isLocked, let locked = model.lockedViewMatrix {
                sliceView = locked
            } else {
                sliceView = poseFilter.filter(viewMatrix: rawView, at: frame.timestamp)
            }
            model.lastFilteredView = sliceView

            let extent = geometry.extentMM
            let halfExtent = SIMD3<Float>(
                Float(extent.x / 2),
                Float(extent.y / 2),
                Float(extent.z / 2)
            )
            let screenClip = ARSlicePlacement.clipPlaneInLocalMillimetres(
                viewMatrix: sliceView,
                anchorTransform: anchorTransform
            )
            let atScreen = ARSlicePlacement.penetration(
                planePointLocalMM: screenClip.point,
                normalTowardViewer: screenClip.normal,
                halfExtentMM: halfExtent
            )
            let planeDistanceMetres = max((atScreen.approachMM + model.cutDepthMM) / 1000, 0.004)
            let clip = ARSlicePlacement.clipPlaneInLocalMillimetres(
                viewMatrix: sliceView,
                anchorTransform: anchorTransform,
                forwardOffsetMetres: planeDistanceMetres
            )
            let penetration = ARSlicePlacement.penetration(
                planePointLocalMM: clip.point,
                normalTowardViewer: clip.normal,
                halfExtentMM: halfExtent
            )
            model.penetrationFraction = penetration.fraction
            model.approachMM = atScreen.approachMM

            let worldFromSliceEye = sliceView.inverse
            let sliceEyeWorld = SIMD3<Float>(
                worldFromSliceEye.columns.3.x,
                worldFromSliceEye.columns.3.y,
                worldFromSliceEye.columns.3.z
            )
            let sliceForwardWorld = -SIMD3<Float>(
                worldFromSliceEye.columns.2.x,
                worldFromSliceEye.columns.2.y,
                worldFromSliceEye.columns.2.z
            )
            let volumeCentreWorld = SIMD3<Float>(
                anchorTransform.columns.3.x,
                anchorTransform.columns.3.y,
                anchorTransform.columns.3.z
            )
            let towardCentre = volumeCentreWorld - sliceEyeWorld
            model.isAimedAtVolume = simd_length(towardCentre) < 0.05
                || simd_dot(simd_normalize(towardCentre), sliceForwardWorld) > 0.45

            let projection = frame.camera.projectionMatrix(
                for: .portrait,
                viewportSize: viewportPoints,
                zNear: 0.01,
                zFar: 8
            )

            if model.showsVolume {
                let entry = smoothStep(0.04, 0.30, penetration.fraction)
                let ghostAlpha = 1 - 0.85 * entry
                let viewProjection = ARSlicePlacement.volumeViewProjection(
                    viewMatrix: rawView,
                    projectionMatrix: projection,
                    anchorTransform: anchorTransform
                )
                renderer.drawRayMarch(
                    into: encoder,
                    viewProjection: viewProjection,
                    cameraLocal: clip.point,
                    lightDirection: simd_normalize(clip.normal + SIMD3<Float>(0.2, 0.35, 0)),
                    window: model.window,
                    presentation: model.preset == .softTissue ? .softTissue : .bone,
                    clip: clip,
                    globalAlpha: ghostAlpha
                )
            }

            let planeToLocal = ARSlicePlacement.frustumPlaneToLocalMillimetres(
                viewMatrix: sliceView,
                projectionMatrix: projection,
                anchorTransform: anchorTransform,
                planeDistanceMetres: planeDistanceMetres
            )
            renderer.drawCrossSection(
                into: encoder,
                planeToLocal: planeToLocal,
                window: model.window,
                alpha: 1,
                airThresholdHU: -300
            )

            drawNavigator(
                into: encoder,
                view: view,
                sliceView: sliceView,
                anchorTransform: anchorTransform,
                clip: clip,
                halfExtent: halfExtent
            )
        }

        private func drawNavigator(
            into encoder: MTLRenderCommandEncoder,
            view: MTKView,
            sliceView: simd_float4x4,
            anchorTransform: simd_float4x4,
            clip: (point: SIMD3<Float>, normal: SIMD3<Float>),
            halfExtent: SIMD3<Float>
        ) {
            let boundsWidth = max(view.bounds.width, 1)
            let scale = Double(view.drawableSize.width) / Double(boundsWidth)
            let sizePoints = 124.0
            let marginPoints = 14.0
            let topPoints = 116.0
            let viewport = MTLViewport(
                originX: Double(view.drawableSize.width) - (sizePoints + marginPoints) * scale,
                originY: topPoints * scale,
                width: sizePoints * scale,
                height: sizePoints * scale,
                znear: 0,
                zfar: 1
            )
            encoder.setViewport(viewport)

            let worldFromEye = sliceView.inverse
            let eyeWorld = SIMD3<Float>(
                worldFromEye.columns.3.x,
                worldFromEye.columns.3.y,
                worldFromEye.columns.3.z
            )
            let localFromWorld = anchorTransform.inverse
            let eyeLocal4 = localFromWorld * SIMD4<Float>(eyeWorld, 1)
            let eyeLocalMM = SIMD3<Float>(eyeLocal4.x, eyeLocal4.y, eyeLocal4.z) * 1000
            let radius = simd_length(halfExtent)
            let viewProjection = ARSlicePlacement.navigatorViewProjection(
                eyeLocalMM: eyeLocalMM,
                radiusMM: radius
            )
            renderer.drawRayMarch(
                into: encoder,
                viewProjection: viewProjection,
                cameraLocal: eyeLocalMM,
                lightDirection: simd_normalize(SIMD3<Float>(0.35, -0.5, 0.75)),
                window: model.window,
                presentation: .bone,
                clip: clip,
                globalAlpha: 1,
                emptyAlpha: 0.55
            )

            encoder.setViewport(MTLViewport(
                originX: 0,
                originY: 0,
                width: Double(view.drawableSize.width),
                height: Double(view.drawableSize.height),
                znear: 0,
                zfar: 1
            ))
        }

        private func finishFrame(buffer: MTLCommandBuffer, drawable: CAMetalDrawable) {
            var staging: MTLTexture?
            if model.captureRequested, let blit = buffer.makeBlitCommandEncoder() {
                let source = drawable.texture
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: source.pixelFormat,
                    width: source.width,
                    height: source.height,
                    mipmapped: false
                )
                descriptor.usage = .shaderRead
                descriptor.storageMode = .shared
                if let target = renderer.device.makeTexture(descriptor: descriptor) {
                    blit.copy(from: source, to: target)
                    staging = target
                }
                blit.endEncoding()
            }
            buffer.present(drawable)
            buffer.commit()
            guard model.captureRequested else { return }
            model.captureRequested = false
            guard let staging else { return }
            buffer.waitUntilCompleted()
            model.lastCapture = TextureImageReader.image(from: staging)
        }

        private func smoothStep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
            let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
            return t * t * (3 - 2 * t)
        }
    }
}

extension ARSliceModel {
    static func matrix(from transform: CGAffineTransform) -> simd_float4x4 {
        simd_float4x4(
            SIMD4<Float>(Float(transform.a), Float(transform.b), 0, 0),
            SIMD4<Float>(Float(transform.c), Float(transform.d), 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(Float(transform.tx), Float(transform.ty), 0, 1)
        )
    }
}
