import Foundation

public struct ImportProgress: Sendable, Equatable {
    public enum Phase: String, Sendable {
        case reading
        case validating
        case converting
        case verifying

        public var displayName: String {
            switch self {
            case .reading: return "Reading"
            case .validating: return "Validating"
            case .converting: return "Converting"
            case .verifying: return "Verifying"
            }
        }
    }

    public var phase: Phase
    public var completed: Int
    public var total: Int

    public init(phase: Phase, completed: Int, total: Int) {
        self.phase = phase
        self.completed = completed
        self.total = max(0, total)
    }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(completed) / Double(total))
    }

    public var countsDescription: String {
        total > 0 ? "\(min(completed, total)) of \(total) files" : "Preparing"
    }
}
