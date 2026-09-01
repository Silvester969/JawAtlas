import Foundation
import simd

struct LowPassFilter {
    private(set) var value: Float?

    mutating func apply(_ input: Float, alpha: Float) -> Float {
        guard let previous = value else {
            value = input
            return input
        }
        let output = previous + alpha * (input - previous)
        value = output
        return output
    }

    mutating func reset() {
        value = nil
    }
}

struct OneEuroFilter {
    var minCutoff: Float
    var beta: Float
    var derivativeCutoff: Float
    private var valueFilter = LowPassFilter()
    private var derivativeFilter = LowPassFilter()
    private var lastTime: Double?

    init(minCutoff: Float, beta: Float, derivativeCutoff: Float = 1) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    private static func alpha(cutoff: Float, interval: Float) -> Float {
        let tau = 1 / (2 * Float.pi * max(cutoff, 0.0001))
        return 1 / (1 + tau / max(interval, 0.0001))
    }

    mutating func filter(_ input: Float, at time: Double) -> Float {
        guard let previousTime = lastTime, time > previousTime else {
            lastTime = time
            _ = derivativeFilter.apply(0, alpha: 1)
            return valueFilter.apply(input, alpha: 1)
        }
        let interval = Float(time - previousTime)
        lastTime = time
        let previous = valueFilter.value ?? input
        let derivative = (input - previous) / max(interval, 0.00001)
        let smoothedDerivative = derivativeFilter.apply(
            derivative,
            alpha: OneEuroFilter.alpha(cutoff: derivativeCutoff, interval: interval)
        )
        let cutoff = minCutoff + beta * abs(smoothedDerivative)
        return valueFilter.apply(input, alpha: OneEuroFilter.alpha(cutoff: cutoff, interval: interval))
    }

    mutating func reset() {
        valueFilter.reset()
        derivativeFilter.reset()
        lastTime = nil
    }
}

struct PoseFilter {
    private var eyeFilters: [OneEuroFilter]
    private var forwardFilters: [OneEuroFilter]
    private var upFilters: [OneEuroFilter]

    init(
        positionCutoff: Float = 0.6,
        positionBeta: Float = 60,
        directionCutoff: Float = 0.8,
        directionBeta: Float = 25
    ) {
        eyeFilters = (0..<3).map { _ in OneEuroFilter(minCutoff: positionCutoff, beta: positionBeta) }
        forwardFilters = (0..<3).map { _ in OneEuroFilter(minCutoff: directionCutoff, beta: directionBeta) }
        upFilters = (0..<3).map { _ in OneEuroFilter(minCutoff: directionCutoff, beta: directionBeta) }
    }

    mutating func filter(viewMatrix: simd_float4x4, at time: Double) -> simd_float4x4 {
        let worldFromEye = viewMatrix.inverse
        let eye = SIMD3<Float>(
            worldFromEye.columns.3.x,
            worldFromEye.columns.3.y,
            worldFromEye.columns.3.z
        )
        let forward = -SIMD3<Float>(
            worldFromEye.columns.2.x,
            worldFromEye.columns.2.y,
            worldFromEye.columns.2.z
        )
        let up = SIMD3<Float>(
            worldFromEye.columns.1.x,
            worldFromEye.columns.1.y,
            worldFromEye.columns.1.z
        )

        var filteredEye = SIMD3<Float>(0, 0, 0)
        var filteredForward = SIMD3<Float>(0, 0, 0)
        var filteredUp = SIMD3<Float>(0, 0, 0)
        for axis in 0..<3 {
            filteredEye[axis] = eyeFilters[axis].filter(eye[axis], at: time)
            filteredForward[axis] = forwardFilters[axis].filter(forward[axis], at: time)
            filteredUp[axis] = upFilters[axis].filter(up[axis], at: time)
        }

        guard simd_length(filteredForward) > 0.001, simd_length(filteredUp) > 0.001 else {
            return viewMatrix
        }
        let direction = simd_normalize(filteredForward)
        return RenderMath.lookAt(eye: filteredEye, center: filteredEye + direction, up: simd_normalize(filteredUp))
    }

    mutating func reset() {
        for axis in 0..<3 {
            eyeFilters[axis].reset()
            forwardFilters[axis].reset()
            upFilters[axis].reset()
        }
    }
}
