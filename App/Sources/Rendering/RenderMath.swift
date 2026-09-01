import simd
import JawAtlasCore

enum RenderMath {
    static func perspective(fovyRadians: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let ys = 1 / tan(fovyRadians * 0.5)
        let xs = ys / max(aspect, 0.0001)
        let zs = far / (near - far)
        return simd_float4x4(
            SIMD4<Float>(xs, 0, 0, 0),
            SIMD4<Float>(0, ys, 0, 0),
            SIMD4<Float>(0, 0, zs, -1),
            SIMD4<Float>(0, 0, zs * near, 0)
        )
    }

    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let forward = simd_normalize(eye - center)
        var side = simd_cross(up, forward)
        if simd_length(side) < 1e-5 {
            side = simd_cross(SIMD3<Float>(1, 0, 0), forward)
        }
        side = simd_normalize(side)
        let trueUp = simd_cross(forward, side)
        return simd_float4x4(
            SIMD4<Float>(side.x, trueUp.x, forward.x, 0),
            SIMD4<Float>(side.y, trueUp.y, forward.y, 0),
            SIMD4<Float>(side.z, trueUp.z, forward.z, 0),
            SIMD4<Float>(-simd_dot(side, eye), -simd_dot(trueUp, eye), -simd_dot(forward, eye), 1)
        )
    }

    static func translation(_ value: SIMD3<Float>) -> simd_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4<Float>(value, 1)
        return matrix
    }

    static func float3(_ vector: Vec3) -> SIMD3<Float> {
        SIMD3<Float>(Float(vector.x), Float(vector.y), Float(vector.z))
    }

    static func vec3(_ vector: SIMD3<Float>) -> Vec3 {
        Vec3(Double(vector.x), Double(vector.y), Double(vector.z))
    }
}

struct OrbitCamera {
    var azimuth: Float = 0
    var elevation: Float = 0.18
    var distance: Float = 260
    var target: SIMD3<Float> = .zero

    static let minimumElevation: Float = -1.45
    static let maximumElevation: Float = 1.45

    mutating func reset(framing radius: Float) {
        azimuth = 0
        elevation = 0.18
        distance = radius * 2.4
        target = .zero
    }

    mutating func orbit(deltaX: Float, deltaY: Float) {
        azimuth -= deltaX
        elevation = min(max(elevation + deltaY, OrbitCamera.minimumElevation), OrbitCamera.maximumElevation)
    }

    mutating func zoom(scale: Float, radius: Float) {
        distance = min(max(distance / max(scale, 0.05), radius * 0.45), radius * 8)
    }

    var eye: SIMD3<Float> {
        let horizontal = cos(elevation)
        let direction = SIMD3<Float>(
            sin(azimuth) * horizontal,
            -cos(azimuth) * horizontal,
            sin(elevation)
        )
        return target + direction * distance
    }

    var up: SIMD3<Float> { SIMD3<Float>(0, 0, 1) }

    func viewProjection(aspect: Float, radius: Float) -> simd_float4x4 {
        let projection = RenderMath.perspective(
            fovyRadians: 45 * .pi / 180,
            aspect: aspect,
            near: max(1, distance - radius * 2),
            far: distance + radius * 3
        )
        return projection * RenderMath.lookAt(eye: eye, center: target, up: up)
    }
}
