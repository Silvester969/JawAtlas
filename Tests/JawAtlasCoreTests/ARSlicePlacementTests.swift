import XCTest
import simd
@testable import JawAtlas
@testable import JawAtlasCore

final class ARSlicePlacementTests: XCTestCase {
    private func demoGeometry() -> VolumeGeometry {
        VolumeGeometry(
            dimensions: (480, 480, 320),
            spacingMM: Vec3(0.265751, 0.265751, 0.2515),
            originMM: Vec3(0, 0, -80.4714),
            rowDirection: Vec3(1, 0, 0),
            columnDirection: Vec3(0, 1, 0),
            sliceNormal: Vec3(0, 0, 1)
        )
    }

    private func assertClose(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>, _ tolerance: Float) {
        XCTAssertEqual(lhs.x, rhs.x, accuracy: tolerance)
        XCTAssertEqual(lhs.y, rhs.y, accuracy: tolerance)
        XCTAssertEqual(lhs.z, rhs.z, accuracy: tolerance)
    }

    func testSuperiorAxisPointsUpAfterPlacement() {
        let geometry = demoGeometry()
        let transform = ARSlicePlacement.uprightTransform(
            at: SIMD3<Float>(0.2, -0.4, -0.6),
            facing: SIMD3<Float>(0.2, 0.1, 0),
            geometry: geometry
        )
        let superiorImage = (transform * SIMD4<Float>(0, 0, 1, 0)).xyz
        assertClose(superiorImage, SIMD3<Float>(0, 1, 0), 1e-5)
    }

    func testPlacementRestsTheVolumeOnTheSurface() {
        let geometry = demoGeometry()
        let hit = SIMD3<Float>(0, -0.35, -0.5)
        let transform = ARSlicePlacement.uprightTransform(
            at: hit,
            facing: SIMD3<Float>(0, 0.2, 0),
            geometry: geometry
        )
        let halfHeightMetres = Float(geometry.extentMM.z / 2) * 0.001
        XCTAssertEqual(transform.columns.3.y, hit.y + halfHeightMetres, accuracy: 1e-6)
        let bottomLocal = SIMD4<Float>(0, 0, -Float(geometry.extentMM.z / 2) * 0.001, 1)
        XCTAssertEqual((transform * bottomLocal).y, hit.y, accuracy: 1e-5)
    }

    func testAnteriorFacesTheViewer() {
        let geometry = demoGeometry()
        let hit = SIMD3<Float>(0, 0, -1)
        let camera = SIMD3<Float>(0, 0.3, 0)
        let transform = ARSlicePlacement.uprightTransform(at: hit, facing: camera, geometry: geometry)
        let anteriorImage = (transform * SIMD4<Float>(0, -1, 0, 0)).xyz
        var toViewer = camera - hit
        toViewer.y = 0
        assertClose(anteriorImage, simd_normalize(toViewer), 1e-5)
    }

    func testPlacementBasisStaysRightHanded() {
        let geometry = demoGeometry()
        let transform = ARSlicePlacement.uprightTransform(
            at: SIMD3<Float>(0.4, -0.2, -0.9),
            facing: SIMD3<Float>(-0.3, 0.4, 0.2),
            geometry: geometry
        )
        let x = transform.columns.0.xyz
        let y = transform.columns.1.xyz
        let z = transform.columns.2.xyz
        assertClose(simd_cross(x, y), z, 1e-5)
        XCTAssertEqual(simd_length(x), 1, accuracy: 1e-5)
        XCTAssertEqual(simd_length(y), 1, accuracy: 1e-5)
        XCTAssertEqual(simd_length(z), 1, accuracy: 1e-5)
    }

