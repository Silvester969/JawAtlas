import XCTest
@testable import JawAtlasCore

final class ArchCurveTests: XCTestCase {
    private func semicirclePoints(radius: Double, count: Int) -> [Vec3] {
        (0..<count).map { index in
            let angle = Double.pi * Double(index) / Double(count - 1)
            return Vec3(radius * cos(angle), radius * sin(angle), 4)
        }
    }

    func testCurvePassesThroughControlPoints() {
        let controls = [Vec3(0, 0, 0), Vec3(10, 8, 0), Vec3(20, 10, 0), Vec3(30, 4, 0)]
        let curve = ArchCurve(controlPointsLocalMM: controls)
        let dense = curve.densePolyline()
        for control in controls {
            let nearest = dense.map { ($0 - control).length }.min() ?? .infinity
            XCTAssertLessThan(nearest, 0.5)
        }
    }

    func testUniformResamplingHasEvenSpacing() {
        let curve = ArchCurve(controlPointsLocalMM: semicirclePoints(radius: 30, count: 9))
        let resampled = curve.resampledUniformly(count: 60)
        XCTAssertEqual(resampled.count, 60)
        var spacings: [Double] = []
        for index in 1..<resampled.count {
            spacings.append((resampled[index] - resampled[index - 1]).length)
        }
        let mean = spacings.reduce(0, +) / Double(spacings.count)
        for spacing in spacings {
            XCTAssertEqual(spacing, mean, accuracy: mean * 0.25)
        }
    }

    func testSemicircleLengthApproximatesPiR() {
        let radius = 40.0
        let curve = ArchCurve(controlPointsLocalMM: semicirclePoints(radius: radius, count: 17))
        let length = curve.totalLengthMM()
        XCTAssertEqual(length, .pi * radius, accuracy: .pi * radius * 0.03)
    }

    func testResampledPointsKeepDrawingPlaneZ() {
        let curve = ArchCurve(controlPointsLocalMM: semicirclePoints(radius: 25, count: 7))
        for point in curve.resampledUniformly(count: 30) {
            XCTAssertEqual(point.z, 4, accuracy: 0.2)
        }
    }

    func testOrientationNormalizesRightToLeft() {
        let geometry = VolumeGeometry(
            dimensions: (100, 100, 100),
            spacingMM: Vec3(0.3, 0.3, 0.3),
            originMM: Vec3(0, 0, 0),
            rowDirection: Vec3(1, 0, 0),
            columnDirection: Vec3(0, 1, 0),
            sliceNormal: Vec3(0, 0, 1)
        )
        let rightToLeft = [Vec3(-10, 0, 0), Vec3(0, 8, 0), Vec3(10, 0, 0)]
        let leftToRight: [Vec3] = rightToLeft.reversed()
        let keptOrder = ArchCurve.orientedRightToLeft(rightToLeft, geometry: geometry)
        let flipped = ArchCurve.orientedRightToLeft(leftToRight, geometry: geometry)
        XCTAssertEqual(keptOrder, rightToLeft)
        XCTAssertEqual(flipped, rightToLeft)
    }

    func testTooFewPointsAreUnusable() {
        XCTAssertFalse(ArchCurve(controlPointsLocalMM: [Vec3(0, 0, 0), Vec3(1, 1, 0)]).isUsable)
        XCTAssertTrue(
            ArchCurve(controlPointsLocalMM: semicirclePoints(radius: 20, count: 4)).isUsable
        )
    }

    func testStoryStatePersistsArchCurve() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var story = StoryState()
        story.archControlPointsLocalMM = semicirclePoints(radius: 30, count: 5)
        try StoryStateIO.save(story, to: directory)
        let loaded = StoryStateIO.load(from: directory)
        XCTAssertEqual(loaded.archControlPointsLocalMM, story.archControlPointsLocalMM)
    }

    func testStoryWithoutArchCurveStillLoads() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = "{\"schemaVersion\":1,\"moments\":[],\"notes\":\"hello\"}"
        try legacy.data(using: .utf8)?.write(to: BundleLayout.storyURL(in: directory))
        let loaded = StoryStateIO.load(from: directory)
        XCTAssertEqual(loaded.notes, "hello")
        XCTAssertNil(loaded.archControlPointsLocalMM)
    }
}
