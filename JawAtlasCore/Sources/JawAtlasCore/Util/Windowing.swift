import Foundation

public struct WindowLevel: Equatable, Sendable {
    public var center: Double
    public var width: Double

    public init(center: Double, width: Double) {
        self.center = center
        self.width = max(1, width)
    }

    public static let bone = WindowLevel(center: 300, width: 1500)
    public static let softTissue = WindowLevel(center: 50, width: 400)

    public static let centerRange: ClosedRange<Double> = -1000...3000
    public static let widthRange: ClosedRange<Double> = 10...4000

    public func adjusted(centerDelta: Double, widthDelta: Double) -> WindowLevel {
        WindowLevel(
            center: min(max(center + centerDelta, WindowLevel.centerRange.lowerBound), WindowLevel.centerRange.upperBound),
            width: min(max(width + widthDelta, WindowLevel.widthRange.lowerBound), WindowLevel.widthRange.upperBound)
        )
    }

    public var displayText: String {
        String(format: "C %.0f / W %.0f", center, width)
    }

    public func normalize(_ hu: Double) -> Double {
        let low = center - width / 2
        let value = (hu - low) / width
        return min(max(value, 0), 1)
    }

    public func byteValue(_ hu: Int16) -> UInt8 {
        UInt8(normalize(Double(hu)) * 255)
    }
}

public enum WindowPreset: String, CaseIterable, Sendable {
    case bone
    case softTissue
    case custom

    public var displayName: String {
        switch self {
        case .bone: return "Bone"
        case .softTissue: return "Soft Tissue"
        case .custom: return "Custom"
        }
    }

    public var level: WindowLevel? {
        switch self {
        case .bone: return .bone
        case .softTissue: return .softTissue
        case .custom: return nil
        }
    }
}
