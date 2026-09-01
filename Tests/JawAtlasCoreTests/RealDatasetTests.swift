import XCTest
@testable import JawAtlasCore

final class RealDatasetTests: XCTestCase {
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var datasetURL: URL {
        repositoryRoot.appendingPathComponent("data/raw/dens-invaginatus-cbct/DICOM", isDirectory: true)
    }

    private func requireDataset() throws -> URL {
        let url = RealDatasetTests.datasetURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Reference dataset is not available on this machine")
        }
        return url
    }

    func testScansEveryStudySeriesInTheReferenceDataset() throws {
        let dataset = try requireDataset()
        let result = try ImportPipeline.scan(urls: [dataset])
        XCTAssertGreaterThanOrEqual(result.candidates.count, 4)
        XCTAssertEqual(result.unreadableCount, 4)
        XCTAssertEqual(result.ignoredCount, 0)

        let preferred = try XCTUnwrap(result.preferredCandidate)
        XCTAssertTrue(preferred.isOriginalAcquisition)
        XCTAssertEqual(preferred.columns, 204)
        XCTAssertEqual(preferred.rows, 204)
        XCTAssertEqual(preferred.slices.count, 201)
        XCTAssertEqual(preferred.spacingMM.x, 0.3, accuracy: 1e-6)
        XCTAssertEqual(preferred.spacingMM.y, 0.3, accuracy: 1e-6)
        XCTAssertEqual(preferred.spacingMM.z, 0.3, accuracy: 1e-6)
        XCTAssertFalse(preferred.isGapped)
    }

    func testConvertsReferenceSeriesIntoAVerifiedBundle() async throws {
        let dataset = try requireDataset()
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("real-\(UUID().uuidString)", isDirectory: true)
        let cases = root.appendingPathComponent("Cases", isDirectory: true)
        try FileManager.default.createDirectory(at: cases, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try ImportPipeline.scan(urls: [dataset])
        let candidate = try XCTUnwrap(result.preferredCandidate)
        let record = try BundleConverter.convert(
            candidate: candidate,
            label: "Reference Scan",
            casesDirectory: cases
        )

        XCTAssertEqual(record.dimensions, [204, 204, 201])
        let manifest = try IntegrityVerifier.loadManifest(in: record.directory)
        try IntegrityVerifier.deepVerify(manifest: manifest, directory: record.directory)
        XCTAssertEqual(manifest.volumeByteCount, 204 * 204 * 201 * 2)
        XCTAssertTrue(manifest.huRescaled)

        let manifestData = try Data(contentsOf: BundleLayout.manifestURL(in: record.directory))
        let identifiers = Set(candidate.slices.flatMap { $0.identifierValues })
        XCTAssertFalse(identifiers.isEmpty)
        XCTAssertNil(IntegrityVerifier.denyListHit(in: manifestData, denyValues: Array(identifiers)))

        let store = CaseStore(root: root)
        _ = await store.reload()
        let handle = try await store.makeHandle(forCaseID: record.id)
        defer { handle.close() }
        XCTAssertEqual(handle.depth, 201)

        let middleSlice = try XCTUnwrap(handle.withSlice(100) { Array($0) })
        let minimum = try XCTUnwrap(middleSlice.min())
        let maximum = try XCTUnwrap(middleSlice.max())
        XCTAssertLessThanOrEqual(minimum, -500)
        XCTAssertGreaterThanOrEqual(maximum, 500)

        let source = candidate.slices[100]
        var expected = [Int16](repeating: 0, count: source.rows * source.columns)
        let raw = try Data(contentsOf: source.sourceURL, options: [.mappedIfSafe])
        try raw.withUnsafeBytes { pointer in
            try PixelDecoder.decodeHounsfield(bytes: pointer, slice: source, into: &expected)
        }
        for probe in [0, 1000, 20408, 41615] {
            XCTAssertEqual(middleSlice[probe], expected[probe])
        }
    }

    func testBundledDemoSeriesIsPresentAndImportable() async throws {
        guard let folder = DemoSeeder.seedURL(in: .main) else {
            throw XCTSkip("Demo seed is not bundled in this build")
        }
        let result = try ImportPipeline.scan(urls: [folder])
        let candidate = try XCTUnwrap(result.preferredCandidate)
        XCTAssertEqual(candidate.slices.count, 320)
        XCTAssertTrue(candidate.isOriginalAcquisition)
        XCTAssertEqual(candidate.slices[0].pixelRepresentation, 1)

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("seed-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CaseStore(root: root)
        try await store.prepare()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "demo-seed-\(UUID().uuidString)"))
        let outcome = try await DemoSeeder.seed(from: folder, into: store, defaults: defaults)
        XCTAssertTrue(outcome.wasCreated)
        XCTAssertEqual(outcome.record.label, DemoSeeder.demoLabel)
        XCTAssertEqual(outcome.record.dimensions, [480, 480, 320])
        XCTAssertEqual(DemoSeeder.storedDemoCaseID(defaults: defaults), outcome.record.id)

        let second = try await DemoSeeder.seed(from: folder, into: store, defaults: defaults)
        XCTAssertFalse(second.wasCreated)
        let finalRecords = await store.reload()
        XCTAssertEqual(finalRecords.count, 1)
    }
}
