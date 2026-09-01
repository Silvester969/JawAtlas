import UIKit
import Metal
import simd
import JawAtlasCore

enum TextureImageReader {
    static func image(from texture: MTLTexture) -> UIImage? {
        let width = texture.width
        let height = texture.height
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
        }
        let info = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: info,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

@MainActor
enum MomentImageRenderer {
    static let defaultPixelSize = CGSize(width: 1200, height: 1500)

    static func render(
        renderer: VolumeRenderer,
        geometry: VolumeGeometry,
        moment: StoryMoment,
        pixelSize: CGSize = defaultPixelSize
    ) -> UIImage? {
        let width = max(Int(pixelSize.width.rounded()), 16)
        let height = max(Int(pixelSize.height.rounded()), 16)
        guard let base = renderBase(renderer: renderer, moment: moment, width: width, height: height) else {
            return nil
        }
        return compose(base: base, moment: moment, width: width, height: height)
    }

    static func window(for moment: StoryMoment) -> WindowLevel {
        WindowPreset(rawValue: moment.windowPreset)?.level ?? .bone
    }

    static func presentation(for moment: StoryMoment) -> VolumePresentation {
        moment.windowPreset == WindowPreset.softTissue.rawValue ? .softTissue : .bone
    }

    static func planeMatrix(for moment: StoryMoment, aspect: Float) -> simd_float4x4 {
        SlicePlaneMath.planeToLocal(
            azimuth: Float(moment.planeAzimuth),
            elevation: Float(moment.planeElevation ?? 0),
            offsetMM: Float(moment.planeOffsetMM),
            pan: SIMD2<Float>(Float(moment.planePanX), Float(moment.planePanY)),
            spanMM: Float(moment.planeSpanMM),
            aspect: aspect
        )
    }

    static func planeUV(localMM: SIMD3<Float>, planeToLocal: simd_float4x4) -> SIMD2<Float> {
        let center = SIMD3<Float>(
            planeToLocal.columns.3.x,
            planeToLocal.columns.3.y,
            planeToLocal.columns.3.z
        )
        let axisU = SIMD3<Float>(
            planeToLocal.columns.0.x,
            planeToLocal.columns.0.y,
            planeToLocal.columns.0.z
        )
        let axisV = SIMD3<Float>(
            planeToLocal.columns.1.x,
            planeToLocal.columns.1.y,
            planeToLocal.columns.1.z
        )
        let delta = localMM - center
        let u = simd_dot(delta, axisU) / max(simd_length_squared(axisU), 1e-8)
        let v = simd_dot(delta, axisV) / max(simd_length_squared(axisV), 1e-8)
        return SIMD2<Float>(u, v)
    }

    static func pixelPoint(uv: SIMD2<Float>, width: Int, height: Int) -> CGPoint {
        CGPoint(
            x: CGFloat((uv.x + 1) / 2) * CGFloat(width),
            y: CGFloat((1 - uv.y) / 2) * CGFloat(height)
        )
    }

    private static func renderBase(
        renderer: VolumeRenderer,
        moment: StoryMoment,
        width: Int,
        height: Int
    ) -> UIImage? {
        guard (try? renderer.preparePipelines(colorFormat: .bgra8Unorm)) != nil else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let target = renderer.device.makeTexture(descriptor: descriptor) else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let buffer = renderer.commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else {
            return nil
        }

        let aspect = Float(width) / Float(height)
        switch moment.stage {
        case .slice:
            renderer.drawCrossSection(
                into: encoder,
                planeToLocal: planeMatrix(for: moment, aspect: aspect),
                window: window(for: moment),
                alpha: 1
            )
        case .volume:
            var camera = OrbitCamera()
            camera.azimuth = Float(moment.cameraAzimuth)
            camera.elevation = Float(moment.cameraElevation)
            camera.distance = Float(moment.cameraDistance)
            camera.target = .zero
            renderer.drawRayMarch(
                into: encoder,
                camera: camera,
                aspect: aspect,
                window: window(for: moment),
                presentation: presentation(for: moment)
            )
        }
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        return TextureImageReader.image(from: target)
    }

    private static func compose(base: UIImage, moment: StoryMoment, width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            base.draw(in: CGRect(origin: .zero, size: size))
            if moment.stage == .slice {
                drawStrokes(moment: moment, width: width, height: height, in: context.cgContext)
            }
            drawCaption(moment.caption, width: width, height: height)
        }
    }

    private static func drawStrokes(moment: StoryMoment, width: Int, height: Int, in context: CGContext) {
        guard !moment.strokesLocalMM.isEmpty else { return }
        let matrix = planeMatrix(for: moment, aspect: Float(width) / Float(height))
        let scale = CGFloat(width) / defaultPixelSize.width
        let lineWidth = max(4 * scale, 1.5)
        let glowColor = UIColor.white.withAlphaComponent(0.8)
        let strokeColor = UIColor(hex: 0x4DA3FF)
        for stroke in moment.strokesLocalMM {
            let points = stroke.map { point -> CGPoint in
                let local = SIMD3<Float>(Float(point.x), Float(point.y), Float(point.z))
                return pixelPoint(uv: planeUV(localMM: local, planeToLocal: matrix), width: width, height: height)
            }
            guard let first = points.first else { continue }
            let path = CGMutablePath()
            path.move(to: first)
            if points.count == 1 {
                path.addLine(to: CGPoint(x: first.x + 0.1, y: first.y))
            } else {
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            context.saveGState()
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addPath(path)
            context.setStrokeColor(glowColor.cgColor)
            context.setLineWidth(lineWidth * 2.4)
            context.strokePath()
            context.addPath(path)
            context.setStrokeColor(strokeColor.cgColor)
            context.setLineWidth(lineWidth)
            context.strokePath()
            context.restoreGState()
        }
    }

    private static func drawCaption(_ caption: String, width: Int, height: Int) {
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let scale = CGFloat(width) / defaultPixelSize.width
        let fontSize = max(44 * scale, 13)
        let inset = max(48 * scale, 12)
        let verticalPadding = max(36 * scale, 10)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textWidth = CGFloat(width) - inset * 2
        let bounding = attributed.boundingRect(
            with: CGSize(width: textWidth, height: CGFloat(height) / 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let barHeight = ceil(bounding.height) + verticalPadding * 2
        let barRect = CGRect(x: 0, y: CGFloat(height) - barHeight, width: CGFloat(width), height: barHeight)
        UIColor(white: 0.04, alpha: 0.94).setFill()
        UIRectFillUsingBlendMode(barRect, .normal)
        attributed.draw(
            with: CGRect(x: inset, y: barRect.minY + verticalPadding, width: textWidth, height: ceil(bounding.height)),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
    }
}
