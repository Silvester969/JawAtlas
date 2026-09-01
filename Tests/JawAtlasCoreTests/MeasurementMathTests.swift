import XCTest
@testable import JawAtlasCore

final class MeasurementMathTests: XCTestCase {
    func testDistanceIsEuclideanMM() {
        XCTAssertEqual(MeasurementMath.distanceMM(Vec3(0, 0, 0), Vec3(3, 4, 0)), 5, accuracy: 1e-9)
        XCTAssertEqual(MeasurementMath.distanceMM(Vec3(1, 2, 3), Vec3(1, 2, 3)), 0, accuracy: 1e-9)
        XCTAssertEqual(MeasurementMath.distanceMM(Vec3(0, 0, -2), Vec3(0, 0, 2)), 4, accuracy: 1e-9)
    }

    func testAngleAtVertex() {
        XCTAssertEqual(
            MeasurementMath.angleDegrees(vertex: Vec3(0, 0, 0), first: Vec3(1, 0, 0), second: Vec3(0, 1, 0)),
            90,
            accuracy: 1e-6
        )
        XCTAssertEqual(
            MeasurementMath.angleDegrees(vertex: Vec3(0, 0, 0), first: Vec3(1, 0, 0), second: Vec3(-1, 0, 0)),
            180,
            accuracy: 1e-6
        )
        XCTAssertEqual(
            MeasurementMath.angleDegrees(vertex: Vec3(0, 0, 0), first: Vec3(2, 0, 0), second: Vec3(2, 2, 0)),
            45,
            accuracy: 1e-6
        )
    }

    func testDisplayTexts() {
        XCTAssertEqual(MeasurementMath.distanceText(12.34), "12.3 mm")
        XCTAssertEqual(MeasurementMath.angleText(89.96), "90.0°")
    }
}
