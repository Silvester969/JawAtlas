import Foundation

public struct Vec3: Equatable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vec3(0, 0, 0)

    public func dot(_ other: Vec3) -> Double {
        x * other.x + y * other.y + z * other.z
    }

    public func cross(_ other: Vec3) -> Vec3 {
        Vec3(
            y * other.z - z * other.y,
            z * other.x - x * other.z,
            x * other.y - y * other.x
        )
    }

    public var length: Double { (x * x + y * y + z * z).squareRoot() }

    public var normalized: Vec3 {
        let l = length
        guard l > 1e-12 else { return Vec3(0, 0, 0) }
        return Vec3(x / l, y / l, z / l)
    }

    public func quantized(_ step: Double) -> Vec3 {
        Vec3((x / step).rounded() * step, (y / step).rounded() * step, (z / step).rounded() * step)
    }

    public func isClose(to other: Vec3, tolerance: Double) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance && abs(z - other.z) <= tolerance
    }
}
