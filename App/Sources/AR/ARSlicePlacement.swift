import Foundation
import simd
import JawAtlasCore

enum ARSlicePlacement {
    static func pointsToMetres(isPad: Bool) -> Float {
        isPad ? Float(0.0254 / 132.0) : Float(0.0254 / 163.0)
    }

    static func uprightTransform(
        at hitPosition: SIMD3<Float>,
        facing cameraPosition: SIMD3<Float>,
        geometry: VolumeGeometry
    ) -> simd_float4x4 {
        var toViewer = cameraPosition - hitPosition
        toViewer.y = 0
        if simd_length(toViewer) < 1e-4 {
            toViewer = SIMD3<Float>(0, 0, 1)
        }
        let forward = simd_normalize(toViewer)
        let superiorAxis = SIMD3<Float>(0, 1, 0)
        let anteriorImage = -forward
        let lateralImage = simd_normalize(simd_cross(anteriorImage, superiorAxis))
        let liftMetres = Float(geometry.extentMM.z / 2) * 0.001
        let origin = hitPosition + SIMD3<Float>(0, liftMetres, 0)
        return simd_float4x4(
            SIMD4<Float>(lateralImage, 0),
            SIMD4<Float>(anteriorImage, 0),
            SIMD4<Float>(superiorAxis, 0),
            SIMD4<Float>(origin, 1)
        )
    }

    static func planeToLocalMillimetres(
        viewMatrix: simd_float4x4,
        anchorTransform: simd_float4x4,
        viewportPoints: CGSize,
        pointsToMetres: Float,
        forwardOffsetMetres: Float = 0
    ) -> simd_float4x4 {
        let eyeFromWorld = viewMatrix
        let worldFromEye = eyeFromWorld.inverse
        let eyePosition = SIMD3<Float>(worldFromEye.columns.3.x, worldFromEye.columns.3.y, worldFromEye.columns.3.z)
        let screenRight = SIMD3<Float>(worldFromEye.columns.0.x, worldFromEye.columns.0.y, worldFromEye.columns.0.z)
        let screenUp = SIMD3<Float>(worldFromEye.columns.1.x, worldFromEye.columns.1.y, worldFromEye.columns.1.z)
        let forward = -SIMD3<Float>(worldFromEye.columns.2.x, worldFromEye.columns.2.y, worldFromEye.columns.2.z)
        let planeOrigin = eyePosition + forward * forwardOffsetMetres

        let halfWidth = Float(viewportPoints.width) * pointsToMetres / 2
        let halfHeight = Float(viewportPoints.height) * pointsToMetres / 2

        let screenPlane = simd_float4x4(
            SIMD4<Float>(screenRight * halfWidth, 0),
            SIMD4<Float>(screenUp * halfHeight, 0),
            SIMD4<Float>(0, 0, 0, 0),
            SIMD4<Float>(planeOrigin, 1)
        )

        let localFromWorld = anchorTransform.inverse
        var millimetres = matrix_identity_float4x4
        millimetres.columns.0.x = 1000
        millimetres.columns.1.y = 1000
        millimetres.columns.2.z = 1000
        return millimetres * localFromWorld * screenPlane
    }

    static func clipPlaneInLocalMillimetres(
        viewMatrix: simd_float4x4,
        anchorTransform: simd_float4x4,
        forwardOffsetMetres: Float = 0
    ) -> (point: SIMD3<Float>, normal: SIMD3<Float>) {
        let worldFromEye = viewMatrix.inverse
        let eyePosition = SIMD3<Float>(worldFromEye.columns.3.x, worldFromEye.columns.3.y, worldFromEye.columns.3.z)
        let towardViewer = SIMD3<Float>(worldFromEye.columns.2.x, worldFromEye.columns.2.y, worldFromEye.columns.2.z)
        let planeOrigin = eyePosition - towardViewer * forwardOffsetMetres

        let localFromWorld = anchorTransform.inverse
        let localPoint = localFromWorld * SIMD4<Float>(planeOrigin, 1)
        let localNormal = localFromWorld * SIMD4<Float>(towardViewer, 0)
        return (
            SIMD3<Float>(localPoint.x, localPoint.y, localPoint.z) * 1000,
            simd_normalize(SIMD3<Float>(localNormal.x, localNormal.y, localNormal.z))
        )
    }

