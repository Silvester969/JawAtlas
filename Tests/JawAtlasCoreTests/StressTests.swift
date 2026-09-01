import XCTest
@testable import JawAtlas
@testable import JawAtlasCore

final class StressTests: XCTestCase {
    private var root = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["STRESS"] == "1")
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func physicalFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / 1_048_576
    }

    private func makeLargeMultiFrameFile() throws -> URL {
        let width = 512
        let height = 512
        let frames = 300
        var fixture = FixtureSlice()
        fixture.rows = height
        fixture.columns = width
        fixture.frames = frames
        fixture.spacingBetweenSlices = "0.3"
        var pixels = [UInt16](repeating: 0, count: width * height * frames)
        for frame in 0..<frames {
            let base = frame * width * height
            for index in 0..<(width * height) {
                let x = index % width
                let y = index / width
                let inCore = (x - 256) * (x - 256) + (y - 256) * (y - 256) < 150 * 150
                pixels[base + index] = inCore ? UInt16(1900 + (index % 137)) : UInt16(30 + (frame % 11))
            }
        }
        fixture.pixels = pixels
        let url = root.appendingPathComponent("large.dcm")
        try fixture.encoded().write(to: url)
        return url
    }

    func testLargeMultiFrameImportStress() async throws {
        let start = Date()
        let file = try makeLargeMultiFrameFile()
        let generated = Date()
        let fileMB = Double((try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0) / 1_048_576

        let baselineMB = physicalFootprintMB()
        let slices = try DICOMParser.parseExpanded(fileAt: file)
        XCTAssertEqual(slices.count, 300)
        let result = SeriesBuilder.build(from: slices)
        let candidate = try XCTUnwrap(result.candidates.first)
        XCTAssertEqual(candidate.slices.count, 300)

        let cases = root.appendingPathComponent("cases", isDirectory: true)
        try FileManager.default.createDirectory(at: cases, withIntermediateDirectories: true)
        let convertStart = Date()
        let record = try BundleConverter.convert(candidate: candidate, label: "Stress", casesDirectory: cases)
        let convertSeconds = Date().timeIntervalSince(convertStart)
        let peakMB = physicalFootprintMB()

        XCTAssertEqual(record.dimensions, [512, 512, 300])
        let volumeMB = Double(record.volumeByteCount) / 1_048_576
        let manifest = try IntegrityVerifier.loadManifest(in: record.directory)
        try IntegrityVerifier.deepVerify(manifest: manifest, directory: record.directory)

        let store = CaseStore(root: root.appendingPathComponent("store", isDirectory: true))
        try await store.prepare()
        _ = await store.reload()
        let handleStore = CaseStore(root: cases.deletingLastPathComponent())
        _ = await handleStore.reload()

        print("STRESS large-import fileMB=\(String(format: "%.0f", fileMB)) genSeconds=\(String(format: "%.1f", generated.timeIntervalSince(start))) convertSeconds=\(String(format: "%.1f", convertSeconds)) volumeMB=\(String(format: "%.0f", volumeMB)) footprintDeltaMB=\(String(format: "%.0f", peakMB - baselineMB))")
        XCTAssertLessThan(convertSeconds, 120)
        XCTAssertLessThan(peakMB - baselineMB, 900)
    }

    func testLargeCaseHandoffStress() async throws {
        let file = try makeLargeMultiFrameFile()
        let slices = try DICOMParser.parseExpanded(fileAt: file)
        let candidate = try XCTUnwrap(SeriesBuilder.build(from: slices).candidates.first)
        let senderRoot = root.appendingPathComponent("sender", isDirectory: true)
        let sender = CaseStore(root: senderRoot)
        try await sender.prepare()
        let record = try await sender.importSeries(candidate: candidate, label: "Big case")

        let archive = root.appendingPathComponent("big.zip")
        let exportStart = Date()
        try await sender.exportPackage(id: record.id, to: archive)
        let exportSeconds = Date().timeIntervalSince(exportStart)
        let archiveMB = Double((try FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? NSNumber)?.intValue ?? 0) / 1_048_576

        let received = root.appendingPathComponent("received", isDirectory: true)
        let extractStart = Date()
        _ = try ZipArchive(fileAt: archive).extractAll(to: received)
        let extractSeconds = Date().timeIntervalSince(extractStart)

        let receiver = CaseStore(root: root.appendingPathComponent("receiver", isDirectory: true))
        try await receiver.prepare()
        let adoption = try await receiver.adoptPackage(at: received)
        XCTAssertEqual(adoption.record.dimensions, [512, 512, 300])

        print("STRESS handoff archiveMB=\(String(format: "%.0f", archiveMB)) exportSeconds=\(String(format: "%.1f", exportSeconds)) extractSeconds=\(String(format: "%.1f", extractSeconds))")
        XCTAssertLessThan(exportSeconds, 60)
        XCTAssertLessThan(extractSeconds, 60)
    }

    func testManyCaseLibraryStress() async throws {
        let store = CaseStore(root: root.appendingPathComponent("many", isDirectory: true))
        try await store.prepare()
        let source = root.appendingPathComponent("dicom", isDirectory: true)
        let urls = try FixtureSeries.write(into: source, slices: 6)
        let parsed = try urls.map { try DICOMParser.parse(fileAt: $0) }
        let candidate = try XCTUnwrap(SeriesBuilder.build(from: parsed).candidates.first)
        let seed = try await store.importSeries(candidate: candidate, label: "Seed")

        let casesDir = await store.casesDirectory
        for index in 0..<59 {
            let clone = casesDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.copyItem(at: seed.directory, to: clone)
            var manifest = try IntegrityVerifier.loadManifest(in: clone)
            manifest.caseID = clone.lastPathComponent
            manifest.label = "Case \(index)"
            manifest.seriesUIDHash = "hash-\(index)"
            manifest.patientTag = "P\(index % 12)"
            let data = try BundleManifest.encoder().encode(manifest)
            try data.write(to: BundleLayout.manifestURL(in: clone), options: [.atomic])
        }

        let sweepStart = Date()
        await store.sweep()
        let sweepSeconds = Date().timeIntervalSince(sweepStart)
        let reloadStart = Date()
        let records = await store.reload()
        let reloadSeconds = Date().timeIntervalSince(reloadStart)

        XCTAssertEqual(records.count, 60)
        let groups = Set(records.compactMap { $0.patientTag })
        XCTAssertEqual(groups.count, 12)

        print("STRESS library cases=\(records.count) sweepSeconds=\(String(format: "%.2f", sweepSeconds)) reloadSeconds=\(String(format: "%.2f", reloadSeconds))")
        XCTAssertLessThan(reloadSeconds, 3)
        XCTAssertLessThan(sweepSeconds, 3)
    }

    func testStoryAndSummaryStress() throws {
        var story = StoryState()
        for index in 0..<40 {
            var moment = StoryMoment(
                title: "Moment \(index)",
                caption: "Caption \(index)",
                stage: .slice,
                windowPreset: "bone",
                planeAzimuth: Double(index) * 0.1,
                planeElevation: 0.2,
                planeOffsetMM: Double(index),
                planePanX: 0,
                planePanY: 0,
                planeSpanMM: 90,
                cameraAzimuth: 0,
                cameraElevation: 0,
                cameraDistance: 200
            )
            moment.strokesLocalMM = (0..<4).map { stroke in
                (0..<200).map { point in
                    Vec3(Double(point) * 0.3, Double(stroke) * 2, Double(index))
                }
            }
            story.moments.append(moment)
        }
        let directory = root
        let saveStart = Date()
        try StoryStateIO.save(story, to: directory)
        let saved = Date().timeIntervalSince(saveStart)
        let loadStart = Date()
        let loaded = StoryStateIO.load(from: directory)
        let loadSeconds = Date().timeIntervalSince(loadStart)
        XCTAssertEqual(loaded.moments.count, 40)
        let sizeKB = Double((try FileManager.default.attributesOfItem(atPath: BundleLayout.storyURL(in: directory).path)[.size] as? NSNumber)?.intValue ?? 0) / 1024
        print("STRESS story moments=40 strokes=160 points=32000 sizeKB=\(String(format: "%.0f", sizeKB)) saveSeconds=\(String(format: "%.2f", saved)) loadSeconds=\(String(format: "%.2f", loadSeconds))")
        XCTAssertLessThan(saved, 2)
        XCTAssertLessThan(loadSeconds, 2)
    }
}
