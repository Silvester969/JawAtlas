import XCTest
@testable import JawAtlasCore

final class SeriesBuilderTests: XCTestCase {
    private var workDirectory = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        workDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("series-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    func testSortsSlicesByProjectionOntoNormal() throws {
        let urls = try FixtureSeries.write(into: workDirectory, slices: 12)
        var slices = try urls.map { try DICOMParser.parse(fileAt: $0) }
        slices.shuffle()
        let result = SeriesBuilder.build(from: slices)
        let candidate = try XCTUnwrap(result.candidates.first)
        let positions = candidate.slices.map { $0.positionAlongNormal }
        XCTAssertEqual(positions, positions.sorted())
        XCTAssertEqual(candidate.slices.count, 12)
    }

    func testSortsObliqueSeriesCorrectly() throws {
        let oblique = "1\\0\\0\\0\\0.707106\\-0.707106"
        let urls = try FixtureSeries.write(
            into: workDirectory,
            slices: 10,
            orientation: oblique
        )
        let slices = try urls.map { try DICOMParser.parse(fileAt: $0) }.shuffled()
        let result = SeriesBuilder.build(from: slices)
        let candidate = try XCTUnwrap(result.candidates.first)
        XCTAssertEqual(candidate.slices.count, 10)
        let positions = candidate.slices.map { $0.positionAlongNormal }
        XCTAssertEqual(positions, positions.sorted())
    }

    func testDerivesSpacingWhenSliceThicknessIsWrong() throws {
        let urls = try FixtureSeries.write(into: workDirectory, slices: 8, spacing: 0.3)
        let slices = try urls.map { try DICOMParser.parse(fileAt: $0) }
        let candidate = try XCTUnwrap(SeriesBuilder.build(from: slices).candidates.first)
        XCTAssertEqual(candidate.spacingMM.z, 0.3, accuracy: 1e-6)
    }

    func testSpacingResolutionOrderPrefersDeclaredValue() {
        XCTAssertEqual(SeriesBuilder.resolveSliceSpacing(declared: 0.5, derived: 0.3, thickness: 61.2), 0.5)
        XCTAssertEqual(SeriesBuilder.resolveSliceSpacing(declared: nil, derived: 0.3, thickness: 61.2), 0.3)
        XCTAssertEqual(SeriesBuilder.resolveSliceSpacing(declared: nil, derived: nil, thickness: 0.4), 0.4)
        XCTAssertNil(SeriesBuilder.resolveSliceSpacing(declared: 61.2, derived: nil, thickness: 61.2))
        XCTAssertNil(SeriesBuilder.resolveSliceSpacing(declared: 0, derived: -1, thickness: nil))
    }

    func testDetectsGaps() throws {
        let urls = try FixtureSeries.write(into: workDirectory, slices: 10, gapAt: 5)
        let slices = try urls.map { try DICOMParser.parse(fileAt: $0) }
        let candidate = try XCTUnwrap(SeriesBuilder.build(from: slices).candidates.first)
        XCTAssertTrue(candidate.isGapped)
    }

    func testContiguousSeriesIsNotGapped() throws {
        let urls = try FixtureSeries.write(into: workDirectory, slices: 10)
        let slices = try urls.map { try DICOMParser.parse(fileAt: $0) }
        let candidate = try XCTUnwrap(SeriesBuilder.build(from: slices).candidates.first)
        XCTAssertFalse(candidate.isGapped)
    }

    func testSeparatesDistinctSeries() throws {
        let first = workDirectory.appendingPathComponent("a", isDirectory: true)
        let second = workDirectory.appendingPathComponent("b", isDirectory: true)
        let urlsA = try FixtureSeries.write(into: first, slices: 6, seriesUID: "1.1.1")
        let urlsB = try FixtureSeries.write(into: second, slices: 8, seriesUID: "2.2.2")
        let slices = try (urlsA + urlsB).map { try DICOMParser.parse(fileAt: $0) }
        let result = SeriesBuilder.build(from: slices)
        XCTAssertEqual(result.candidates.count, 2)
        XCTAssertEqual(result.candidates.map(\.slices.count).sorted(), [6, 8])
    }

    func testRejectsSeriesBelowMinimumSliceCount() throws {
        let urls = try FixtureSeries.write(into: workDirectory, slices: 2)
        let slices = try urls.map { try DICOMParser.parse(fileAt: $0) }
        let result = SeriesBuilder.build(from: slices)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.rejectedSliceCount, 2)
    }

    func testPrefersOriginalAcquisitionOverDerived() throws {
        let original = workDirectory.appendingPathComponent("orig", isDirectory: true)
        let derived = workDirectory.appendingPathComponent("der", isDirectory: true)
        let urlsA = try FixtureSeries.write(into: original, slices: 6, seriesUID: "1.1.1")
        var derivedURLs: [URL] = []
        try FileManager.default.createDirectory(at: derived, withIntermediateDirectories: true)
        for index in 0..<20 {
            var fixture = FixtureSlice()
            fixture.imageType = "DERIVED\\SECONDARY\\REFORMATTED"
            fixture.seriesUID = "9.9.9"
            fixture.position = "0\\0\\\(Double(index) * 0.3)"
            fixture.spacingBetweenSlices = nil
            let url = derived.appendingPathComponent("d-\(index).dcm")
            try fixture.encoded().write(to: url)
            derivedURLs.append(url)
        }
        let slices = try (urlsA + derivedURLs).map { try DICOMParser.parse(fileAt: $0) }
        let result = SeriesBuilder.build(from: slices)
        XCTAssertEqual(result.preferredCandidate?.slices.count, 6)
        XCTAssertTrue(result.preferredCandidate?.isOriginalAcquisition == true)
    }
}
