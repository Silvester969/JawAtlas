import Foundation

public struct VolumeGeometry: Sendable, Equatable {
    public let dimensions: (Int, Int, Int)
    public let spacingMM: Vec3
    public let originMM: Vec3
    public let rowDirection: Vec3
    public let columnDirection: Vec3
    public let sliceNormal: Vec3

    public init(
        dimensions: (Int, Int, Int),
        spacingMM: Vec3,
        originMM: Vec3,
        rowDirection: Vec3,
        columnDirection: Vec3,
        sliceNormal: Vec3
    ) {
        self.dimensions = dimensions
        self.spacingMM = spacingMM
        self.originMM = originMM
        self.rowDirection = rowDirection.normalized
        self.columnDirection = columnDirection.normalized
        self.sliceNormal = sliceNormal.normalized
    }

    public init(manifest: BundleManifest) {
        let rows = manifest.orientation
        self.init(
            dimensions: (manifest.dimensions[0], manifest.dimensions[1], manifest.dimensions[2]),
            spacingMM: Vec3(manifest.spacingMM[0], manifest.spacingMM[1], manifest.spacingMM[2]),
            originMM: Vec3(manifest.originMM[0], manifest.originMM[1], manifest.originMM[2]),
            rowDirection: Vec3(Double(rows[0][0]), Double(rows[0][1]), Double(rows[0][2])),
            columnDirection: Vec3(Double(rows[1][0]), Double(rows[1][1]), Double(rows[1][2])),
            sliceNormal: Vec3(Double(rows[2][0]), Double(rows[2][1]), Double(rows[2][2]))
        )
    }

    public static func == (lhs: VolumeGeometry, rhs: VolumeGeometry) -> Bool {
        lhs.dimensions == rhs.dimensions
            && lhs.spacingMM == rhs.spacingMM
            && lhs.originMM == rhs.originMM
            && lhs.rowDirection == rhs.rowDirection
            && lhs.columnDirection == rhs.columnDirection
            && lhs.sliceNormal == rhs.sliceNormal
    }

    public var width: Int { dimensions.0 }
    public var height: Int { dimensions.1 }
    public var depth: Int { dimensions.2 }

    public var extentMM: Vec3 {
        Vec3(
            Double(width) * spacingMM.x,
            Double(height) * spacingMM.y,
            Double(depth) * spacingMM.z
        )
    }

    public var diagonalMM: Double { extentMM.length }

    public var centerPatientMM: Vec3 {
        patientPoint(fromLocalMM: Vec3.zero)
    }

    public func localMM(fromVoxel voxel: Vec3) -> Vec3 {
        let extent = extentMM
        return Vec3(
            (voxel.x + 0.5) * spacingMM.x - extent.x / 2,
            (voxel.y + 0.5) * spacingMM.y - extent.y / 2,
            (voxel.z + 0.5) * spacingMM.z - extent.z / 2
        )
    }

    public func voxel(fromLocalMM local: Vec3) -> Vec3 {
        let extent = extentMM
        return Vec3(
            (local.x + extent.x / 2) / spacingMM.x - 0.5,
            (local.y + extent.y / 2) / spacingMM.y - 0.5,
            (local.z + extent.z / 2) / spacingMM.z - 0.5
        )
    }

    public func patientPoint(fromLocalMM local: Vec3) -> Vec3 {
        let extent = extentMM
        let alongRow = local.x + extent.x / 2 - spacingMM.x / 2
        let alongColumn = local.y + extent.y / 2 - spacingMM.y / 2
        let alongNormal = local.z + extent.z / 2 - spacingMM.z / 2
        return Vec3(
            originMM.x + rowDirection.x * alongRow + columnDirection.x * alongColumn + sliceNormal.x * alongNormal,
            originMM.y + rowDirection.y * alongRow + columnDirection.y * alongColumn + sliceNormal.y * alongNormal,
            originMM.z + rowDirection.z * alongRow + columnDirection.z * alongColumn + sliceNormal.z * alongNormal
        )
    }

    public func localMM(fromPatient patient: Vec3) -> Vec3 {
        let delta = Vec3(
            patient.x - originMM.x,
            patient.y - originMM.y,
            patient.z - originMM.z
        )
        let extent = extentMM
        return Vec3(
            delta.dot(rowDirection) - extent.x / 2 + spacingMM.x / 2,
            delta.dot(columnDirection) - extent.y / 2 + spacingMM.y / 2,
            delta.dot(sliceNormal) - extent.z / 2 + spacingMM.z / 2
        )
    }

    public func voxel(fromPatient patient: Vec3) -> Vec3 {
        voxel(fromLocalMM: localMM(fromPatient: patient))
    }

    public func patientPoint(fromVoxel voxel: Vec3) -> Vec3 {
        patientPoint(fromLocalMM: localMM(fromVoxel: voxel))
    }

    public func textureCoordinate(fromLocalMM local: Vec3) -> Vec3 {
        let extent = extentMM
        return Vec3(
            (local.x + extent.x / 2) / extent.x,
            (local.y + extent.y / 2) / extent.y,
            (local.z + extent.z / 2) / extent.z
        )
    }

    public func containsLocalMM(_ local: Vec3) -> Bool {
        let extent = extentMM
        return abs(local.x) <= extent.x / 2
            && abs(local.y) <= extent.y / 2
            && abs(local.z) <= extent.z / 2
    }

    public func clampedVoxel(_ voxel: Vec3) -> Vec3 {
        Vec3(
            min(max(voxel.x, 0), Double(width - 1)),
            min(max(voxel.y, 0), Double(height - 1)),
            min(max(voxel.z, 0), Double(depth - 1))
        )
    }
}
