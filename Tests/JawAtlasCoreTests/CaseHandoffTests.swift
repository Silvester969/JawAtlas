import XCTest
@testable import JawAtlasCore

final class CaseHandoffTests: XCTestCase {
    private var root = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("handoff-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeStore(_ name: String) async throws -> CaseStore {
        let store = CaseStore(root: root.appendingPathComponent(name, isDirectory: true))
        try await store.prepare()
        return store
    }

    private func importFixture(into store: CaseStore, label: String) async throws -> CaseRecord {
        let source = root.appendingPathComponent("dicom-\(UUID().uuidString)", isDirectory: true)
        let urls = try FixtureSeries.write(into: source, slices: 6)
        let parsed = try urls.map { try DICOMParser.parse(fileAt: $0) }
        let candidate = try XCTUnwrap(SeriesBuilder.build(from: parsed).candidates.first)
        return try await store.importSeries(candidate: candidate, label: label)
    }

    func testZipWriterRoundTripsThroughOwnReader() throws {
        let source = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let payload = Data((0..<70000).map { UInt8($0 % 251) })
        try payload.write(to: source.appendingPathComponent("volume.i16"))
        try Data("hello".utf8).write(to: source.appendingPathComponent("manifest.json"))

        let archive = root.appendingPathComponent("case.zip")
        try ZipWriter.writeArchive(of: source, to: archive)

        let out = root.appendingPathComponent("out", isDirectory: true)
        let reader = try ZipArchive(fileAt: archive)
        _ = try reader.extractAll(to: out)
        XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("volume.i16")), payload)
        XCTAssertEqual(
            String(data: try Data(contentsOf: out.appendingPathComponent("manifest.json")), encoding: .utf8),
            "hello"
        )
    }

    func testCrc32MatchesKnownVector() {
        XCTAssertEqual(ZipWriter.crc32(of: Data("123456789".utf8)), 0xCBF43926)
    }

    func testFullHandoffBetweenTwoStores() async throws {
        let sender = try await makeStore("sender")
        let record = try await importFixture(into: sender, label: "Molar case")
        try await sender.setPatientTag(id: record.id, to: "JD-104")
        var story = StoryState()
        story.notes = "Quote two implants, patient is anxious"
        story.moments.append(StoryMoment(
            title: "The gap",
            stage: .slice,
            windowPreset: "bone",
            planeAzimuth: 0.4,
            planeOffsetMM: 2,
            planePanX: 0,
            planePanY: 0,
            planeSpanMM: 90,
            cameraAzimuth: 0,
            cameraElevation: 0,
            cameraDistance: 200
        ))
        try StoryStateIO.save(story, to: record.directory)

        let archive = root.appendingPathComponent("transfer.zip")
        try await sender.exportPackage(id: record.id, to: archive)

        let received = root.appendingPathComponent("received", isDirectory: true)
        _ = try ZipArchive(fileAt: archive).extractAll(to: received)
        XCTAssertTrue(CaseStore.isCasePackage(received))

        let receiver = try await makeStore("receiver")
        let adoption = try await receiver.adoptPackage(at: received)
        XCTAssertFalse(adoption.merged)
        XCTAssertEqual(adoption.record.label, "Molar case")
        XCTAssertEqual(adoption.record.patientTag, "JD-104")

        let receivedStory = StoryStateIO.load(from: adoption.record.directory)
        XCTAssertEqual(receivedStory.notes, "Quote two implants, patient is anxious")
        XCTAssertEqual(receivedStory.moments.count, 1)
        XCTAssertEqual(receivedStory.moments[0].title, "The gap")

        let handle = try await receiver.makeHandle(forCaseID: adoption.record.id)
        defer { handle.close() }
        XCTAssertEqual(handle.depth, 6)
    }

    func testSecondHandoffMergesCaseDetails() async throws {
        let sender = try await makeStore("sender2")
        let record = try await importFixture(into: sender, label: "Original")
        let receiver = try await makeStore("receiver2")

        let firstArchive = root.appendingPathComponent("first.zip")
        try await sender.exportPackage(id: record.id, to: firstArchive)
        let firstDir = root.appendingPathComponent("first", isDirectory: true)
        _ = try ZipArchive(fileAt: firstArchive).extractAll(to: firstDir)
        _ = try await receiver.adoptPackage(at: firstDir)

        try await sender.rename(id: record.id, to: "Updated plan")
        var story = StoryState()
        story.notes = "Patient accepted"
        try StoryStateIO.save(story, to: record.directory)
        let secondArchive = root.appendingPathComponent("second.zip")
        try await sender.exportPackage(id: record.id, to: secondArchive)
        let secondDir = root.appendingPathComponent("second", isDirectory: true)
        _ = try ZipArchive(fileAt: secondArchive).extractAll(to: secondDir)

        let adoption = try await receiver.adoptPackage(at: secondDir)
        XCTAssertTrue(adoption.merged)
        XCTAssertEqual(adoption.record.label, "Updated plan")
        XCTAssertEqual(StoryStateIO.load(from: adoption.record.directory).notes, "Patient accepted")
        let all = await receiver.reload()
        XCTAssertEqual(all.count, 1)
    }

    func testOldManifestWithoutPatientTagStillLoads() throws {
        let directory = root.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var manifest = BundleManifest(
            caseID: "L1",
            label: "Legacy",
            importedAt: Date(timeIntervalSince1970: 0),
            dimensions: [2, 2, 2],
            spacingMM: [1, 1, 1],
            orientation: [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0]],
            originMM: [0, 0, 0],
            volumeSHA256: "x",
            isGapped: false,
            seriesUIDHash: "y"
        )
        manifest.patientTag = nil
        var data = try BundleManifest.encoder().encode(manifest)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "patientTag")
        data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try BundleManifest.decoder().decode(BundleManifest.self, from: data)
        XCTAssertNil(decoded.patientTag)
        XCTAssertEqual(decoded.label, "Legacy")
    }
}
