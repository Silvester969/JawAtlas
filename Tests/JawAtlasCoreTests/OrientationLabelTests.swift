import XCTest
@testable import JawAtlasCore

final class OrientationLabelTests: XCTestCase {
    private func identityGeometry() -> VolumeGeometry {
        VolumeGeometry(
            dimensions: (100, 100, 100),
            spacingMM: Vec3(0.3, 0.3, 0.3),
            originMM: Vec3(0, 0, 0),
            rowDirection: Vec3(1, 0, 0),
            columnDirection: Vec3(0, 1, 0),
            sliceNormal: Vec3(0, 0, 1)
        )
    }

    func testCardinalLetters() {
        XCTAssertEqual(AnatomicOrientation.label(forPatientDirection: Vec3(1, 0, 0)), "L")
        XCTAssertEqual(AnatomicOrientation.label(forPatientDirection: Vec3(-1, 0, 0)), "R")
        XCTAssertEqual(AnatomicOrientation.label(forPatientDirection: Vec3(0, 1, 0)), "P")
        XCTAssertEqual(AnatomicOrientation.label(forPatientDirection: Vec3(0, -1, 0)), "A")
        XCTAssertEqual(AnatomicOrientation.label(forPatientDirection: Vec3(0, 0, 1)), "H")
        XCTAssertEqual(AnatomicOrientation.label(forPatientDirection: Vec3(0, 0, -1)), "F")
    }

    func testObliqueDirectionGetsCompoundLabel() {
        let label = AnatomicOrientation.label(forPatientDirection: Vec3(0.7, -0.7, 0))
        XCTAssertEqual(label, "LA")
        let dominant = AnatomicOrientation.label(forPatientDirection: Vec3(0.95, -0.1, 0))
        XCTAssertEqual(dominant, "L")
    }

    func testCompoundOrderFollowsMagnitude() {
        XCTAssertEqual(AnatomicOrientation.label(forPatientDirection: Vec3(0.5, -0.8, 0)), "AL")
        XCTAssertEqual(AnatomicOrientation.label(forPatientDirection: Vec3(0.4, 0, 0.9)), "HL")
    }

    func testZeroDirectionProducesEmptyLabel() {
        XCTAssertEqual(AnatomicOrientation.label(forPatientDirection: Vec3(0, 0, 0)), "")
    }

    func testAxialPaneFollowsRadiologicalConvention() {
        let frame = MPRPlaneFrame(kind: .axial, geometry: identityGeometry())
        XCTAssertEqual(frame.rightEdgeLabel, "L")
        XCTAssertEqual(frame.leftEdgeLabel, "R")
        XCTAssertEqual(frame.topEdgeLabel, "A")
        XCTAssertEqual(frame.bottomEdgeLabel, "P")
    }

    func testCoronalPaneLabels() {
        let frame = MPRPlaneFrame(kind: .coronal, geometry: identityGeometry())
        XCTAssertEqual(frame.rightEdgeLabel, "L")
        XCTAssertEqual(frame.leftEdgeLabel, "R")
        XCTAssertEqual(frame.topEdgeLabel, "H")
        XCTAssertEqual(frame.bottomEdgeLabel, "F")
    }

    func testSagittalPaneShowsAnteriorOnScreenLeft() {
        let frame = MPRPlaneFrame(kind: .sagittal, geometry: identityGeometry())
        XCTAssertEqual(frame.leftEdgeLabel, "A")
        XCTAssertEqual(frame.rightEdgeLabel, "P")
        XCTAssertEqual(frame.topEdgeLabel, "H")
        XCTAssertEqual(frame.bottomEdgeLabel, "F")
    }

    func testPaneAxesFormRightHandedViewFromConventionalSide() {
        for kind in MPRPlaneKind.allCases {
            let right = kind.patientScreenRight
            let up = kind.patientScreenUp
            let towardViewer = Vec3(
                right.y * up.z - right.z * up.y,
                right.z * up.x - right.x * up.z,
                right.x * up.y - right.y * up.x
            )
            switch kind {
            case .axial:
                XCTAssertEqual(towardViewer.z, -1, accuracy: 1e-9)
            case .coronal:
                XCTAssertEqual(towardViewer.y, -1, accuracy: 1e-9)
            case .sagittal:
                XCTAssertEqual(towardViewer.x, 1, accuracy: 1e-9)
            }
        }
    }

    func testLocalDirectionsFollowVolumeOrientation() {
        let rotated = VolumeGeometry(
            dimensions: (100, 100, 100),
            spacingMM: Vec3(0.3, 0.3, 0.3),
            originMM: Vec3(0, 0, 0),
            rowDirection: Vec3(0, 1, 0),
            columnDirection: Vec3(-1, 0, 0),
            sliceNormal: Vec3(0, 0, 1)
        )
        let frame = MPRPlaneFrame(kind: .axial, geometry: rotated)
        XCTAssertEqual(frame.localRight.x, 0, accuracy: 1e-9)
        XCTAssertEqual(frame.localRight.y, -1, accuracy: 1e-9)
        XCTAssertEqual(frame.localUp.x, -1, accuracy: 1e-9)
        XCTAssertEqual(frame.localUp.y, 0, accuracy: 1e-9)
        XCTAssertEqual(frame.rightEdgeLabel, "L")
    }

    func testRoundTripLocalPatientDirections() {
        let geometry = identityGeometry()
        let direction = Vec3(0.36, -0.48, 0.8)
        let local = MPRPlaneFrame.localDirection(direction, geometry: geometry)
        let back = MPRPlaneFrame.patientDirection(local, geometry: geometry)
        XCTAssertEqual(back.x, direction.normalized.x, accuracy: 1e-9)
        XCTAssertEqual(back.y, direction.normalized.y, accuracy: 1e-9)
        XCTAssertEqual(back.z, direction.normalized.z, accuracy: 1e-9)
    }

    func testWindowLevelAdjustmentClamps() {
        let level = WindowLevel.bone.adjusted(centerDelta: 100_000, widthDelta: -100_000)
        XCTAssertEqual(level.center, WindowLevel.centerRange.upperBound)
        XCTAssertEqual(level.width, WindowLevel.widthRange.lowerBound)
        XCTAssertEqual(WindowLevel(center: 300, width: 1500).displayText, "C 300 / W 1500")
    }
}
