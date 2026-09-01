import Foundation

public struct DemoSeedOutcome: Sendable {
    public var record: CaseRecord
    public var wasCreated: Bool
}

public enum DemoSeeder {
    public static let demoLabel = "Demo — missing teeth study case"
    public static let seedFolderName = "DemoSeries"
    public static let demoCaseDefaultsKey = "com.jawatlas.demoCaseID"

    public static func seedURL(in bundle: Bundle) -> URL? {
        bundle.url(forResource: seedFolderName, withExtension: nil)
    }

    public static func storedDemoCaseID(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: demoCaseDefaultsKey)
    }

    public static func rememberDemoCaseID(_ id: String, defaults: UserDefaults = .standard) {
        defaults.set(id, forKey: demoCaseDefaultsKey)
    }

    public static func forgetDemoCaseID(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: demoCaseDefaultsKey)
    }

    public static func seed(
        from folder: URL,
        into store: CaseStore,
        defaults: UserDefaults = .standard,
        progress: @Sendable (ImportProgress) -> Void = { _ in }
    ) async throws -> DemoSeedOutcome {
        let result = try ImportPipeline.scan(urls: [folder], progress: progress)
        guard let candidate = result.preferredCandidate else {
            throw ImportError.noUsableSeries(unreadable: result.unreadableCount, ignored: result.ignoredCount)
        }
        if let existing = await store.record(seriesUIDHash: candidate.seriesUIDHash) {
            rememberDemoCaseID(existing.id, defaults: defaults)
            return DemoSeedOutcome(record: existing, wasCreated: false)
        }
        let record = try await store.importSeries(candidate: candidate, label: demoLabel, progress: progress)
        rememberDemoCaseID(record.id, defaults: defaults)
        return DemoSeedOutcome(record: record, wasCreated: true)
    }
}
