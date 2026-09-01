import XCTest
@testable import JawAtlasCore

final class CodecCompatibilityTests: XCTestCase {
    private var workDirectory = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        workDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    private func write(_ fixture: FixtureSlice, name: String = "slice.dcm") throws -> URL {
        let url = workDirectory.appendingPathComponent(name)
        try fixture.encoded().write(to: url)
        return url
    }

    private func decodeAll(_ url: URL) throws -> [Int16] {
        let slice = try DICOMParser.parse(fileAt: url)
        var output = [Int16](repeating: 0, count: slice.voxelsPerSlice)
        try PixelDecoder.decodeFrame(fileAt: url, slice: slice, into: &output)
        return output
    }

    private func testPixels(count: Int, seed: UInt64) -> [UInt16] {
        var generator = DeterministicGenerator(seed: seed)
        return (0..<count).map { _ in UInt16(generator.next() % 3800) }
    }

    func testDeflatedDatasetRoundTrips() throws {
        var fixture = FixtureSlice()
        fixture.syntax = .deflated
        fixture.rows = 6
        fixture.columns = 6
        fixture.pixels = testPixels(count: 36, seed: 1)
        let url = try write(fixture)
        XCTAssertTrue(DICOMParser.isDICOM(fileAt: url))
        let decoded = try decodeAll(url)
        let expected = fixture.pixels.map { Int16(clamping: Int($0) - 1000) }
        XCTAssertEqual(decoded, expected)
    }

    func testRLERoundTrips() throws {
        var fixture = FixtureSlice()
        fixture.syntax = .rle
        fixture.rows = 8
        fixture.columns = 8
        fixture.pixels = testPixels(count: 64, seed: 2)
        let url = try write(fixture)
        let decoded = try decodeAll(url)
        let expected = fixture.pixels.map { Int16(clamping: Int($0) - 1000) }
        XCTAssertEqual(decoded, expected)
    }

    func testRLEWithLongRunsRoundTrips() throws {
        var fixture = FixtureSlice()
        fixture.syntax = .rle
        fixture.rows = 16
        fixture.columns = 16
        fixture.pixels = (0..<256).map { $0 < 200 ? UInt16(700) : UInt16($0) }
        let url = try write(fixture)
        let decoded = try decodeAll(url)
        XCTAssertEqual(decoded[0], -300)
        XCTAssertEqual(decoded[199], -300)
        XCTAssertEqual(decoded[255], Int16(255 - 1000))
    }

    func testJPEGLosslessGradientRoundTrips() throws {
        var fixture = FixtureSlice()
        fixture.syntax = .jpegLossless
        fixture.rows = 12
        fixture.columns = 10
        fixture.pixels = (0..<120).map { UInt16(($0 * 23) % 4096) }
        let url = try write(fixture)
        let decoded = try decodeAll(url)
        let expected = fixture.pixels.map { Int16(clamping: Int($0) - 1000) }
        XCTAssertEqual(decoded, expected)
    }

    func testJPEGLosslessRandomRoundTrips() throws {
        var fixture = FixtureSlice()
        fixture.syntax = .jpegLossless
        fixture.rows = 20
        fixture.columns = 20
        fixture.pixels = testPixels(count: 400, seed: 3)
        let url = try write(fixture)
        let decoded = try decodeAll(url)
        let expected = fixture.pixels.map { Int16(clamping: Int($0) - 1000) }
        XCTAssertEqual(decoded, expected)
    }

    func testHeaderlessDatasetParses() throws {
        var fixture = FixtureSlice()
        fixture.syntax = .headerless
        fixture.rows = 4
        fixture.columns = 4
        fixture.pixels = testPixels(count: 16, seed: 4)
        let url = try write(fixture)
        XCTAssertTrue(DICOMParser.isDICOM(fileAt: url))
        let decoded = try decodeAll(url)
        let expected = fixture.pixels.map { Int16(clamping: Int($0) - 1000) }
        XCTAssertEqual(decoded, expected)
    }

    func testMonochromeOneWithoutRescaleInverts() throws {
        var fixture = FixtureSlice()
        fixture.photometric = "MONOCHROME1"
        fixture.includeRescale = false
        fixture.rows = 2
        fixture.columns = 2
        fixture.pixels = [0, 65535, 30000, 40000]
        let url = try write(fixture)
        let slice = try DICOMParser.parse(fileAt: url)
        XCTAssertTrue(slice.isInvertedGrey)
        var output = [Int16](repeating: 0, count: 4)
        try PixelDecoder.decodeFrame(fileAt: url, slice: slice, into: &output)
        XCTAssertEqual(output[0], Int16.max)
        XCTAssertEqual(output[1], 0)
    }

