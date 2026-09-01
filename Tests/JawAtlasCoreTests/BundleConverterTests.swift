import XCTest
@testable import JawAtlasCore

final class BundleConverterTests: XCTestCase {
    private var workDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var casesDirectory = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        workDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("convert-\(UUID().uuidString)", isDirectory: true)
        casesDirectory = workDirectory.appendingPathComponent("Cases", isDirectory: true)
        try FileManager.default.createDirectory(at: casesDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    private func makeCandidate(
        slices: Int = 6,
        rows: Int = 8,
        columns: Int = 8,
        patientName: String? = "DOE^JANE",
        valueFor: @escaping (Int, Int) -> UInt16 = { index, voxel in UInt16(1000 + (index * 7 + voxel) % 500) }
    ) throws -> SeriesCandidate {
        let source = workDirectory.appendingPathComponent("dicom", isDirectory: true)
        let urls = try FixtureSeries.write(
            into: source,
            slices: slices,
            rows: rows,
            columns: columns,
            patientName: patientName,
            valueFor: valueFor
        )
        let parsed = try urls.map { try DICOMParser.parse(fileAt: $0) }
        return try XCTUnwrap(SeriesBuilder.build(from: parsed).candidates.first)
    }

    func testProducesValidBundle() throws {
        let candidate = try makeCandidate()
        let record = try BundleConverter.convert(
            candidate: candidate,
            label: "Test Scan",
            casesDirectory: casesDirectory
        )
        XCTAssertEqual(record.dimensions, [8, 8, 6])
        let manifest = try IntegrityVerifier.loadManifest(in: record.directory)
        try IntegrityVerifier.deepVerify(manifest: manifest, directory: record.directory)
        XCTAssertEqual(manifest.format, "jawatlas.bundle")
        XCTAssertEqual(manifest.version, 1)
        XCTAssertEqual(manifest.dtype, "int16")
        XCTAssertTrue(manifest.huRescaled)
        XCTAssertEqual(manifest.volumeByteCount, 8 * 8 * 6 * 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: BundleLayout.thumbnailURL(in: record.directory).path))
    }

