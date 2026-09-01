import Foundation

public struct ArchCurve: Sendable, Equatable {
    public static let minimumControlPoints = 4

    public var controlPointsLocalMM: [Vec3]

    public init(controlPointsLocalMM: [Vec3]) {
        self.controlPointsLocalMM = controlPointsLocalMM
    }

    public var isUsable: Bool {
        controlPointsLocalMM.count >= ArchCurve.minimumControlPoints
    }

    public static func catmullRom(_ p0: Vec3, _ p1: Vec3, _ p2: Vec3, _ p3: Vec3, _ t: Double) -> Vec3 {
        let t2 = t * t
        let t3 = t2 * t
        func blend(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
            0.5 * ((2 * b)
                + (-a + c) * t
                + (2 * a - 5 * b + 4 * c - d) * t2
                + (-a + 3 * b - 3 * c + d) * t3)
        }
        return Vec3(
            blend(p0.x, p1.x, p2.x, p3.x),
            blend(p0.y, p1.y, p2.y, p3.y),
            blend(p0.z, p1.z, p2.z, p3.z)
        )
    }

    public func densePolyline(subdivisions: Int = 24) -> [Vec3] {
        let points = controlPointsLocalMM
        guard points.count >= 2 else { return points }
        var padded = points
        padded.insert(points[0], at: 0)
        padded.append(points[points.count - 1])
        var result: [Vec3] = []
        for segment in 1..<(padded.count - 2) {
            for step in 0..<subdivisions {
                let t = Double(step) / Double(subdivisions)
                result.append(ArchCurve.catmullRom(
                    padded[segment - 1],
                    padded[segment],
                    padded[segment + 1],
                    padded[segment + 2],
                    t
                ))
            }
        }
        result.append(points[points.count - 1])
        return result
    }

    public func totalLengthMM(subdivisions: Int = 24) -> Double {
        let dense = densePolyline(subdivisions: subdivisions)
        guard dense.count >= 2 else { return 0 }
        var length = 0.0
        for index in 1..<dense.count {
            length += (dense[index] - dense[index - 1]).length
        }
        return length
    }

    public func resampledUniformly(count: Int, subdivisions: Int = 24) -> [Vec3] {
        guard count >= 2 else { return [] }
        let dense = densePolyline(subdivisions: subdivisions)
        guard dense.count >= 2 else { return [] }
        var cumulative: [Double] = [0]
        cumulative.reserveCapacity(dense.count)
        for index in 1..<dense.count {
            cumulative.append(cumulative[index - 1] + (dense[index] - dense[index - 1]).length)
        }
        let total = cumulative[cumulative.count - 1]
        guard total > 0 else { return [] }
        var result: [Vec3] = []
        result.reserveCapacity(count)
        var cursor = 0
        for sample in 0..<count {
            let target = total * Double(sample) / Double(count - 1)
            while cursor < dense.count - 2 && cumulative[cursor + 1] < target {
                cursor += 1
            }
            let segmentLength = cumulative[cursor + 1] - cumulative[cursor]
            let fraction = segmentLength > 0 ? (target - cumulative[cursor]) / segmentLength : 0
            result.append(dense[cursor] + (dense[cursor + 1] - dense[cursor]) * fraction)
        }
        return result
    }

    public static func orientedRightToLeft(
        _ points: [Vec3],
        geometry: VolumeGeometry
    ) -> [Vec3] {
        guard let first = points.first, let last = points.last else { return points }
        let firstPatient = geometry.patientPoint(fromLocalMM: first)
        let lastPatient = geometry.patientPoint(fromLocalMM: last)
        return firstPatient.x <= lastPatient.x ? points : points.reversed()
    }
}

public extension Vec3 {
    static func - (lhs: Vec3, rhs: Vec3) -> Vec3 {
        Vec3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }

    static func + (lhs: Vec3, rhs: Vec3) -> Vec3 {
        Vec3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }

    static func * (lhs: Vec3, rhs: Double) -> Vec3 {
        Vec3(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs)
    }
}
