import CoreGraphics
import simd
import JawAtlasCore

struct SliceMarkMapper: Sendable {
    let planeToLocal: simd_float4x4
    let size: CGSize

    func localMM(fromScreenPoint point: CGPoint) -> Vec3 {
        let width = max(Float(size.width), 1)
        let height = max(Float(size.height), 1)
        let u = Float(point.x) / width * 2 - 1
        let v = 1 - Float(point.y) / height * 2
        let local = planeToLocal * SIMD4<Float>(u, v, 0, 1)
        return Vec3(Double(local.x), Double(local.y), Double(local.z))
    }

    func screenPoint(fromLocalMM point: Vec3) -> CGPoint {
        let center = planeToLocal.columns.3
        let delta = SIMD3<Float>(
            Float(point.x) - center.x,
            Float(point.y) - center.y,
            Float(point.z) - center.z
        )
        let basisU = SIMD3<Float>(
            planeToLocal.columns.0.x,
            planeToLocal.columns.0.y,
            planeToLocal.columns.0.z
        )
        let basisV = SIMD3<Float>(
            planeToLocal.columns.1.x,
            planeToLocal.columns.1.y,
            planeToLocal.columns.1.z
        )
        let u = simd_dot(delta, basisU) / max(simd_length_squared(basisU), 1e-9)
        let v = simd_dot(delta, basisV) / max(simd_length_squared(basisV), 1e-9)
        return CGPoint(
            x: CGFloat((u + 1) / 2) * size.width,
            y: CGFloat((1 - v) / 2) * size.height
        )
    }
}