    func testHounsfieldRoundTripAtProbeVoxels() throws {
        let candidate = try makeCandidate(slices: 5, rows: 4, columns: 4) { index, voxel in
            UInt16(1000 + index * 10 + voxel)
        }
        let record = try BundleConverter.convert(
            candidate: candidate,
            label: "Probe",
            casesDirectory: casesDirectory
        )
        let data = try Data(contentsOf: BundleLayout.volumeURL(in: record.directory))
        let voxels: [Int16] = data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Int16.self))
        }
        for k in 0..<5 {
            for voxel in [0, 3, 7, 15] {
                let expected = Int16(1000 + k * 10 + voxel - 1000)
                XCTAssertEqual(voxels[k * 16 + voxel], expected)
            }
        }
    }

    func testOrientationMatrixIsRowMajorThreeByFour() throws {
        let candidate = try makeCandidate()
        let matrix = BundleConverter.orientationMatrix(for: candidate)
        XCTAssertEqual(matrix.count, 3)
        XCTAssertTrue(matrix.allSatisfy { $0.count == 4 })
        XCTAssertEqual(matrix[0], [1, 0, 0, 0])
        XCTAssertEqual(matrix[1], [0, 1, 0, 0])
        XCTAssertEqual(matrix[2], [0, 0, 1, 0])
    }

    func testManifestRoundTripIsStable() throws {
        let manifest = BundleManifest(
            caseID: "ABC",
            label: "Round Trip",
            importedAt: Date(timeIntervalSince1970: 1_700_000_000),
            dimensions: [4, 5, 6],
            spacingMM: [0.3, 0.3, 0.4],
            orientation: [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0]],
            originMM: [-1, -2, -3],
            volumeSHA256: "deadbeef",
            isGapped: true,
            seriesUIDHash: "cafe"
        )
        let data = try BundleManifest.encoder().encode(manifest)
        let decoded = try BundleManifest.decoder().decode(BundleManifest.self, from: data)
        XCTAssertEqual(manifest, decoded)
        XCTAssertEqual(try BundleManifest.encoder().encode(decoded), data)
        XCTAssertEqual(decoded.flatOrientation.count, 12)
    }

    func testDenyListStopsIdentifierLeak() throws {
        let candidate = try makeCandidate(patientName: "LEAKY^NAME")
        XCTAssertThrowsError(
            try BundleConverter.convert(
                candidate: candidate,
                label: "LEAKY^NAME jaw",
                casesDirectory: casesDirectory
            )
        ) { error in
            guard case ImportError.identifierLeak = error else {
                return XCTFail("expected identifier leak, got \(error)")
            }
        }
        let leftovers = try FileManager.default.contentsOfDirectory(at: casesDirectory, includingPropertiesForKeys: nil)
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testBundleContainsNoIdentifiersOrDICOMMagic() throws {
        let candidate = try makeCandidate(patientName: "SUNILBHAI M_32YRS")
        let record = try BundleConverter.convert(
            candidate: candidate,
            label: "Anonymous Scan",
            casesDirectory: casesDirectory
        )
        let manifestData = try Data(contentsOf: BundleLayout.manifestURL(in: record.directory))
        let text = try XCTUnwrap(String(data: manifestData, encoding: .utf8))
        XCTAssertFalse(text.contains("SUNILBHAI"))
        XCTAssertFalse(text.uppercased().contains("DICM"))
        XCTAssertNil(IntegrityVerifier.denyListHit(in: manifestData, denyValues: ["SUNILBHAI M_32YRS"]))
    }

    func testCancellationLeavesNoCaseBehind() async throws {
        let candidate = try makeCandidate(slices: 40, rows: 64, columns: 64)
        let cases = casesDirectory
        let task = Task.detached {
            try BundleConverter.convert(candidate: candidate, label: "Cancelled", casesDirectory: cases)
        }
        task.cancel()
        let outcome = await task.result
        if case .success = outcome {
            let entries = try FileManager.default.contentsOfDirectory(at: cases, includingPropertiesForKeys: nil)
            XCTAssertLessThanOrEqual(entries.count, 1)
            return
        }
        let entries = try FileManager.default.contentsOfDirectory(at: cases, includingPropertiesForKeys: nil)
        XCTAssertTrue(entries.isEmpty)
    }

    func testPartialResidueIsSweptAndCaseHidden() async throws {
        let store = CaseStore(root: workDirectory.appendingPathComponent("store", isDirectory: true))
        try await store.prepare()
        let directory = await store.casesDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0, 1, 2, 3]).write(to: directory.appendingPathComponent("volume.i16.part"))
        let records = await store.reload()
        XCTAssertTrue(records.isEmpty)
        await store.sweep()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testUnreadableBundleIsReportedNotDeleted() async throws {
        let store = CaseStore(root: workDirectory.appendingPathComponent("store2", isDirectory: true))
        try await store.prepare()
        let candidate = try makeCandidate()
        let record = try await store.importSeries(candidate: candidate, label: "Damaged")
        try Data([1, 2, 3]).write(to: BundleLayout.volumeURL(in: record.directory))
        let records = await store.reload()
        XCTAssertEqual(records.count, 1)
        guard case .unreadable = records[0].status else {
            return XCTFail("expected an unreadable status")
        }
    }

    func testDeepVerifyDetectsTamperedVoxels() throws {
        let candidate = try makeCandidate()
        let record = try BundleConverter.convert(
            candidate: candidate,
            label: "Tamper",
            casesDirectory: casesDirectory
        )
        let manifest = try IntegrityVerifier.loadManifest(in: record.directory)
        var data = try Data(contentsOf: BundleLayout.volumeURL(in: record.directory))
        data[0] = data[0] &+ 1
        try data.write(to: BundleLayout.volumeURL(in: record.directory))
        XCTAssertThrowsError(try IntegrityVerifier.deepVerify(manifest: manifest, directory: record.directory)) { error in
            XCTAssertEqual(error as? VolumeError, VolumeError.hashMismatch)
        }
    }
}