    func testMultiFrameFileExpandsIntoOrderedSlices() throws {
        var fixture = FixtureSlice()
        fixture.frames = 5
        fixture.rows = 4
        fixture.columns = 4
        fixture.spacingBetweenSlices = "0.5"
        fixture.pixels = (0..<80).map { UInt16(1000 + $0) }
        let url = try write(fixture)
        let slices = try DICOMParser.parseExpanded(fileAt: url)
        XCTAssertEqual(slices.count, 5)
        XCTAssertEqual(slices[3].position.z, 1.5, accuracy: 1e-9)
        var output = [Int16](repeating: 0, count: 16)
        try PixelDecoder.decodeFrame(fileAt: url, slice: slices[2], into: &output)
        XCTAssertEqual(output[0], Int16(1000 + 32 - 1000))
        let result = SeriesBuilder.build(from: slices)
        XCTAssertEqual(result.candidates.first?.slices.count, 5)
        XCTAssertEqual(result.candidates.first?.spacingMM.z ?? 0, 0.5, accuracy: 1e-9)
    }

    func testMissingRescaleTriggersAirCalibration() throws {
        let source = workDirectory.appendingPathComponent("noscale", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        var urls: [URL] = []
        for index in 0..<6 {
            var fixture = FixtureSlice()
            fixture.includeRescale = false
            fixture.rows = 32
            fixture.columns = 32
            fixture.position = "0\\0\\\(Double(index) * 0.3)"
            fixture.spacingBetweenSlices = nil
            fixture.pixels = (0..<1024).map { voxel -> UInt16 in
                let x = voxel % 32
                let y = voxel / 32
                let inCore = x > 8 && x < 24 && y > 8 && y < 24
                return inCore ? 1400 : 20
            }
            let url = source.appendingPathComponent("s\(index).dcm")
            try fixture.encoded().write(to: url)
            urls.append(url)
        }
        let parsed = try urls.flatMap { try DICOMParser.parseExpanded(fileAt: $0) }
        let candidate = try XCTUnwrap(SeriesBuilder.build(from: parsed).candidates.first)
        let cases = workDirectory.appendingPathComponent("cases", isDirectory: true)
        try FileManager.default.createDirectory(at: cases, withIntermediateDirectories: true)
        let record = try BundleConverter.convert(candidate: candidate, label: "Raw", casesDirectory: cases)
        let data = try Data(contentsOf: BundleLayout.volumeURL(in: record.directory))
        let voxels: [Int16] = data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        XCTAssertEqual(Double(voxels[0]), -1020, accuracy: 40)
        let core = voxels[16 * 32 + 16]
        XCTAssertEqual(Double(core), 360, accuracy: 40)
    }

    func testRescaledSeriesIsNotRecalibrated() throws {
        var fixture = FixtureSlice()
        fixture.rows = 4
        fixture.columns = 4
        fixture.pixels = [UInt16](repeating: 0, count: 16)
        let url = try write(fixture)
        let decoded = try decodeAll(url)
        XCTAssertEqual(decoded[0], -1000)
    }

    func testJPEG2000IsRejectedWithAReadableName() throws {
        var fixture = FixtureSlice()
        fixture.syntax = .compressed("1.2.840.10008.1.2.4.90")
        let url = try write(fixture)
        XCTAssertThrowsError(try DICOMParser.parse(fileAt: url)) { error in
            guard case let DICOMError.unsupportedTransferSyntax(name) = error else {
                return XCTFail("expected transfer syntax error, got \(error)")
            }
            XCTAssertTrue(name.contains("JPEG 2000"))
            XCTAssertTrue(name.contains("re-export"))
        }
    }

    func testCorruptEncapsulatedStreamsFailGracefully() throws {
        var fixture = FixtureSlice()
        fixture.syntax = .jpegLossless
        fixture.rows = 8
        fixture.columns = 8
        fixture.pixels = testPixels(count: 64, seed: 5)
        let full = fixture.encoded()
        var generator = DeterministicGenerator(seed: 6)
        for round in 0..<80 {
            var mutated = Array(full)
            switch round % 3 {
            case 0:
                mutated = Array(mutated.prefix(mutated.count - 1 - Int(generator.next() % 400)))
            case 1:
                for _ in 0..<8 {
                    let position = Int(generator.next() % UInt64(mutated.count))
                    mutated[position] = UInt8(generator.next() % 256)
                }
            default:
                let position = Int(generator.next() % UInt64(mutated.count))
                mutated.insert(0xFF, at: position)
            }
            let url = workDirectory.appendingPathComponent("fuzz-\(round).dcm")
            try Data(mutated).write(to: url)
            do {
                let slice = try DICOMParser.parse(fileAt: url)
                var output = [Int16](repeating: 0, count: slice.voxelsPerSlice)
                try PixelDecoder.decodeFrame(fileAt: url, slice: slice, into: &output)
            } catch {
                XCTAssertTrue(error is DICOMError, "unexpected error \(error)")
            }
            try? FileManager.default.removeItem(at: url)
        }
    }
}
