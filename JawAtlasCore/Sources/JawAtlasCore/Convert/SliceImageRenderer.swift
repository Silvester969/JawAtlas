import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum SliceImageRenderer {
    public static func makeImage(
        from voxels: UnsafeBufferPointer<Int16>,
        width: Int,
        height: Int,
        window: WindowLevel,
        maximumEdge: Int? = nil
    ) -> CGImage? {
        guard width > 0, height > 0, voxels.count >= width * height else { return nil }
        var gray = [UInt8](repeating: 0, count: width * height)
        let low = window.center - window.width / 2
        let scale = 255.0 / window.width
        for index in 0..<(width * height) {
            let value = (Double(voxels[index]) - low) * scale
            gray[index] = UInt8(min(max(value, 0), 255))
        }
        guard let provider = CGDataProvider(data: Data(gray) as CFData) else { return nil }
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else { return nil }
        guard let limit = maximumEdge, max(width, height) > limit else { return image }
        return resize(image, maximumEdge: limit)
    }

    public static func resize(_ image: CGImage, maximumEdge: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > maximumEdge else { return image }
        let factor = Double(maximumEdge) / Double(longest)
        let targetWidth = max(1, Int((Double(image.width) * factor).rounded()))
        let targetHeight = max(1, Int((Double(image.height) * factor).rounded()))
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage()
    }

    public static func pngData(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    public static func thumbnailPNG(
        from voxels: UnsafeBufferPointer<Int16>,
        width: Int,
        height: Int,
        maximumEdge: Int = 512
    ) -> Data? {
        guard let image = makeImage(
            from: voxels,
            width: width,
            height: height,
            window: .bone,
            maximumEdge: maximumEdge
        ) else { return nil }
        return pngData(image)
    }
}
