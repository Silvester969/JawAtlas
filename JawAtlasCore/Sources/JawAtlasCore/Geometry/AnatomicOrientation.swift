import Foundation

public enum AnatomicOrientation {
    public static func letter(component index: Int, positive: Bool) -> String {
        switch (index, positive) {
        case (0, true): return "L"
        case (0, false): return "R"
        case (1, true): return "P"
        case (1, false): return "A"
        case (2, true): return "H"
        default: return "F"
        }
    }

    public static func label(
        forPatientDirection direction: Vec3,
        maximumComponents: Int = 2,
        secondaryThreshold: Double = 0.35
    ) -> String {
        let normalized = direction.normalized
        let components = [normalized.x, normalized.y, normalized.z]
        let ranked = components.enumerated()
            .map { (index: $0.offset, magnitude: abs($0.element), positive: $0.element >= 0) }
            .sorted { $0.magnitude > $1.magnitude }
        guard let primary = ranked.first, primary.magnitude > 1e-6 else { return "" }
        var result = letter(component: primary.index, positive: primary.positive)
        for entry in ranked.dropFirst().prefix(maximumComponents - 1)
        where entry.magnitude >= secondaryThreshold {
            result += letter(component: entry.index, positive: entry.positive)
        }
        return result
    }
}

public enum MPRPlaneKind: String, CaseIterable, Sendable, Identifiable {
    case axial
    case coronal
    case sagittal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .axial: return "Axial"
        case .coronal: return "Coronal"
        case .sagittal: return "Sagittal"
        }
    }

    public var patientScreenRight: Vec3 {
        switch self {
        case .axial: return Vec3(1, 0, 0)
        case .coronal: return Vec3(1, 0, 0)
        case .sagittal: return Vec3(0, 1, 0)
        }
    }

    public var patientScreenUp: Vec3 {
        switch self {
        case .axial: return Vec3(0, -1, 0)
        case .coronal: return Vec3(0, 0, 1)
        case .sagittal: return Vec3(0, 0, 1)
        }
    }

    public var patientNormal: Vec3 {
        switch self {
        case .axial: return Vec3(0, 0, 1)
        case .coronal: return Vec3(0, 1, 0)
        case .sagittal: return Vec3(1, 0, 0)
        }
    }
}

public struct MPRPlaneFrame: Sendable, Equatable {
    public let kind: MPRPlaneKind
    public let localRight: Vec3
    public let localUp: Vec3
    public let localNormal: Vec3

    public init(kind: MPRPlaneKind, geometry: VolumeGeometry) {
        self.kind = kind
        self.localRight = MPRPlaneFrame.localDirection(kind.patientScreenRight, geometry: geometry)
        self.localUp = MPRPlaneFrame.localDirection(kind.patientScreenUp, geometry: geometry)
        self.localNormal = MPRPlaneFrame.localDirection(kind.patientNormal, geometry: geometry)
    }

    public static func localDirection(_ patient: Vec3, geometry: VolumeGeometry) -> Vec3 {
        Vec3(
            patient.dot(geometry.rowDirection),
            patient.dot(geometry.columnDirection),
            patient.dot(geometry.sliceNormal)
        ).normalized
    }

    public static func patientDirection(_ local: Vec3, geometry: VolumeGeometry) -> Vec3 {
        Vec3(
            geometry.rowDirection.x * local.x + geometry.columnDirection.x * local.y
                + geometry.sliceNormal.x * local.z,
            geometry.rowDirection.y * local.x + geometry.columnDirection.y * local.y
                + geometry.sliceNormal.y * local.z,
            geometry.rowDirection.z * local.x + geometry.columnDirection.z * local.y
                + geometry.sliceNormal.z * local.z
        ).normalized
    }

    public var rightEdgeLabel: String {
        AnatomicOrientation.label(forPatientDirection: kind.patientScreenRight)
    }

    public var leftEdgeLabel: String {
        AnatomicOrientation.label(forPatientDirection: kind.patientScreenRight.negated)
    }

    public var topEdgeLabel: String {
        AnatomicOrientation.label(forPatientDirection: kind.patientScreenUp)
    }

    public var bottomEdgeLabel: String {
        AnatomicOrientation.label(forPatientDirection: kind.patientScreenUp.negated)
    }
}

public extension Vec3 {
    var negated: Vec3 { Vec3(-x, -y, -z) }
}
