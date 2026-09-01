import Foundation

public struct CaseRecord: Identifiable, Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case ready
        case unreadable(String)

        public var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    public let id: String
    public var label: String
    public var importedAt: Date
    public var dimensions: [Int]
    public var spacingMM: [Double]
    public var isGapped: Bool
    public var seriesUIDHash: String
    public var patientTag: String?
    public var volumeByteCount: Int
    public var storageByteCount: Int64
    public var directory: URL
    public var status: Status

    public var thumbnailURL: URL? {
        let url = BundleLayout.thumbnailURL(in: directory)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public var dimensionsDescription: String {
        guard dimensions.count == 3 else { return "Unknown size" }
        return "\(dimensions[0]) × \(dimensions[1]) × \(dimensions[2]) voxels"
    }

    public var spacingDescription: String {
        guard spacingMM.count == 3 else { return "Unknown spacing" }
        return String(format: "%.3g × %.3g × %.3g mm", spacingMM[0], spacingMM[1], spacingMM[2])
    }

    public var physicalSizeDescription: String {
        guard dimensions.count == 3, spacingMM.count == 3 else { return "" }
        let extents = (0..<3).map { Double(dimensions[$0]) * spacingMM[$0] }
        return String(format: "%.1f × %.1f × %.1f mm", extents[0], extents[1], extents[2])
    }

    public var storageDescription: String {
        ByteCountFormatter.string(fromByteCount: storageByteCount, countStyle: .file)
    }
}
