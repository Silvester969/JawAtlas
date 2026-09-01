import Foundation

public enum MeasurementMath {
    public static func distanceMM(_ a: Vec3, _ b: Vec3) -> Double {
        (b - a).length
    }

    public static func angleDegrees(vertex: Vec3, first: Vec3, second: Vec3) -> Double {
        let u = (first - vertex).normalized
        let v = (second - vertex).normalized
        let cosine = min(max(u.dot(v), -1), 1)
        return acos(cosine) * 180 / .pi
    }

    public static func distanceText(_ millimetres: Double) -> String {
        String(format: "%.1f mm", millimetres)
    }

    public static func angleText(_ degrees: Double) -> String {
        String(format: "%.1f°", degrees)
    }
}
