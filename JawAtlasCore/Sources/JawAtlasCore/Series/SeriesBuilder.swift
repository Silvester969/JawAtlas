import Foundation

public enum SeriesBuilder {
    public static let minimumSlices = 4
    public static let spacingSanityRange = 0.0...10.0

    public static func build(from slices: [DICOMSlice], unreadable: Int = 0, ignored: Int = 0) -> SeriesScanResult {
        var groups: [String: [DICOMSlice]] = [:]
        for slice in slices {
            groups[groupKey(for: slice), default: []].append(slice)
        }
        var candidates: [SeriesCandidate] = []
        var rejected = 0
        for (key, group) in groups {
            if let candidate = makeCandidate(key: key, group: group) {
                candidates.append(candidate)
            } else {
                rejected += group.count
            }
        }
        candidates.sort { lhs, rhs in
            if lhs.isOriginalAcquisition != rhs.isOriginalAcquisition { return lhs.isOriginalAcquisition }
            return lhs.voxelCount > rhs.voxelCount
        }
        return SeriesScanResult(
            candidates: candidates,
            unreadableCount: unreadable,
            ignoredCount: ignored,
            rejectedSliceCount: rejected
        )
    }

    private static func groupKey(for slice: DICOMSlice) -> String {
        let normal = slice.sliceNormal.quantized(0.001)
        let row = slice.rowDirection.quantized(0.001)
        return [
            slice.studyUID,
            slice.seriesUID,
            String(slice.rows),
            String(slice.columns),
            String(format: "%.3f_%.3f_%.3f", row.x, row.y, row.z),
            String(format: "%.3f_%.3f_%.3f", normal.x, normal.y, normal.z)
        ].joined(separator: "|")
    }

    private static func makeCandidate(key: String, group: [DICOMSlice]) -> SeriesCandidate? {
        guard let first = group.first else { return nil }
        let normal = first.sliceNormal
        guard normal.length > 0.5 else { return nil }

        var sorted = group.sorted { $0.positionAlongNormal < $1.positionAlongNormal }
        var deduplicated: [DICOMSlice] = []
        for slice in sorted {
            if let previous = deduplicated.last,
               abs(previous.positionAlongNormal - slice.positionAlongNormal) < 1e-4 {
                continue
            }
            deduplicated.append(slice)
        }
        sorted = deduplicated
        guard sorted.count >= minimumSlices else { return nil }

        var deltas: [Double] = []
        deltas.reserveCapacity(sorted.count - 1)
        for index in 1..<sorted.count {
            deltas.append(abs(sorted[index].positionAlongNormal - sorted[index - 1].positionAlongNormal))
        }
        let median = medianValue(deltas)
        guard let zSpacing = resolveSliceSpacing(
            declared: first.spacingBetweenSlicesMM,
            derived: median,
            thickness: first.sliceThicknessMM
        ) else { return nil }

        let gapThreshold = max(median ?? zSpacing, zSpacing) * 1.5
        let isGapped = deltas.contains { $0 > gapThreshold + 1e-6 }

        let uidHash = StreamingHasher.hex(of: "\(first.studyUID)|\(first.seriesUID)|\(key)")

        return SeriesCandidate(
            id: key,
            slices: sorted,
            columns: first.columns,
            rows: first.rows,
            spacingMM: Vec3(first.columnSpacingMM, first.rowSpacingMM, zSpacing),
            origin: sorted[0].position,
            rowDirection: first.rowDirection,
            columnDirection: first.columnDirection,
            sliceNormal: normal,
            isGapped: isGapped,
            imageType: first.imageType,
            seriesUIDHash: uidHash
        )
    }

    public static func resolveSliceSpacing(declared: Double?, derived: Double?, thickness: Double?) -> Double? {
        for candidate in [declared, derived, thickness] {
            if let value = candidate, isSane(value) { return value }
        }
        return nil
    }

    public static func isSane(_ spacing: Double) -> Bool {
        spacing.isFinite && spacing > spacingSanityRange.lowerBound && spacing <= spacingSanityRange.upperBound
    }

    public static func medianValue(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[middle] }
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
}
