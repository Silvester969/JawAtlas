import XCTest
import simd
@testable import JawAtlas
@testable import JawAtlasCore

final class StoryTests: XCTestCase {
    private func sampleState() -> StoryState {
        let momentA = StoryMoment(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID(),
            title: "The infection",
            caption: "This dark area is the infection",
            createdAt: Date(timeIntervalSince1970: 1_720_000_000),
            stage: .slice,
            windowPreset: "bone",
            planeAzimuth: 0.42,
            planeOffsetMM: -6.5,
            planePanX: 2.0,
            planePanY: -3.5,
            planeSpanMM: 88,
            cameraAzimuth: 0.1,
            cameraElevation: 0.2,
            cameraDistance: 260,
            strokesLocalMM: [
                [Vec3(1.5, -2.25, 10), Vec3(2.5, -2.0, 11), Vec3(3.75, -1.5, 12)],
                [Vec3(-4, 0, 5), Vec3(-3, 1, 5.5)]
            ]
        )
        let momentB = StoryMoment(
            title: "Whole jaw",
            createdAt: Date(timeIntervalSince1970: 1_720_000_060),
            stage: .volume,
            windowPreset: "softTissue",
            planeAzimuth: 0,
            planeOffsetMM: 0,
            planePanX: 0,
            planePanY: 0,
            planeSpanMM: 120,
            cameraAzimuth: 1.2,
            cameraElevation: -0.3,
            cameraDistance: 400
        )
        return StoryState(moments: [momentA, momentB])
    }

    func testStoryStateJSONRoundTripKeepsStrokesAndCaptions() throws {
        let original = sampleState()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StoryState.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.moments[0].strokesLocalMM.count, 2)
        XCTAssertEqual(decoded.moments[0].strokesLocalMM[0][2], Vec3(3.75, -1.5, 12))
        XCTAssertEqual(decoded.moments[0].caption, "This dark area is the infection")
    }

    func testStoryStateIOSaveAndLoad() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = sampleState()
        try StoryStateIO.save(original, to: directory)
        let loaded = StoryStateIO.load(from: directory)
        XCTAssertEqual(loaded, original)
    }

    func testMissingStoryFileReturnsEmptyState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let loaded = StoryStateIO.load(from: directory)
        XCTAssertEqual(loaded, StoryState())
    }

    func testCorruptedStoryFileReturnsEmptyState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = BundleLayout.storyURL(in: directory)
        let garbage = Data("{not json at all]]".utf8)
        try garbage.write(to: url)
        let loaded = StoryStateIO.load(from: directory)
        XCTAssertEqual(loaded, StoryState())
    }

    func testNewerSchemaVersionReturnsEmptyState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var future = sampleState()
        future.schemaVersion = 99
        try StoryStateIO.save(future, to: directory)
        let loaded = StoryStateIO.load(from: directory)
        XCTAssertEqual(loaded, StoryState())
    }

    func testMapperRoundTripWithinTolerance() {
        let matrix = SlicePlaneMath.planeToLocal(
            azimuth: 0.7,
            offsetMM: 12,
            pan: SIMD2<Float>(4, -6),
            spanMM: 90,
            aspect: 1.5
        )
        let mapper = SliceMarkMapper(planeToLocal: matrix, size: CGSize(width: 390, height: 520))
        let screenPoints = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 195, y: 260),
            CGPoint(x: 390, y: 520),
            CGPoint(x: 37.5, y: 411.25),
            CGPoint(x: 310.2, y: 88.8)
        ]
        for point in screenPoints {
            let local = mapper.localMM(fromScreenPoint: point)
            let back = mapper.screenPoint(fromLocalMM: local)
            XCTAssertEqual(Double(back.x), Double(point.x), accuracy: 1e-3)
            XCTAssertEqual(Double(back.y), Double(point.y), accuracy: 1e-3)
        }
    }

    func testMapperKnownGeometry() {
        let matrix = SlicePlaneMath.planeToLocal(
            azimuth: 0,
            offsetMM: 0,
            pan: SIMD2<Float>(0, 0),
            spanMM: 100,
            aspect: 1
        )
        let mapper = SliceMarkMapper(planeToLocal: matrix, size: CGSize(width: 200, height: 200))
        let center = mapper.localMM(fromScreenPoint: CGPoint(x: 100, y: 100))
        XCTAssertEqual(center.x, 0, accuracy: 1e-4)
        XCTAssertEqual(center.y, 0, accuracy: 1e-4)
        XCTAssertEqual(center.z, 0, accuracy: 1e-4)
        let topRight = mapper.localMM(fromScreenPoint: CGPoint(x: 200, y: 0))
        XCTAssertEqual(topRight.x, 50, accuracy: 1e-3)
        XCTAssertEqual(topRight.y, 0, accuracy: 1e-3)
        XCTAssertEqual(topRight.z, 50, accuracy: 1e-3)
        let projected = mapper.screenPoint(fromLocalMM: Vec3(25, 0, -25))
        XCTAssertEqual(Double(projected.x), 150, accuracy: 1e-3)
        XCTAssertEqual(Double(projected.y), 150, accuracy: 1e-3)
    }
}

extension StoryTests {
    func testMomentWithoutElevationDecodesAsFlatCut() throws {
        let json = """
        {"schemaVersion":1,"moments":[{"id":"7B2504E0-4F89-41D3-9A0C-0305E82C3301",
        "title":"Old","caption":"","createdAt":"2026-08-21T10:00:00Z","stage":"slice",
        "windowPreset":"bone","planeAzimuth":0.5,"planeOffsetMM":3,"planePanX":0,
        "planePanY":0,"planeSpanMM":90,"cameraAzimuth":0,"cameraElevation":0,
        "cameraDistance":200,"strokesLocalMM":[]}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(StoryState.self, from: Data(json.utf8))
        XCTAssertEqual(state.moments.count, 1)
        XCTAssertNil(state.moments[0].planeElevation)
        XCTAssertEqual(state.moments[0].planeElevation ?? 0, 0)
    }
}
