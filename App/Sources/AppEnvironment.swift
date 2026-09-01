import Foundation
import Observation
import JawAtlasCore

@MainActor
@Observable
final class AppEnvironment {
    enum LibraryState: Equatable {
        case loading
        case seeding(ImportProgress)
        case ready
        case failed(String)
    }

    let store: CaseStore
    let appLock = AppLock()
    private(set) var cases: [CaseRecord] = []
    private(set) var state: LibraryState = .loading
    private(set) var demoCaseID: String?
    private(set) var pendingImportURLs: [URL] = []
    private(set) var incomingFailureMessage: String?
    private var bootstrapTask: Task<Void, Never>?

    init(store: CaseStore = CaseStore(root: CaseStore.defaultRoot())) {
        self.store = store
    }

    var isBusy: Bool {
        switch state {
        case .loading, .seeding: return true
        case .ready, .failed: return false
        }
    }

    func bootstrap() async {
        if let bootstrapTask {
            await bootstrapTask.value
            return
        }
        let task = Task { await performBootstrap() }
        bootstrapTask = task
        await task.value
    }

    func receiveIncoming(url: URL) {
        Task { [weak self] in
            guard let self else { return }
            await self.bootstrap()
            await self.stageIncoming(url: url)
        }
    }

    func clearPendingImports() {
        pendingImportURLs = []
    }

    func clearIncomingFailure() {
        incomingFailureMessage = nil
    }

    private func stageIncoming(url: URL) async {
        let stagingDirectory = await store.stagingDirectory
        do {
            let staged = try await Task.detached(priority: .userInitiated) {
                try IncomingScanStager.stage(urls: [url], into: stagingDirectory)
            }.value
            pendingImportURLs.append(contentsOf: staged)
        } catch {
            incomingFailureMessage = AppEnvironment.message(for: error)
        }
    }

    private func performBootstrap() async {
        demoCaseID = DemoSeeder.storedDemoCaseID()
        do {
            try await store.prepare()
        } catch {
            state = .failed("Storage could not be prepared on this device.")
            return
        }
        cases = await store.reload()
        state = .ready
        if cases.isEmpty && demoCaseID == nil {
            await seedDemo()
        }
    }

    func refresh() async {
        cases = await store.reload()
        if case .failed = state { state = .ready }
    }

    func delete(_ record: CaseRecord) async {
        await store.delete(id: record.id)
        if record.id == demoCaseID {
            DemoSeeder.forgetDemoCaseID()
            demoCaseID = nil
        }
        await refresh()
    }

    func setPatientTag(_ record: CaseRecord, to tag: String) async {
        try? await store.setPatientTag(id: record.id, to: tag)
        await refresh()
    }

    func exportCase(_ record: CaseRecord) async -> URL? {
        let label = record.label.replacingOccurrences(of: "/", with: "-")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label).jawatlas.zip")
        try? FileManager.default.removeItem(at: destination)
        do {
            try await store.exportPackage(id: record.id, to: destination)
            await refresh()
            return destination
        } catch {
            return nil
        }
    }

    func rename(_ record: CaseRecord, to label: String) async {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await store.rename(id: record.id, to: trimmed)
        await refresh()
    }

    func adopt(caseID: String) async {
        await refresh()
        _ = caseID
    }

    func seedDemo() async {
        guard let folder = DemoSeeder.seedURL(in: .main) else {
            state = .ready
            return
        }
        state = .seeding(ImportProgress(phase: .reading, completed: 0, total: 0))
        let store = self.store
        let relay: @Sendable (ImportProgress) -> Void = { progress in
            guard progress.completed % 16 == 0 || progress.completed == progress.total else { return }
            Task { @MainActor [weak self] in
                guard let self, case .seeding = self.state else { return }
                self.state = .seeding(progress)
            }
        }
        do {
            let outcome = try await Task.detached(priority: .userInitiated) {
                try await DemoSeeder.seed(from: folder, into: store, progress: relay)
            }.value
            demoCaseID = outcome.record.id
            cases = await store.reload()
            state = .ready
        } catch {
            cases = await store.reload()
            state = .failed(AppEnvironment.message(for: error))
        }
    }

    func totalStorageBytes() -> Int64 {
        cases.reduce(0) { $0 + $1.storageByteCount }
    }

    func isDemo(_ record: CaseRecord) -> Bool { record.id == demoCaseID }

    static func message(for error: Error) -> String {
        if let importError = error as? ImportError { return importError.userMessage }
        if let volumeError = error as? VolumeError { return volumeError.userMessage }
        if let zipError = error as? ZipArchiveError { return zipError.userMessage }
        if let incomingError = error as? IncomingScanError { return incomingError.userMessage }
        if error is CancellationError { return ImportError.cancelled.userMessage }
        return "Something went wrong. Please try again."
    }
}
