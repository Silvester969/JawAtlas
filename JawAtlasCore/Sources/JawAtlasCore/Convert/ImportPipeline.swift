import Foundation

public enum ImportPipeline {
    public static let maximumFileCount = 20000

    public static func collectFiles(from urls: [URL]) -> [URL] {
        let manager = FileManager.default
        var collected: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                guard let enumerator = manager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }
                for case let item as URL in enumerator {
                    let isRegular = (try? item.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
                    guard isRegular else { continue }
                    collected.append(item)
                    if collected.count >= maximumFileCount { return collected }
                }
            } else {
                collected.append(url)
                if collected.count >= maximumFileCount { return collected }
            }
        }
        return collected
    }

    public static func scan(
        files: [URL],
        progress: @Sendable (ImportProgress) -> Void = { _ in }
    ) throws -> SeriesScanResult {
        guard !files.isEmpty else { throw ImportError.nothingSelected }
        var slices: [DICOMSlice] = []
        slices.reserveCapacity(files.count)
        var unreadable = 0
        var ignored = 0

        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            progress(ImportProgress(phase: .reading, completed: index, total: files.count))
            guard DICOMParser.isDICOM(fileAt: file) else {
                ignored += 1
                continue
            }
            do {
                slices.append(contentsOf: try DICOMParser.parseExpanded(fileAt: file))
            } catch {
                unreadable += 1
            }
        }
        progress(ImportProgress(phase: .validating, completed: files.count, total: files.count))
        guard !slices.isEmpty else {
            throw ImportError.noReadableFiles(unreadable: unreadable, ignored: ignored)
        }
        let result = SeriesBuilder.build(from: slices, unreadable: unreadable, ignored: ignored)
        guard !result.candidates.isEmpty else {
            throw ImportError.noUsableSeries(unreadable: unreadable, ignored: ignored)
        }
        return result
    }

    public static func scan(
        urls: [URL],
        progress: @Sendable (ImportProgress) -> Void = { _ in }
    ) throws -> SeriesScanResult {
        try scan(files: collectFiles(from: urls), progress: progress)
    }
}
