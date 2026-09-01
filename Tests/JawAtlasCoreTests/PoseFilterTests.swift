import XCTest
import simd
@testable import JawAtlas
@testable import JawAtlasCore

final class PoseFilterTests: XCTestCase {
    func testConstantInputPassesThroughUnchanged() {
        var filter = OneEuroFilter(minCutoff: 0.7, beta: 40)
        var time = 0.0
        var output: Float = 0
        for _ in 0..<60 {
            output = filter.filter(0.25, at: time)
            time += 1.0 / 60
        }
        XCTAssertEqual(output, 0.25, accuracy: 1e-5)
    }

    func testTremorIsAttenuated() {
        var filter = OneEuroFilter(minCutoff: 0.7, beta: 40)
        var time = 0.0
        _ = filter.filter(0, at: time)
        var peak: Float = 0
        for step in 1...240 {
            time += 1.0 / 60
            let tremor: Float = (step % 2 == 0 ? 1 : -1) * 0.003
            peak = max(peak, abs(filter.filter(tremor, at: time)))
        }
        XCTAssertLessThan(peak, 0.002)
    }

    func testDeliberateStepIsTrackedQuickly() {
        var filter = OneEuroFilter(minCutoff: 0.7, beta: 40)
        var time = 0.0
        _ = filter.filter(0, at: time)
        var value: Float = 0
        for _ in 0..<12 {
            time += 1.0 / 60
            value = filter.filter(0.3, at: time)
        }
        XCTAssertEqual(value, 0.3, accuracy: 0.02)
    }

    func testPoseFilterPreservesAStaticPose() {
        var filter = PoseFilter()
        let view = RenderMath.lookAt(
            eye: SIMD3<Float>(0.1, -0.2, 0.4),
            center: SIMD3<Float>(0, -0.3, -0.5),
            up: SIMD3<Float>(0, 1, 0)
        )
        var time = 0.0
        var output = view
        for _ in 0..<90 {
            output = filter.filter(viewMatrix: view, at: time)
            time += 1.0 / 60
        }
        for column in 0..<4 {
            for row in 0..<4 {
                XCTAssertEqual(output[column][row], view[column][row], accuracy: 1e-3)
            }
        }
    }

    func testPenetrationOutsideVolumeReportsApproachDistance() {
        let half = SIMD3<Float>(60, 60, 40)
        let result = ARSlicePlacement.penetration(
            planePointLocalMM: SIMD3<Float>(0, -160, 0),
            normalTowardViewer: SIMD3<Float>(0, -1, 0),
            halfExtentMM: half
        )
        XCTAssertEqual(result.fraction, 0)
        XCTAssertEqual(result.approachMM, 100, accuracy: 1e-3)
    }

    func testPenetrationThroughTheCentreIsHalf() {
        let half = SIMD3<Float>(60, 60, 40)
        let result = ARSlicePlacement.penetration(
            planePointLocalMM: SIMD3<Float>(0, 0, 0),
            normalTowardViewer: SIMD3<Float>(0, -1, 0),
            halfExtentMM: half
        )
        XCTAssertEqual(result.fraction, 0.5, accuracy: 1e-4)
        XCTAssertEqual(result.approachMM, 0)
    }

    func testPenetrationBeyondVolumeIsComplete() {
        let half = SIMD3<Float>(60, 60, 40)
        let result = ARSlicePlacement.penetration(
            planePointLocalMM: SIMD3<Float>(0, 160, 0),
            normalTowardViewer: SIMD3<Float>(0, -1, 0),
            halfExtentMM: half
        )
        XCTAssertEqual(result.fraction, 1)
    }

    func testScrubOffsetMovesThePlaneForward() {
        let anchor = matrix_identity_float4x4
        let eye = SIMD3<Float>(0, 0, 0.4)
        let view = RenderMath.lookAt(eye: eye, center: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))
        let without = ARSlicePlacement.clipPlaneInLocalMillimetres(
            viewMatrix: view,
            anchorTransform: anchor
        )
        let with = ARSlicePlacement.clipPlaneInLocalMillimetres(
            viewMatrix: view,
            anchorTransform: anchor,
            forwardOffsetMetres: 0.025
        )
        let shift = with.point - without.point
        XCTAssertEqual(simd_length(shift), 25, accuracy: 0.01)
        XCTAssertLessThan(simd_dot(simd_normalize(shift), with.normal), -0.999)
    }
}

