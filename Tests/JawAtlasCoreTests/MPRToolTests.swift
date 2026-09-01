import XCTest
import simd
@testable import JawAtlas

@MainActor
final class MPRToolTests: XCTestCase {
    func testNavigateIsDefaultAndSilent() {
        let model = ViewerModel()
        XCTAssertEqual(model.mprTool, .navigate)
        XCTAssertNil(model.mprPrompt)
        model.addMeasurePoint(SIMD3<Float>(0, 0, 0))
        XCTAssertTrue(model.measurements.isEmpty)
    }

    func testLengthFlowGuidesAndCompletes() {
        let model = ViewerModel()
        model.selectMPRTool(.length)
        XCTAssertEqual(model.mprPrompt, "Tap where the measurement should start")
        model.addMeasurePoint(SIMD3<Float>(0, 0, 0))
        XCTAssertEqual(model.mprPrompt, "Tap where it should end")
        model.addMeasurePoint(SIMD3<Float>(10, 0, 0))
        XCTAssertEqual(model.measurements.count, 1)
        XCTAssertEqual(model.measurements[0].label, "10.0 mm")
        XCTAssertTrue(model.measureDraft.isEmpty)
        XCTAssertEqual(model.mprPrompt, "Tap where the measurement should start")
    }

    func testAngleFlowGuidesThroughThreePoints() {
        let model = ViewerModel()
        model.selectMPRTool(.angle)
        XCTAssertEqual(model.mprPrompt, "Tap the first point of the angle")
        model.addMeasurePoint(SIMD3<Float>(10, 0, 0))
        XCTAssertEqual(model.mprPrompt, "Tap the corner, where the two lines meet")
        model.addMeasurePoint(SIMD3<Float>(0, 0, 0))
        XCTAssertEqual(model.mprPrompt, "Tap the last point of the angle")
        model.addMeasurePoint(SIMD3<Float>(0, 10, 0))
        XCTAssertEqual(model.measurements.count, 1)
        XCTAssertEqual(model.measurements[0].label, "90.0°")
    }

    func testReselectingToolReturnsToNavigate() {
        let model = ViewerModel()
        model.selectMPRTool(.length)
        model.addMeasurePoint(SIMD3<Float>(0, 0, 0))
        model.selectMPRTool(.length)
        XCTAssertEqual(model.mprTool, .navigate)
        XCTAssertTrue(model.measureDraft.isEmpty)
        model.selectMPRTool(.window)
        model.selectMPRTool(.angle)
        XCTAssertEqual(model.mprTool, .angle)
    }
}
