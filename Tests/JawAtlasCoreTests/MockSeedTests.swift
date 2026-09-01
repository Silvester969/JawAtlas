import XCTest
@testable import JawAtlasCore

final class MockSeedTests: XCTestCase {
    func testConvertMockCases() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MOCKSEED"] == "1")
        guard let sourceRoot = ProcessInfo.processInfo.environment["MOCK_SOURCE"],
              let outputRoot = ProcessInfo.processInfo.environment["MOCK_OUTPUT"] else {
            throw XCTSkip("MOCK_SOURCE and MOCK_OUTPUT required")
        }
        let output = URL(fileURLWithPath: outputRoot, isDirectory: true)
        try? FileManager.default.removeItem(at: output)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for folder in ["out_M53", "out_M44"] {
            let source = URL(fileURLWithPath: sourceRoot, isDirectory: true)
                .appendingPathComponent(folder, isDirectory: true)
            let result = try ImportPipeline.scan(urls: [source])
            let candidate = try XCTUnwrap(result.preferredCandidate)
            let record = try BundleConverter.convert(
                candidate: candidate,
                label: folder,
                casesDirectory: output
            )
            XCTAssertEqual(record.dimensions, [480, 480, 320])
            print("MOCKSEED converted \(folder) -> \(record.id)")
        }
    }
}
