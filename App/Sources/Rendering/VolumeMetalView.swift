import SwiftUI
import MetalKit
import simd
import JawAtlasCore

enum VolumeSceneMode {
    case volume
    case crossSection(simd_float4x4)
    case panoramic([SIMD3<Float>], slabMM: Float)
}

struct VolumeMetalView: UIViewRepresentable {
    let renderer: VolumeRenderer
    let mode: VolumeSceneMode
    let camera: OrbitCamera
    let window: WindowLevel
    let presentation: VolumePresentation
    var shaded: Bool = true
    var mip: Bool = false
    let isPaused: Bool
    var onTwoFingerPan: ((CGSize, CGSize) -> Void)? = nil
    var onTwoFingerActive: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isOpaque = false
        view.backgroundColor = .clear
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.delegate = context.coordinator
        let panRecognizer = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTwoFingerPan(_:))
        )
        panRecognizer.minimumNumberOfTouches = 2
        panRecognizer.maximumNumberOfTouches = 2
        panRecognizer.delegate = context.coordinator
        view.addGestureRecognizer(panRecognizer)
        try? renderer.preparePipelines(colorFormat: view.colorPixelFormat)
        context.coordinator.apply(
            mode: mode, camera: camera, window: window,
            presentation: presentation, shaded: shaded, mip: mip
        )
        context.coordinator.onTwoFingerPan = onTwoFingerPan
        context.coordinator.onTwoFingerActive = onTwoFingerActive
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.apply(
            mode: mode, camera: camera, window: window,
            presentation: presentation, shaded: shaded, mip: mip
        )
        context.coordinator.onTwoFingerPan = onTwoFingerPan
        context.coordinator.onTwoFingerActive = onTwoFingerActive
        view.setNeedsDisplay()
    }

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate, UIGestureRecognizerDelegate {
        private let renderer: VolumeRenderer
        var onTwoFingerPan: ((CGSize, CGSize) -> Void)?
        var onTwoFingerActive: ((Bool) -> Void)?
        private var lastPanTranslation = CGPoint.zero
        private var mode: VolumeSceneMode = .volume
        private var camera = OrbitCamera()
        private var window = WindowLevel.bone
        private var presentation = VolumePresentation.bone
        private var shaded = true
        private var mip = false

        init(renderer: VolumeRenderer) {
            self.renderer = renderer
        }

        func apply(
            mode: VolumeSceneMode,
            camera: OrbitCamera,
            window: WindowLevel,
            presentation: VolumePresentation,
            shaded: Bool,
            mip: Bool
        ) {
            self.mode = mode
            self.camera = camera
            self.window = window
            self.presentation = presentation
            self.shaded = shaded
            self.mip = mip
        }

        nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        }

        @objc func handleTwoFingerPan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            switch recognizer.state {
            case .began:
                lastPanTranslation = .zero
                onTwoFingerActive?(true)
            case .changed:
                let translation = recognizer.translation(in: view)
                let delta = CGSize(
                    width: translation.x - lastPanTranslation.x,
                    height: translation.y - lastPanTranslation.y
                )
                lastPanTranslation = translation
                onTwoFingerPan?(delta, view.bounds.size)
            default:
                onTwoFingerActive?(false)
            }
        }

        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        nonisolated func draw(in view: MTKView) {
            MainActor.assumeIsolated {
                render(in: view)
            }
        }

        private func render(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor,
                  let buffer = renderer.commandQueue.makeCommandBuffer(),
                  let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                return
            }
            let size = view.drawableSize
            let aspect = Float(max(size.width, 1) / max(size.height, 1))
            switch mode {
            case .volume:
                renderer.drawRayMarch(
                    into: encoder,
                    camera: camera,
                    aspect: aspect,
                    window: window,
                    presentation: presentation,
                    shaded: shaded,
                    mip: mip
                )
            case let .crossSection(planeToLocal):
                renderer.drawCrossSection(
                    into: encoder,
                    planeToLocal: planeToLocal,
                    window: window,
                    alpha: 1
                )
            case let .panoramic(points, slabMM):
                renderer.drawPanoramic(
                    into: encoder,
                    archPointsLocalMM: points,
                    window: window,
                    slabMM: slabMM
                )
            }
            encoder.endEncoding()
            buffer.present(drawable)
            buffer.commit()
        }
    }
}
