import XCTest
import Compression
@testable import JawAtlasCore

struct ZipFixtureEntry {
    var name: String
    var payload = Data()
    var method: UInt16 = 0
    var overrideUncompressedSize: UInt32?
    var externalAttributes: UInt32 = 0
    var versionMadeBy: UInt16 = 0x0314
    var zip64 = false
}

enum ZipFixture {
    static func deflated(_ data: Data) -> Data {
        let capacity = data.count + 512
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source -> Int in
                guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
                      let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return compression_encode_buffer(
                    destinationBase,
                    capacity,
                    sourceBase,
                    source.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        return output.prefix(written)
    }

    static func u16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    static func u32(_ value: UInt32) -> Data {
        var data = Data()
        for shift in stride(from: 0, to: 32, by: 8) {
            data.append(UInt8((value >> UInt32(shift)) & 0xFF))
        }
        return data
    }

    static func u64(_ value: UInt64) -> Data {
        var data = Data()
        for shift in stride(from: 0, to: 64, by: 8) {
            data.append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
        return data
    }

    static func archive(_ entries: [ZipFixtureEntry]) -> Data {
        var body = Data()
        var central = Data()
        for entry in entries {
            let offset = UInt32(body.count)
            let storedBytes = entry.method == 8 ? deflated(entry.payload) : entry.payload
            let uncompressedSize = entry.overrideUncompressedSize ?? UInt32(entry.payload.count)
            let nameData = Data(entry.name.utf8)

            body.append(u32(0x0403_4B50))
            body.append(u16(20))
            body.append(u16(0))
            body.append(u16(entry.method))
            body.append(u16(0))
            body.append(u16(0))
            body.append(u32(0))
            body.append(u32(UInt32(storedBytes.count)))
            body.append(u32(uncompressedSize))
            body.append(u16(UInt16(nameData.count)))
            body.append(u16(0))
            body.append(nameData)
            body.append(storedBytes)

            var extra = Data()
            var centralUncompressed = uncompressedSize
            var centralCompressed = UInt32(storedBytes.count)
            var centralOffset = offset
            if entry.zip64 {
                extra.append(u16(0x0001))
                extra.append(u16(24))
                extra.append(u64(UInt64(uncompressedSize)))
                extra.append(u64(UInt64(storedBytes.count)))
                extra.append(u64(UInt64(offset)))
                centralUncompressed = 0xFFFF_FFFF
                centralCompressed = 0xFFFF_FFFF
                centralOffset = 0xFFFF_FFFF
            }

            central.append(u32(0x0201_4B50))
            central.append(u16(entry.versionMadeBy))
            central.append(u16(20))
            central.append(u16(0))
            central.append(u16(entry.method))
            central.append(u16(0))
            central.append(u16(0))
            central.append(u32(0))
            central.append(u32(centralCompressed))
            central.append(u32(centralUncompressed))
            central.append(u16(UInt16(nameData.count)))
            central.append(u16(UInt16(extra.count)))
            central.append(u16(0))
            central.append(u16(0))
            central.append(u16(0))
            central.append(u32(entry.externalAttributes))
            central.append(u32(centralOffset))
            central.append(nameData)
            central.append(extra)
        }

        let centralStart = UInt32(body.count)
        var out = body
        out.append(central)
        if entries.contains(where: { $0.zip64 }) {
            let recordOffset = UInt64(out.count)
            out.append(u32(0x0606_4B50))
            out.append(u64(44))
            out.append(u16(45))
            out.append(u16(45))
            out.append(u32(0))
            out.append(u32(0))
            out.append(u64(UInt64(entries.count)))
            out.append(u64(UInt64(entries.count)))
            out.append(u64(UInt64(central.count)))
            out.append(u64(UInt64(centralStart)))
            out.append(u32(0x0706_4B50))
            out.append(u32(0))
            out.append(u64(recordOffset))
            out.append(u32(1))
            out.append(u32(0x0605_4B50))
            out.append(u16(0))
            out.append(u16(0))
            out.append(u16(0xFFFF))
            out.append(u16(0xFFFF))
            out.append(u32(0xFFFF_FFFF))
            out.append(u32(0xFFFF_FFFF))
            out.append(u16(0))
        } else {
            out.append(u32(0x0605_4B50))
            out.append(u16(0))
            out.append(u16(0))
            out.append(u16(UInt16(entries.count)))
            out.append(u16(UInt16(entries.count)))
            out.append(u32(UInt32(central.count)))
            out.append(u32(centralStart))
            out.append(u16(0))
        }
        return out
    }
}

final class ZipArchiveTests: XCTestCase {
    private var workDirectory = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        workDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("zip-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    private func makeDestination() -> URL {
        workDirectory.appendingPathComponent("out-\(UUID().uuidString)", isDirectory: true)
    }

    func testStoredEntryExtracts() throws {
        let payload = Data("hello stored world".utf8)
        let data = ZipFixture.archive([ZipFixtureEntry(name: "notes/readme.txt", payload: payload)])
        let archive = try ZipArchive(data: data)
        XCTAssertEqual(archive.entries.count, 1)
        XCTAssertEqual(archive.entries[0].name, "notes/readme.txt")
        let destination = makeDestination()
        let written = try archive.extractAll(to: destination)
        XCTAssertEqual(written.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(written.first)), payload)
    }

    func testDeflateEntryExtractsWithOneShotDecoder() throws {
        var payload = Data()
        for index in 0..<9000 {
            payload.append(UInt8(index % 251))
        }
        let data = ZipFixture.archive([ZipFixtureEntry(name: "slice.bin", payload: payload, method: 8)])
        let archive = try ZipArchive(data: data)
        let entry = try XCTUnwrap(archive.entries.first)
        XCTAssertEqual(entry.method, 8)
        XCTAssertLessThan(entry.compressedSize, entry.uncompressedSize)
        XCTAssertEqual(try archive.extractData(of: entry), payload)
    }

    func testZip64ArchiveExtracts() throws {
        let payload = Data("zip64 payload bytes".utf8)
        let data = ZipFixture.archive([ZipFixtureEntry(name: "big.bin", payload: payload, zip64: true)])
        let archive = try ZipArchive(data: data)
        let entry = try XCTUnwrap(archive.entries.first)
        XCTAssertEqual(entry.uncompressedSize, UInt64(payload.count))
        XCTAssertEqual(try archive.extractData(of: entry), payload)
    }

    func testDirectoryAndSymlinkEntriesAreSkipped() throws {
        let payload = Data("real file".utf8)
        let data = ZipFixture.archive([
            ZipFixtureEntry(name: "folder/"),
            ZipFixtureEntry(name: "link", payload: Data("target".utf8), externalAttributes: 0xA1FF_0000),
            ZipFixtureEntry(name: "folder/file.bin", payload: payload)
        ])
        let archive = try ZipArchive(data: data)
        let written = try archive.extractAll(to: makeDestination())
        XCTAssertEqual(written.count, 1)
        XCTAssertEqual(written.first?.lastPathComponent, "file.bin")
    }

    func testAbsolutePathEntryThrows() throws {
        let data = ZipFixture.archive([ZipFixtureEntry(name: "/etc/passwd", payload: Data([1]))])
        let archive = try ZipArchive(data: data)
        XCTAssertThrowsError(try archive.extractAll(to: makeDestination())) { error in
            guard case ZipArchiveError.unsafeEntryPath = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testTraversalPathEntryThrows() throws {
        let data = ZipFixture.archive([ZipFixtureEntry(name: "../escape.bin", payload: Data([1]))])
        let archive = try ZipArchive(data: data)
        XCTAssertThrowsError(try archive.extractAll(to: makeDestination())) { error in
            guard case ZipArchiveError.unsafeEntryPath = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testTruncatedArchiveThrowsTypedError() throws {
        let data = ZipFixture.archive([ZipFixtureEntry(name: "a.bin", payload: Data([1, 2, 3]))])
        XCTAssertThrowsError(try ZipArchive(data: data.dropLast(4))) { error in
            XCTAssertTrue(error is ZipArchiveError)
        }
        XCTAssertThrowsError(try ZipArchive(data: Data(count: 10))) { error in
            XCTAssertEqual(error as? ZipArchiveError, .truncated)
        }
        XCTAssertThrowsError(try ZipArchive(data: Data(count: 4096))) { error in
            XCTAssertEqual(error as? ZipArchiveError, .notZipArchive)
        }
    }

    func testOversizeDeclarationThrows() throws {
        let data = ZipFixture.archive([
            ZipFixtureEntry(name: "a.bin", payload: Data([1]), overrideUncompressedSize: 0xF000_0000),
            ZipFixtureEntry(name: "b.bin", payload: Data([1]), overrideUncompressedSize: 0xF000_0000)
        ])
        XCTAssertThrowsError(try ZipArchive(data: data)) { error in
            XCTAssertEqual(error as? ZipArchiveError, .declaredSizeTooLarge)
        }
    }

    func testStoredSizeMismatchThrows() throws {
        let data = ZipFixture.archive([
            ZipFixtureEntry(name: "lie.bin", payload: Data([1, 2, 3]), overrideUncompressedSize: 9)
        ])
        let archive = try ZipArchive(data: data)
        XCTAssertThrowsError(try archive.extractAll(to: makeDestination())) { error in
            XCTAssertTrue(error is ZipArchiveError)
        }
    }

    func testTooManyEntriesThrows() throws {
        var entries: [ZipFixtureEntry] = []
        entries.reserveCapacity(20001)
        for index in 0..<20001 {
            entries.append(ZipFixtureEntry(name: "e\(index)"))
        }
        let data = ZipFixture.archive(entries)
        XCTAssertThrowsError(try ZipArchive(data: data)) { error in
            guard case ZipArchiveError.tooManyEntries = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testMutatedArchivesNeverCrash() throws {
        let base = ZipFixture.archive([
            ZipFixtureEntry(name: "a/one.bin", payload: Data("first payload".utf8)),
            ZipFixtureEntry(name: "two.bin", payload: Data(repeating: 7, count: 300), method: 8)
        ])
        for length in stride(from: 0, to: base.count, by: 3) {
            let truncated = base.prefix(length)
            if let archive = try? ZipArchive(data: Data(truncated)) {
                _ = try? archive.extractAll(to: makeDestination())
            }
        }
        for position in stride(from: 0, to: base.count, by: 5) {
            var mutated = base
            let index = mutated.startIndex + position
            mutated[index] = mutated[index] ^ 0xFF
            if let archive = try? ZipArchive(data: mutated) {
                _ = try? archive.extractAll(to: makeDestination())
            }
        }
    }

    func testStagerStagesDICOMFolderAndPipelineScans() throws {
        let source = workDirectory.appendingPathComponent("series", isDirectory: true)
        _ = try FixtureSeries.write(into: source, slices: 6)
        let staging = workDirectory.appendingPathComponent("staging", isDirectory: true)
        let staged = try IncomingScanStager.stage(urls: [source], into: staging)
        XCTAssertEqual(staged.count, 1)
        let result = try ImportPipeline.scan(urls: staged)
        XCTAssertEqual(result.candidates.count, 1)
        XCTAssertEqual(result.candidates.first?.slices.count, 6)
    }

    func testStagerUnzipsArchiveAndPipelineScans() throws {
        let source = workDirectory.appendingPathComponent("zipsource", isDirectory: true)
        let sliceURLs = try FixtureSeries.write(into: source, slices: 6)
        var entries: [ZipFixtureEntry] = []
        for (index, url) in sliceURLs.enumerated() {
            let method: UInt16 = index % 2 == 0 ? 0 : 8
            entries.append(
                ZipFixtureEntry(
                    name: "scan/\(url.lastPathComponent)",
                    payload: try Data(contentsOf: url),
                    method: method
                )
            )
        }
        let zipURL = workDirectory.appendingPathComponent("scan.zip")
        try ZipFixture.archive(entries).write(to: zipURL)
        let staging = workDirectory.appendingPathComponent("staging", isDirectory: true)
        let staged = try IncomingScanStager.stage(urls: [zipURL], into: staging)
        let result = try ImportPipeline.scan(urls: staged)
        XCTAssertEqual(result.candidates.count, 1)
        XCTAssertEqual(result.candidates.first?.slices.count, 6)
    }

    func testStagerCopiesLooseDICOMFiles() throws {
        let source = workDirectory.appendingPathComponent("loose", isDirectory: true)
        let sliceURLs = try FixtureSeries.write(into: source, slices: 6)
        let staging = workDirectory.appendingPathComponent("staging", isDirectory: true)
        let staged = try IncomingScanStager.stage(urls: sliceURLs, into: staging)
        XCTAssertEqual(staged.count, 1)
        let result = try ImportPipeline.scan(urls: staged)
        XCTAssertEqual(result.candidates.first?.slices.count, 6)
    }

    func testStagerEmptyInputThrows() {
        let staging = workDirectory.appendingPathComponent("staging", isDirectory: true)
        XCTAssertThrowsError(try IncomingScanStager.stage(urls: [], into: staging)) { error in
            XCTAssertEqual(error as? IncomingScanError, .nothingToStage)
        }
    }

    func testStagerMissingSourceThrows() {
        let staging = workDirectory.appendingPathComponent("staging", isDirectory: true)
        let ghost = workDirectory.appendingPathComponent("missing.dcm")
        XCTAssertThrowsError(try IncomingScanStager.stage(urls: [ghost], into: staging)) { error in
            guard case IncomingScanError.sourceMissing = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testStagerRejectsHostileArchive() throws {
        let zipURL = workDirectory.appendingPathComponent("hostile.zip")
        let data = ZipFixture.archive([ZipFixtureEntry(name: "../../evil.dcm", payload: Data([1]))])
        try data.write(to: zipURL)
        let staging = workDirectory.appendingPathComponent("staging", isDirectory: true)
        XCTAssertThrowsError(try IncomingScanStager.stage(urls: [zipURL], into: staging)) { error in
            guard case ZipArchiveError.unsafeEntryPath = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []
        XCTAssertTrue(leftovers.isEmpty)
    }
}
