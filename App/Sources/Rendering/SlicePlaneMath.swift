import simd

enum SlicePlaneMath {
    static func planeNormal(azimuth: Float, elevation: Float) -> SIMD3<Float> {
        SIMD3<Float>(
            sin(azimuth) * cos(elevation),
            -cos(azimuth) * cos(elevation),
            sin(elevation)
        )
    }

    static func planeAxes(
        azimuth: Float,
        elevation: Float
    ) -> (normal: SIMD3<Float>, horizontal: SIMD3<Float>, vertical: SIMD3<Float>) {
        let normal = planeNormal(azimuth: azimuth, elevation: elevation)
        let horizontal = SIMD3<Float>(cos(azimuth), sin(azimuth), 0)
        let vertical = simd_normalize(simd_cross(normal, horizontal))
        return (normal, horizontal, vertical)
    }

    static func focusPoint(
        azimuth: Float,
        elevation: Float,
        offsetMM: Float,
        pan: SIMD2<Float>
    ) -> SIMD3<Float> {
        let axes = planeAxes(azimuth: azimuth, elevation: elevation)
        return axes.normal * offsetMM + axes.horizontal * pan.x + axes.vertical * pan.y
    }

    static func pose(
        focus: SIMD3<Float>,
        azimuth: Float,
        elevation: Float
    ) -> (offsetMM: Float, pan: SIMD2<Float>) {
        let axes = planeAxes(azimuth: azimuth, elevation: elevation)
        return (
            simd_dot(focus, axes.normal),
            SIMD2<Float>(simd_dot(focus, axes.horizontal), simd_dot(focus, axes.vertical))
        )
    }

    static func planeToLocal(
        azimuth: Float,
        elevation: Float = 0,
        offsetMM: Float,
        pan: SIMD2<Float>,
        spanMM: Float,
        aspect: Float
    ) -> simd_float4x4 {
        let halfHeight = spanMM / 2
        let halfWidth = halfHeight * aspect
        let normal = planeNormal(azimuth: azimuth, elevation: elevation)
        let horizontal = SIMD3<Float>(cos(azimuth), sin(azimuth), 0)
        let vertical = simd_normalize(simd_cross(normal, horizontal))
        let center = normal * offsetMM + horizontal * pan.x + vertical * pan.y
        return simd_float4x4(
            SIMD4<Float>(horizontal * halfWidth, 0),
            SIMD4<Float>(vertical * halfHeight, 0),
            SIMD4<Float>(normal, 0),
            SIMD4<Float>(center, 1)
        )
    }
}