    func testScreenCentreMapsToTheCameraPositionInVolumeMillimetres() {
        let anchor = ARSlicePlacement.uprightTransform(
            at: SIMD3<Float>(0, -0.3, -0.5),
            facing: SIMD3<Float>(0, 0, 0),
            geometry: demoGeometry()
        )
        let eye = SIMD3<Float>(0.02, -0.1, -0.2)
        let view = RenderMath.lookAt(eye: eye, center: SIMD3<Float>(0, -0.3, -0.5), up: SIMD3<Float>(0, 1, 0))
        let matrix = ARSlicePlacement.planeToLocalMillimetres(
            viewMatrix: view,
            anchorTransform: anchor,
            viewportPoints: CGSize(width: 402, height: 874),
            pointsToMetres: ARSlicePlacement.pointsToMetres(isPad: false)
        )
        let centre = (matrix * SIMD4<Float>(0, 0, 0, 1)).xyz
        let expected = (anchor.inverse * SIMD4<Float>(eye, 1)).xyz * 1000
        assertClose(centre, expected, 1e-3)
    }

    func testCrossSectionIsLifeSize() {
        let anchor = ARSlicePlacement.uprightTransform(
            at: SIMD3<Float>(0, -0.3, -0.5),
            facing: SIMD3<Float>(0, 0, 0),
            geometry: demoGeometry()
        )
        let view = RenderMath.lookAt(
            eye: SIMD3<Float>(0, -0.25, -0.2),
            center: SIMD3<Float>(0, -0.3, -0.5),
            up: SIMD3<Float>(0, 1, 0)
        )
        let viewport = CGSize(width: 402, height: 874)
        let pointsToMetres = ARSlicePlacement.pointsToMetres(isPad: false)
        let matrix = ARSlicePlacement.planeToLocalMillimetres(
            viewMatrix: view,
            anchorTransform: anchor,
            viewportPoints: viewport,
            pointsToMetres: pointsToMetres
        )
        let left = (matrix * SIMD4<Float>(-1, 0, 0, 1)).xyz
        let right = (matrix * SIMD4<Float>(1, 0, 0, 1)).xyz
        let bottom = (matrix * SIMD4<Float>(0, -1, 0, 1)).xyz
        let top = (matrix * SIMD4<Float>(0, 1, 0, 1)).xyz

        let widthMM = simd_length(right - left)
        let heightMM = simd_length(top - bottom)
        let expectedWidthMM = Float(viewport.width) * pointsToMetres * 1000
        let expectedHeightMM = Float(viewport.height) * pointsToMetres * 1000

        XCTAssertEqual(widthMM, expectedWidthMM, accuracy: 0.02)
        XCTAssertEqual(heightMM, expectedHeightMM, accuracy: 0.02)
        XCTAssertEqual(expectedWidthMM, 62.6, accuracy: 0.5)
    }

    func testClipPlaneNormalPointsBackTowardTheViewer() {
        let anchor = ARSlicePlacement.uprightTransform(
            at: SIMD3<Float>(0, -0.3, -0.5),
            facing: SIMD3<Float>(0, 0, 0),
            geometry: demoGeometry()
        )
        let eye = SIMD3<Float>(0, -0.25, -0.15)
        let target = SIMD3<Float>(0, -0.3, -0.5)
        let view = RenderMath.lookAt(eye: eye, center: target, up: SIMD3<Float>(0, 1, 0))
        let clip = ARSlicePlacement.clipPlaneInLocalMillimetres(viewMatrix: view, anchorTransform: anchor)

        XCTAssertEqual(simd_length(clip.normal), 1, accuracy: 1e-5)
        let anchorCentreLocal = SIMD3<Float>(0, 0, 0)
        XCTAssertLessThan(simd_dot(anchorCentreLocal - clip.point, clip.normal), 0)
        let eyeLocal = (anchor.inverse * SIMD4<Float>(eye, 1)).xyz * 1000
        assertClose(clip.point, eyeLocal, 1e-2)
    }

    func testPointsToMetresMatchesDeviceDensities() {
        XCTAssertEqual(ARSlicePlacement.pointsToMetres(isPad: false), 0.0001558, accuracy: 1e-7)
        XCTAssertEqual(ARSlicePlacement.pointsToMetres(isPad: true), 0.0001924, accuracy: 1e-7)
    }
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3<Float>(x, y, z) }
}
