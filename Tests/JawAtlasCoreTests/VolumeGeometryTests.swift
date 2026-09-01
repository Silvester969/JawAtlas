import XCTest
@testable import JawAtlasCore

final class VolumeGeometryTests: XCTestCase {
    private func axisAligned() -> VolumeGeometry {
        VolumeGeometry(
            dimensions: (480, 480, 320),
            spacingMM: Vec3(0.265751, 0.265751, 0.2515),
            originMM: Vec3(0, 0, -80.4714),
            rowDirection: Vec3(1, 0, 0),
            columnDirection: Vec3(0, 1, 0),
            sliceNormal: Vec3(0, 0, 1)
        )
    }

    private func oblique() -> VolumeGeometry {
        let row = Vec3(1, 0, 0)
        let column = Vec3(0, 0.707106, -0.707106)
        return VolumeGeometry(
            dimensions: (64, 48, 32),
            spacingMM: Vec3(0.3, 0.4, 0.5),
            originMM: Vec3(-10, 25, 3),
            rowDirection: row,
            columnDirection: column,
            sliceNormal: row.cross(column)
        )
    }

    private func assertClose(_ lhs: Vec3, _ rhs: Vec3, _ tolerance: Double, _ message: String = "") {
        XCTAssertEqual(lhs.x, rhs.x, accuracy: tolerance, message)
        XCTAssertEqual(lhs.y, rhs.y, accuracy: tolerance, message)
        XCTAssertEqual(lhs.z, rhs.z, accuracy: tolerance, message)
    }

    func testFirstVoxelSitsAtTheDicomOrigin() {
        let geometry = axisAligned()
        assertClose(geometry.patientPoint(fromVoxel: Vec3(0, 0, 0)), geometry.originMM, 1e-9)
    }

    func testVoxelToPatientRoundTripAxisAligned() {
        let geometry = axisAligned()
        for voxel in [Vec3(0, 0, 0), Vec3(479, 479, 319), Vec3(318, 117, 117), Vec3(12.5, 300.25, 8.75)] {
            let patient = geometry.patientPoint(fromVoxel: voxel)
            assertClose(geometry.voxel(fromPatient: patient), voxel, 1e-6)
        }
    }

    func testVoxelToPatientRoundTripOblique() {
        let geometry = oblique()
        for voxel in [Vec3(0, 0, 0), Vec3(63, 47, 31), Vec3(20.5, 10.25, 4.75)] {
            let patient = geometry.patientPoint(fromVoxel: voxel)
            assertClose(geometry.voxel(fromPatient: patient), voxel, 1e-6)
        }
    }

    func testLocalSpaceIsCenteredOnTheVolume() {
        let geometry = axisAligned()
        let extent = geometry.extentMM
        XCTAssertEqual(extent.x, 480 * 0.265751, accuracy: 1e-9)
        XCTAssertEqual(extent.z, 320 * 0.2515, accuracy: 1e-9)
        let centreVoxel = Vec3(239.5, 239.5, 159.5)
        assertClose(geometry.localMM(fromVoxel: centreVoxel), Vec3.zero, 1e-9)
        XCTAssertTrue(geometry.containsLocalMM(Vec3.zero))
        XCTAssertFalse(geometry.containsLocalMM(Vec3(extent.x, 0, 0)))
    }

    func testLocalAndPatientRoundTrip() {
        let geometry = oblique()
        for local in [Vec3.zero, Vec3(3, -4, 5), Vec3(-9.1, 2.2, -1.3)] {
            let patient = geometry.patientPoint(fromLocalMM: local)
            assertClose(geometry.localMM(fromPatient: patient), local, 1e-9)
        }
    }

    func testTextureCoordinatesSpanTheUnitCube() {
        let geometry = axisAligned()
        let extent = geometry.extentMM
        assertClose(
            geometry.textureCoordinate(fromLocalMM: Vec3(-extent.x / 2, -extent.y / 2, -extent.z / 2)),
            Vec3(0, 0, 0),
            1e-9
        )
        assertClose(
            geometry.textureCoordinate(fromLocalMM: Vec3(extent.x / 2, extent.y / 2, extent.z / 2)),
            Vec3(1, 1, 1),
            1e-9
        )
        assertClose(geometry.textureCoordinate(fromLocalMM: .zero), Vec3(0.5, 0.5, 0.5), 1e-9)
    }

    func testMillimetreDistancesSurviveTheRoundTrip() {
        let geometry = oblique()
        let a = geometry.patientPoint(fromVoxel: Vec3(10, 10, 10))
        let b = geometry.patientPoint(fromVoxel: Vec3(20, 10, 10))
        let separation = Vec3(b.x - a.x, b.y - a.y, b.z - a.z).length
        XCTAssertEqual(separation, 10 * 0.3, accuracy: 1e-9)
    }

    func testGeometryFromManifestMatchesTheAuthoredValues() {
        let manifest = BundleManifest(
            caseID: "G",
            label: "geometry",
            importedAt: Date(timeIntervalSince1970: 0),
            dimensions: [480, 480, 320],
            spacingMM: [0.265751, 0.265751, 0.2515],
            orientation: [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0]],
            originMM: [0, 0, -80.4714],
            volumeSHA256: "x",
            isGapped: false,
            seriesUIDHash: "y"
        )
        XCTAssertEqual(VolumeGeometry(manifest: manifest), axisAligned())
    }

    func testDemoScanAnnotationLandsInsideTheVolume() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let annotation = repository.appendingPathComponent("App/Seeds/DemoSeries.roi.json")
        guard let data = try? Data(contentsOf: annotation) else {
            throw XCTSkip("Demo annotation is not present on this machine")
        }
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let markups = try XCTUnwrap(root["markups"] as? [[String: Any]])
        let centre = try XCTUnwrap(markups.first?["center"] as? [Double])
        XCTAssertEqual(markups.first?["coordinateSystem"] as? String, "LPS")

        let geometry = axisAligned()
        let site = Vec3(centre[0], centre[1], centre[2])
        let voxel = geometry.voxel(fromPatient: site)
        XCTAssertEqual(voxel.x, 317.7, accuracy: 1.0)
        XCTAssertEqual(voxel.y, 117.0, accuracy: 1.0)
        XCTAssertEqual(voxel.z, 116.8, accuracy: 1.0)
        XCTAssertTrue(geometry.containsLocalMM(geometry.localMM(fromPatient: site)))
        assertClose(geometry.patientPoint(fromVoxel: voxel), site, 1e-6)
    }
}