extension PoseFilterTests {
    func testFrustumPlaneAlignsExactlyWithTheProjectedVolume() {
        let anchor = matrix_identity_float4x4
        let eye = SIMD3<Float>(0.05, 0.12, 0.4)
        let view = RenderMath.lookAt(eye: eye, center: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))
        let projection = RenderMath.perspective(fovyRadians: 60 * .pi / 180, aspect: 0.46, near: 0.01, far: 8)
        let distance: Float = 0.3
        let plane = ARSlicePlacement.frustumPlaneToLocalMillimetres(
            viewMatrix: view,
            projectionMatrix: projection,
            anchorTransform: anchor,
            planeDistanceMetres: distance
        )
        let volumeViewProjection = ARSlicePlacement.volumeViewProjection(
            viewMatrix: view,
            projectionMatrix: projection,
            anchorTransform: anchor
        )
        for corner in [SIMD2<Float>(0.5, -0.25), SIMD2<Float>(-1, 1), SIMD2<Float>(0.9, 0.7)] {
            let localMM = plane * SIMD4<Float>(corner.x, corner.y, 0, 1)
            let clip = volumeViewProjection * localMM
            XCTAssertEqual(clip.x / clip.w, corner.x, accuracy: 1e-3)
            XCTAssertEqual(clip.y / clip.w, corner.y, accuracy: 1e-3)
        }
    }

    func testFrustumPlaneSitsAtTheRequestedDistance() {
        let anchor = matrix_identity_float4x4
        let eye = SIMD3<Float>(0, 0, 0.5)
        let view = RenderMath.lookAt(eye: eye, center: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))
        let projection = RenderMath.perspective(fovyRadians: 60 * .pi / 180, aspect: 0.5, near: 0.01, far: 8)
        let plane = ARSlicePlacement.frustumPlaneToLocalMillimetres(
            viewMatrix: view,
            projectionMatrix: projection,
            anchorTransform: anchor,
            planeDistanceMetres: 0.35
        )
        let centre = plane * SIMD4<Float>(0, 0, 0, 1)
        XCTAssertEqual(centre.x, 0, accuracy: 1e-3)
        XCTAssertEqual(centre.y, 0, accuracy: 1e-3)
        XCTAssertEqual(centre.z, 150, accuracy: 1e-2)
    }
}

extension PoseFilterTests {
    func testElevatedPlaneNormalPointsUpAtTopView() {
        let normal = SlicePlaneMath.planeNormal(azimuth: .pi, elevation: .pi / 2)
        XCTAssertEqual(normal.x, 0, accuracy: 1e-5)
        XCTAssertEqual(normal.y, 0, accuracy: 1e-5)
        XCTAssertEqual(normal.z, 1, accuracy: 1e-5)
        let matrix = SlicePlaneMath.planeToLocal(
            azimuth: .pi,
            elevation: .pi / 2,
            offsetMM: 0,
            pan: .zero,
            spanMM: 100,
            aspect: 1
        )
        let up = matrix.columns.1
        XCTAssertEqual(up.y, -50, accuracy: 1e-3)
        XCTAssertEqual(up.z, 0, accuracy: 1e-3)
    }

    func testTopViewAxesAreRadiological() {
        let axes = SlicePlaneMath.planeAxes(azimuth: 0, elevation: -.pi / 2)
        XCTAssertEqual(axes.horizontal.x, 1, accuracy: 1e-5)
        XCTAssertEqual(axes.vertical.y, -1, accuracy: 1e-5)
        let frontAxes = SlicePlaneMath.planeAxes(azimuth: 0, elevation: 0)
        XCTAssertEqual(frontAxes.horizontal.x, 1, accuracy: 1e-5)
        XCTAssertEqual(frontAxes.vertical.z, 1, accuracy: 1e-5)
    }
}

extension PoseFilterTests {
    func testFocusPointRoundTripsThroughPose() {
        let focus = SIMD3<Float>(-19.8, -14.0, 15.3)
        for (azimuth, elevation) in [(Float(0), Float(0)), (.pi / 2, 0), (.pi, .pi / 2), (0.7, -0.5)] {
            let pose = SlicePlaneMath.pose(focus: focus, azimuth: azimuth, elevation: elevation)
            let recovered = SlicePlaneMath.focusPoint(
                azimuth: azimuth,
                elevation: elevation,
                offsetMM: pose.offsetMM,
                pan: pose.pan
            )
            XCTAssertEqual(recovered.x, focus.x, accuracy: 1e-3)
            XCTAssertEqual(recovered.y, focus.y, accuracy: 1e-3)
            XCTAssertEqual(recovered.z, focus.z, accuracy: 1e-3)
        }
    }

    func testDirectionChangeKeepsTheFocusCentred() {
        let startPose = SlicePlaneMath.pose(focus: SIMD3<Float>(-16.4, -7.5, 14.6), azimuth: 0, elevation: 0)
        let focus = SlicePlaneMath.focusPoint(
            azimuth: 0,
            elevation: 0,
            offsetMM: startPose.offsetMM,
            pan: startPose.pan
        )
        let topPose = SlicePlaneMath.pose(focus: focus, azimuth: .pi, elevation: .pi / 2)
        let matrix = SlicePlaneMath.planeToLocal(
            azimuth: .pi,
            elevation: .pi / 2,
            offsetMM: topPose.offsetMM,
            pan: topPose.pan,
            spanMM: 72,
            aspect: 1
        )
        let centre = matrix * SIMD4<Float>(0, 0, 0, 1)
        XCTAssertEqual(centre.x, focus.x, accuracy: 1e-3)
        XCTAssertEqual(centre.y, focus.y, accuracy: 1e-3)
        XCTAssertEqual(centre.z, focus.z, accuracy: 1e-3)
    }
}
