import XCTest
@testable import JawAtlasCore

final class CaseStoreTests: XCTestCase {
    private var root = URL(fileURLWithPath: NSTemporaryDirectory())
    private var sourceDirectory = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("store-\(UUID().uuidString)", isDirectory: true)
        root = base.appendingPathComponent("JawAtlas", isDirectory: true)
        sourceDirectory = base.appendingPathComponent("dicom", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func makeStore() async throws -> CaseStore {
        let store = CaseStore(root: root)
        try await store.prepare()
        return store
    }

    private func importFixture(into store: CaseStore, label: String, seriesUID: String = "1.2.3.4.5") async throws -> CaseRecord {
        let directory = sourceDirectory.appendingPathComponent(seriesUID, isDirectory: true)
        let urls = try FixtureSeries.write(into: directory, slices: 6, seriesUID: seriesUID)
        let parsed = try urls.map { try DICOMParser.parse(fileAt: $0) }
        let candidate = try XCTUnwrap(SeriesBuilder.build(from: parsed).candidates.first)
        return try await store.importSeries(candidate: candidate, label: label)
    }

    func testImportListRenameDeleteCycle() async throws {
        let store = try await makeStore()
        let record = try await importFixture(into: store, label: "First Scan")
        var records = await store.records()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].label, "First Scan")

        try await store.rename(id: record.id, to: "Renamed Scan")
        records = await store.reload()
        XCTAssertEqual(records[0].label, "Renamed Scan")

        let bytesBefore = await store.totalStorageBytes()
        XCTAssertGreaterThan(bytesBefore, 0)

        await store.delete(id: record.id)
        records = await store.reload()
        XCTAssertTrue(records.isEmpty)
        let bytesAfter = await store.totalStorageBytes()
        XCTAssertEqual(bytesAfter, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.directory.path))
    }

    func testRelaunchRestoresLibrary() async throws {
        let store = try await makeStore()
        _ = try await importFixture(into: store, label: "Persisted")
        let reopened = CaseStore(root: root)
        try await reopened.prepare()
        let records = await reopened.reload()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].label, "Persisted")
    }

    func testDuplicateSeriesIsDetectedByHash() async throws {
        let store = try await makeStore()
        let record = try await importFixture(into: store, label: "Original")
        let existing = await store.record(seriesUIDHash: record.seriesUIDHash)
        XCTAssertEqual(existing?.id, record.id)
        let unrelated = await store.record(seriesUIDHash: "not-a-hash")
        XCTAssertNil(unrelated)
    }

    func testMakeHandleExposesMappedVoxels() async throws {
        let store = try await makeStore()
        let record = try await importFixture(into: store, label: "Mapped")
        let handle = try await store.makeHandle(forCaseID: record.id)
        defer { handle.close() }
        XCTAssertEqual(handle.width, 8)
        XCTAssertEqual(handle.height, 8)
        XCTAssertEqual(handle.depth, 6)
        XCTAssertEqual(handle.byteCount, 8 * 8 * 6 * 2)
        XCTAssertEqual(handle.orientation.count, 12)
        let middle = handle.withSlice(3) { buffer in Array(buffer.prefix(4)) }
        XCTAssertEqual(middle?.count, 4)
        XCTAssertNil(handle.sliceRange(-1))
        XCTAssertNil(handle.sliceRange(99))
    }

    func testMakeHandleForMissingCaseThrows() async throws {
        let store = try await makeStore()
        do {
            _ = try await store.makeHandle(forCaseID: "nope")
            XCTFail("expected a typed error")
        } catch let error as VolumeError {
            XCTAssertEqual(error, .caseMissing("nope"))
        }
    }

    func testSweepRemovesManifestlessDirectories() async throws {
        let store = try await makeStore()
        let orphan = await store.casesDirectory.appendingPathComponent("orphan", isDirectory: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try Data([9]).write(to: orphan.appendingPathComponent("volume.i16"))
        await store.sweep()
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    }

    func testImportPipelineCountsUnreadableAndIgnoredFiles() async throws {
        let directory = sourceDirectory.appendingPathComponent("mixed", isDirectory: true)
        _ = try FixtureSeries.write(into: directory, slices: 6)
        try Data("just a note".utf8).write(to: directory.appendingPathComponent("readme.txt"))
        var broken = Array(FixtureSlice().encoded())
        broken = Array(broken.prefix(200))
        try Data(broken).write(to: directory.appendingPathComponent("broken.dcm"))

        let result = try ImportPipeline.scan(urls: [directory])
        XCTAssertEqual(result.ignoredCount, 1)
        XCTAssertEqual(result.unreadableCount, 1)
        XCTAssertEqual(result.candidates.first?.slices.count, 6)
    }

    func testImportPipelineThrowsWhenNothingIsReadable() async throws {
        let directory = sourceDirectory.appendingPathComponent("junk", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("nothing here".utf8).write(to: directory.appendingPathComponent("a.txt"))
        XCTAssertThrowsError(try ImportPipeline.scan(urls: [directory])) { error in
            guard case ImportError.noReadableFiles = error else {
                return XCTFail("expected noReadableFiles, got \(error)")
            }
        }
    }
}