    static func penetration(
        planePointLocalMM point: SIMD3<Float>,
        normalTowardViewer normal: SIMD3<Float>,
        halfExtentMM half: SIMD3<Float>
    ) -> (fraction: Float, approachMM: Float) {
        var dMin = Float.greatestFiniteMagnitude
        var dMax = -Float.greatestFiniteMagnitude
        for index in 0..<8 {
            let corner = SIMD3<Float>(
                index & 1 == 0 ? -half.x : half.x,
                index & 2 == 0 ? -half.y : half.y,
                index & 4 == 0 ? -half.z : half.z
            )
            let distance = simd_dot(corner - point, normal)
            dMin = min(dMin, distance)
            dMax = max(dMax, distance)
        }
        if dMax <= 0 { return (0, -dMax) }
        if dMin >= 0 { return (1, 0) }
        return (dMax / (dMax - dMin), 0)
    }

    static func navigatorViewProjection(
        eyeLocalMM: SIMD3<Float>,
        radiusMM: Float
    ) -> simd_float4x4 {
        let horizontal = SIMD3<Float>(eyeLocalMM.x, eyeLocalMM.y, 0)
        let direction = simd_length(horizontal) < 1
            ? SIMD3<Float>(0, -1, 0)
            : simd_normalize(horizontal)
        let elevation: Float = 0.5
        let distance = radiusMM * 2.7
        let eye = SIMD3<Float>(
            direction.x * cos(elevation),
            direction.y * cos(elevation),
            sin(elevation)
        ) * distance
        let view = RenderMath.lookAt(eye: eye, center: .zero, up: SIMD3<Float>(0, 0, 1))
        let projection = RenderMath.perspective(
            fovyRadians: 40 * .pi / 180,
            aspect: 1,
            near: max(1, distance - radiusMM * 2),
            far: distance + radiusMM * 3
        )
        return projection * view
    }

    static func frustumPlaneToLocalMillimetres(
        viewMatrix: simd_float4x4,
        projectionMatrix: simd_float4x4,
        anchorTransform: simd_float4x4,
        planeDistanceMetres: Float
    ) -> simd_float4x4 {
        let worldFromEye = viewMatrix.inverse
        let eyePosition = SIMD3<Float>(worldFromEye.columns.3.x, worldFromEye.columns.3.y, worldFromEye.columns.3.z)
        let screenRight = SIMD3<Float>(worldFromEye.columns.0.x, worldFromEye.columns.0.y, worldFromEye.columns.0.z)
        let screenUp = SIMD3<Float>(worldFromEye.columns.1.x, worldFromEye.columns.1.y, worldFromEye.columns.1.z)
        let forward = -SIMD3<Float>(worldFromEye.columns.2.x, worldFromEye.columns.2.y, worldFromEye.columns.2.z)

        let distance = max(planeDistanceMetres, 0.004)
        let tanHalfX = 1 / projectionMatrix.columns.0.x
        let tanHalfY = 1 / projectionMatrix.columns.1.y
        let halfWidth = distance * tanHalfX
        let halfHeight = distance * tanHalfY
        let planeOrigin = eyePosition + forward * distance

        let screenPlane = simd_float4x4(
            SIMD4<Float>(screenRight * halfWidth, 0),
            SIMD4<Float>(screenUp * halfHeight, 0),
            SIMD4<Float>(0, 0, 0, 0),
            SIMD4<Float>(planeOrigin, 1)
        )

        let localFromWorld = anchorTransform.inverse
        var millimetres = matrix_identity_float4x4
        millimetres.columns.0.x = 1000
        millimetres.columns.1.y = 1000
        millimetres.columns.2.z = 1000
        return millimetres * localFromWorld * screenPlane
    }

    static func volumeViewProjection(
        viewMatrix: simd_float4x4,
        projectionMatrix: simd_float4x4,
        anchorTransform: simd_float4x4
    ) -> simd_float4x4 {
        var metres = matrix_identity_float4x4
        metres.columns.0.x = 0.001
        metres.columns.1.y = 0.001
        metres.columns.2.z = 0.001
        return projectionMatrix * viewMatrix * anchorTransform * metres
    }
}
