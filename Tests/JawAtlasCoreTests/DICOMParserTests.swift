import XCTest
@testable import JawAtlasCore

final class DICOMParserTests: XCTestCase {
    private var workDirectory = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        workDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("parser-\(UUID().uuidString)", isDirectory: true)
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

    func testParsesExplicitVRLittleEndian() throws {
        var fixture = FixtureSlice()
        fixture.rows = 4
        fixture.columns = 6
        fixture.syntax = .explicitLittleEndian
        let slice = try DICOMParser.parse(fileAt: try write(fixture))
        XCTAssertEqual(slice.rows, 4)
        XCTAssertEqual(slice.columns, 6)
        XCTAssertEqual(slice.rowSpacingMM, 0.3, accuracy: 1e-9)
        XCTAssertEqual(slice.columnSpacingMM, 0.3, accuracy: 1e-9)
        XCTAssertEqual(slice.rescaleIntercept, -1000, accuracy: 1e-9)
        XCTAssertEqual(slice.seriesUID, "1.2.3.4.5")
    }

    func testParsesImplicitVRLittleEndian() throws {
        var fixture = FixtureSlice()
        fixture.syntax = .implicitLittleEndian
        let slice = try DICOMParser.parse(fileAt: try write(fixture))
        XCTAssertEqual(slice.rows, 8)
        XCTAssertEqual(slice.columns, 8)
        XCTAssertEqual(slice.studyUID, "1.2.3.4")
    }

    func testCapturesIdentifiersTransientlyForDenyList() throws {
        var fixture = FixtureSlice()
        fixture.patientName = "SMITH^JOHN"
        let slice = try DICOMParser.parse(fileAt: try write(fixture))
        XCTAssertTrue(slice.identifierValues.contains("SMITH^JOHN"))
    }

    func testRejectsCompressedTransferSyntaxNamingTheUID() throws {
        var fixture = FixtureSlice()
        fixture.syntax = .compressed("1.2.840.10008.1.2.4.90")
        XCTAssertThrowsError(try DICOMParser.parse(fileAt: try write(fixture))) { error in
            guard case let DICOMError.unsupportedTransferSyntax(name) = error else {
                return XCTFail("expected unsupported transfer syntax, got \(error)")
            }
            XCTAssertTrue(name.contains("1.2.840.10008.1.2.4.90"))
        }
    }

    func testRejectsEightBitPixelData() throws {
        var fixture = FixtureSlice()
        fixture.bitsAllocated = 8
        XCTAssertThrowsError(try DICOMParser.parse(fileAt: try write(fixture)))
    }

    func testSkipsUndefinedLengthSequence() throws {
        var fixture = FixtureSlice()
        fixture.undefinedLengthSequence = true
        let slice = try DICOMParser.parse(fileAt: try write(fixture))
        XCTAssertEqual(slice.rows, 8)
    }

    func testTruncatedFileThrowsInsteadOfCrashing() throws {
        var fixture = FixtureSlice()
        fixture.rows = 16
        fixture.columns = 16
        let full = fixture.encoded()
        let truncated = full.prefix(full.count - 200)
        let url = workDirectory.appendingPathComponent("truncated.dcm")
        try truncated.write(to: url)
        XCTAssertThrowsError(try DICOMParser.parse(fileAt: url))
    }

    func testNonDICOMFileIsRejected() throws {
        let url = workDirectory.appendingPathComponent("notes.txt")
        try Data("this is not a scan".utf8).write(to: url)
        XCTAssertFalse(DICOMParser.isDICOM(fileAt: url))
        XCTAssertThrowsError(try DICOMParser.parse(fileAt: url))
    }

    func testEmptyFileIsRejected() throws {
        let url = workDirectory.appendingPathComponent("empty.dcm")
        try Data().write(to: url)
        XCTAssertFalse(DICOMParser.isDICOM(fileAt: url))
        XCTAssertThrowsError(try DICOMParser.parse(fileAt: url))
    }

    func testMissingPixelDataIsRejected() throws {
        var fixture = FixtureSlice()
        fixture.includePixelData = false
        XCTAssertThrowsError(try DICOMParser.parse(fileAt: try write(fixture)))
    }

    func testFuzzCorpusNeverCrashes() throws {
        var generator = DeterministicGenerator(seed: 0x5EED)
        let base = FixtureSlice().encoded()
        var handled = 0
        for index in 0..<240 {
            var mutated = Array(base)
            switch index % 4 {
            case 0:
                let cut = Int(generator.next() % UInt64(mutated.count))
                mutated = Array(mutated.prefix(cut))
            case 1:
                for _ in 0..<16 {
                    let position = Int(generator.next() % UInt64(max(1, mutated.count)))
                    mutated[position] = UInt8(generator.next() % 256)
                }
            case 2:
                let position = 132 + Int(generator.next() % UInt64(max(1, mutated.count - 132)))
                mutated.insert(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF], at: min(position, mutated.count))
            default:
                mutated = (0..<Int(generator.next() % 4096)).map { _ in UInt8(generator.next() % 256) }
            }
            let url = workDirectory.appendingPathComponent("fuzz-\(index).dcm")
            try Data(mutated).write(to: url)
            do {
                _ = try DICOMParser.parse(fileAt: url)
            } catch {
                XCTAssertTrue(error is DICOMError, "unexpected error type \(error)")
            }
            handled += 1
            try? FileManager.default.removeItem(at: url)
        }
        XCTAssertEqual(handled, 240)
    }

    func testDecodesUnsignedPixelsToHounsfield() throws {
        var fixture = FixtureSlice()
        fixture.rows = 2
        fixture.columns = 2
        fixture.pixelRepresentation = 0
        fixture.pixels = [0, 1000, 2000, 3000]
        let slice = try DICOMParser.parse(fileAt: try write(fixture))
        var output = [Int16](repeating: 0, count: 4)
        let data = try Data(contentsOf: slice.sourceURL)
        try data.withUnsafeBytes { raw in
            try PixelDecoder.decodeHounsfield(bytes: raw, slice: slice, into: &output)
        }
        XCTAssertEqual(output, [-1000, 0, 1000, 2000])
    }

    func testDecodesSignedPixelsToHounsfield() throws {
        var fixture = FixtureSlice()
        fixture.rows = 2
        fixture.columns = 2
        fixture.pixelRepresentation = 1
        fixture.intercept = "0"
        fixture.pixels = [UInt16(bitPattern: -500), UInt16(bitPattern: -1), 0, 500]
        let slice = try DICOMParser.parse(fileAt: try write(fixture))
        var output = [Int16](repeating: 0, count: 4)
        let data = try Data(contentsOf: slice.sourceURL)
        try data.withUnsafeBytes { raw in
            try PixelDecoder.decodeHounsfield(bytes: raw, slice: slice, into: &output)
        }
        XCTAssertEqual(output, [-500, -1, 0, 500])
    }

    func testSaturatesOutOfRangeHounsfieldValues() throws {
        var fixture = FixtureSlice()
        fixture.rows = 1
        fixture.columns = 2
        fixture.slope = "100"
        fixture.intercept = "0"
        fixture.pixels = [60000, 0]
        let slice = try DICOMParser.parse(fileAt: try write(fixture))
        var output = [Int16](repeating: 0, count: 2)
        let data = try Data(contentsOf: slice.sourceURL)
        try data.withUnsafeBytes { raw in
            try PixelDecoder.decodeHounsfield(bytes: raw, slice: slice, into: &output)
        }
        XCTAssertEqual(output[0], Int16.max)
        XCTAssertEqual(output[1], 0)
    }
}

struct DeterministicGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return (state >> 17) ^ state
    }
}
