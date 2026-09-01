import simd

struct VolumeUniforms {
    var inverseViewProjection = matrix_identity_float4x4
    var planeToLocal = matrix_identity_float4x4
    var cameraLocal = SIMD3<Float>(0, 0, 0)
    var stepMM: Float = 0.5
    var halfExtentMM = SIMD3<Float>(1, 1, 1)
    var windowLow: Float = -450
    var voxelStepTexture = SIMD3<Float>(0.001, 0.001, 0.001)
    var windowWidth: Float = 1500
    var tintColor = SIMD3<Float>(0.98, 0.94, 0.87)
    var opacityScale: Float = 0.9
    var lightDirection = SIMD3<Float>(0.3, -0.7, 0.5)
    var surfaceThreshold: Float = 400
    var surfaceSoftness: Float = 90
    var maximumSteps: Float = 512
    var ambient: Float = 0.28
    var crossSectionAlpha: Float = 1
    var clipPlanePoint = SIMD3<Float>(0, 0, 0)
    var clipEnabled: Float = 0
    var clipPlaneNormal = SIMD3<Float>(0, 0, 1)
    var crossSectionAirHU: Float = -10000
    var globalAlpha: Float = 1
    var emptyAlpha: Float = 0
    var panoPointCount: Float = 0
    var panoSlabMM: Float = 0
    var shadingEnabled: Float = 1
    var mipEnabled: Float = 0
    var reservedA: Float = 0
    var reservedB: Float = 0
}

enum VolumePresentation: String, CaseIterable, Identifiable {
    case bone
    case teeth
    case softTissue

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bone: return "Bone"
        case .teeth: return "Teeth"
        case .softTissue: return "Soft tissue"
        }
    }

    var surfaceThresholdHU: Float {
        switch self {
        case .bone: return 420
        case .teeth: return 1150
        case .softTissue: return -320
        }
    }

    var surfaceSoftnessHU: Float {
        switch self {
        case .bone: return 110
        case .teeth: return 160
        case .softTissue: return 90
        }
    }

    var tint: SIMD3<Float> {
        switch self {
        case .bone: return SIMD3<Float>(0.98, 0.945, 0.885)
        case .teeth: return SIMD3<Float>(0.99, 0.975, 0.93)
        case .softTissue: return SIMD3<Float>(0.94, 0.78, 0.70)
        }
    }

    var opacityScale: Float {
        switch self {
        case .bone: return 0.97
        case .teeth: return 0.98
        case .softTissue: return 0.9
        }
    }
}
