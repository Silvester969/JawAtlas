import Foundation

public struct SeriesCandidate: Identifiable, Sendable {
    public let id: String
    public var slices: [DICOMSlice]
    public var columns: Int
    public var rows: Int
    public var spacingMM: Vec3
    public var origin: Vec3
    public var rowDirection: Vec3
    public var columnDirection: Vec3
    public var sliceNormal: Vec3
    public var isGapped: Bool
    public var imageType: String
    public var seriesUIDHash: String

    public var depth: Int { slices.count }

    public var voxelCount: Int { columns * rows * slices.count }

    public var volumeByteCount: Int { voxelCount * 2 }

    public var isOriginalAcquisition: Bool {
        let upper = imageType.uppercased()
        return upper.contains("ORIGINAL") && upper.contains("PRIMARY")
    }

    public var planeDescription: String {
        let upper = imageType.uppercased()
        if upper.contains("AXIAL") { return "Axial" }
        if upper.contains("CORONAL") { return "Coronal" }
        if upper.contains("SAGITTAL") { return "Sagittal" }
        if upper.contains("REFORMATTED") { return "Reformatted" }
        return "Volume"
    }

    public var sourceDescription: String {
        isOriginalAcquisition ? "Original" : "Derived"
    }

    public var displaySummary: String {
        let dimensions = "\(columns) × \(rows) × \(slices.count)"
        let spacing = String(format: "%.3g × %.3g × %.3g mm", spacingMM.x, spacingMM.y, spacingMM.z)
        return "\(dimensions) · \(spacing)"
    }

    public var displayTitle: String {
        "\(sourceDescription) \(planeDescription.lowercased()) series"
    }

    public var suggestedLabel: String {
        "\(planeDescription) CBCT \(columns)×\(rows)×\(slices.count)"
    }
}

public struct SeriesScanResult: Sendable {
    public var candidates: [SeriesCandidate]
    public var unreadableCount: Int
    public var ignoredCount: Int
    public var rejectedSliceCount: Int

    public var readableCount: Int { candidates.reduce(0) { $0 + $1.slices.count } + rejectedSliceCount }

    public var preferredCandidate: SeriesCandidate? {
        candidates.max { lhs, rhs in
            if lhs.isOriginalAcquisition != rhs.isOriginalAcquisition {
                return rhs.isOriginalAcquisition
            }
            return lhs.voxelCount < rhs.voxelCount
        }
    }
}
