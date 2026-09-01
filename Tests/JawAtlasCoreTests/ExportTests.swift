import XCTest
import UIKit
import simd
@testable import JawAtlas
@testable import JawAtlasCore

@MainActor
final class ExportTests: XCTestCase {
    private func makeGeometry() -> VolumeGeometry {
        VolumeGeometry(
            dimensions: (32, 32, 32),
            spacingMM: Vec3(1, 1, 1),
            originMM: Vec3(0, 0, 0),
            rowDirection: Vec3(1, 0, 0),
            columnDirection: Vec3(0, 1, 0),
            sliceNormal: Vec3(0, 0, 1)
        )
    }

    private func makeVoxels() -> [Int16] {
        var voxels = [Int16](repeating: -1000, count: 32 * 32 * 32)
        for z in 8..<24 {
            for y in 8..<24 {
                for x in 8..<24 {
                    voxels[(z * 32 + y) * 32 + x] = 1500
                }
            }
        }
        return voxels
    }

    private func makeLoadedRenderer() throws -> VolumeRenderer {
        guard let renderer = try? VolumeRenderer() else {
            throw XCTSkip("Metal is not available in this environment")
        }
        try renderer.upload(voxels: makeVoxels(), geometry: makeGeometry())
        return renderer
    }

    private func makeMoment(stage: MomentStage) -> StoryMoment {
        StoryMoment(
            title: "Middle of the jaw",
            caption: "The cut through the centre of the scan.",
            stage: stage,
            windowPreset: "bone",
            planeAzimuth: 0,
            planeOffsetMM: 0,
            planePanX: 0,
            planePanY: 0,
            planeSpanMM: 32,
            cameraAzimuth: 0.4,
            cameraElevation: 0.25,
            cameraDistance: 70,
            strokesLocalMM: [[Vec3(-5, 0, -5), Vec3(5, 0, 5)]]
        )
    }

    private func brightnessRange(of image: UIImage) throws -> (minimum: UInt8, maximum: UInt8) {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        try pixels.withUnsafeMutableBytes { raw in
            let context = try XCTUnwrap(CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let minimum = try XCTUnwrap(pixels.min())
        let maximum = try XCTUnwrap(pixels.max())
        return (minimum, maximum)
    }

    func testSliceMomentRendersRequestedSizeWithContent() throws {
        let renderer = try makeLoadedRenderer()
        let image = try XCTUnwrap(MomentImageRenderer.render(
            renderer: renderer,
            geometry: makeGeometry(),
            moment: makeMoment(stage: .slice),
            pixelSize: CGSize(width: 320, height: 400)
        ))
        XCTAssertEqual(image.size.width * image.scale, 320)
        XCTAssertEqual(image.size.height * image.scale, 400)
        let range = try brightnessRange(of: image)
        XCTAssertGreaterThan(range.maximum, 140)
        XCTAssertLessThan(range.minimum, 30)
    }

    func testVolumeMomentRendersContent() throws {
        let renderer = try makeLoadedRenderer()
        let image = try XCTUnwrap(MomentImageRenderer.render(
            renderer: renderer,
            geometry: makeGeometry(),
            moment: makeMoment(stage: .volume),
            pixelSize: CGSize(width: 240, height: 300)
        ))
        let range = try brightnessRange(of: image)
        XCTAssertGreaterThan(range.maximum, 90)
        XCTAssertLessThan(range.minimum, 30)
    }

    func testStrokeMappingRoundTrips() {
        let matrix = SlicePlaneMath.planeToLocal(
            azimuth: 0.7,
            offsetMM: 5,
            pan: SIMD2<Float>(3, -2),
            spanMM: 40,
            aspect: 0.8
        )
        let samples: [SIMD2<Float>] = [
            SIMD2<Float>(-1, -1),
            SIMD2<Float>(0.25, 0.5),
            SIMD2<Float>(1, 1),
            SIMD2<Float>(-0.4, 0.9)
        ]
        for sample in samples {
            let local4 = matrix * SIMD4<Float>(sample.x, sample.y, 0, 1)
            let recovered = MomentImageRenderer.planeUV(
                localMM: SIMD3<Float>(local4.x, local4.y, local4.z),
                planeToLocal: matrix
            )
            XCTAssertEqual(recovered.x, sample.x, accuracy: 1e-4)
            XCTAssertEqual(recovered.y, sample.y, accuracy: 1e-4)
        }
        let centre = MomentImageRenderer.pixelPoint(uv: SIMD2<Float>(0, 0), width: 200, height: 100)
        XCTAssertEqual(centre.x, 100, accuracy: 1e-6)
        XCTAssertEqual(centre.y, 50, accuracy: 1e-6)
        let topRight = MomentImageRenderer.pixelPoint(uv: SIMD2<Float>(1, 1), width: 200, height: 100)
        XCTAssertEqual(topRight.x, 200, accuracy: 1e-6)
        XCTAssertEqual(topRight.y, 0, accuracy: 1e-6)
    }

    private func solidImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func pdfPageCount(of data: Data) throws -> Int {
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        return document.numberOfPages
    }

    func testSummaryPDFHasOnePagePerMoment() throws {
        let image = solidImage(size: CGSize(width: 120, height: 150))
        let moments = (1...3).map {
            SummaryMoment(title: "Moment \($0)", caption: "What we looked at together.", image: image)
        }
        let summary = CaseSummary(caseLabel: "Demo Case", moments: moments)
        let data = summary.pdfData()
        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(try pdfPageCount(of: data), 3)

        let withPhoto = CaseSummary(
            caseLabel: "Demo Case",
            moments: moments,
            arPhoto: solidImage(size: CGSize(width: 90, height: 160))
        )
        XCTAssertEqual(try pdfPageCount(of: withPhoto.pdfData()), 4)
    }

    func testSummaryImagesMatchPageCount() {
        let image = solidImage(size: CGSize(width: 120, height: 150))
        let moments = (1...2).map {
            SummaryMoment(title: "Moment \($0)", caption: "", image: image)
        }
        let summary = CaseSummary(
            caseLabel: "Demo Case",
            moments: moments,
            arPhoto: solidImage(size: CGSize(width: 90, height: 160))
        )
        let pages = summary.images()
        XCTAssertEqual(pages.count, 3)
        for page in pages {
            XCTAssertEqual(page.size.width, CaseSummary.pageSize.width, accuracy: 0.5)
            XCTAssertEqual(page.size.height, CaseSummary.pageSize.height, accuracy: 0.5)
        }
    }
}
