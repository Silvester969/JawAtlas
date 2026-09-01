import Foundation
import Observation
import JawAtlasCore

@MainActor
@Observable
final class ImportCoordinator {
    enum Stage: Equatable {
        case idle
        case working(ImportProgress)
        case failed(String)
        case finished(caseID: String, label: String)
    }

    struct SeriesChoice: Identifiable, Equatable {
        let id: String
        let title: String
        let summary: String
        let sliceCount: Int
        let isGapped: Bool
        let isRecommended: Bool
    }

    struct DuplicateChoice: Equatable {
        let existingLabel: String
    }

    private(set) var stage: Stage = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var summaryNote: String?
    var seriesChoices: [SeriesChoice]?
    var gapWarningSliceCount: Int?
    var duplicateChoice: DuplicateChoice?

    private let environment: AppEnvironment
    private var task: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var scopedURLs: [URL] = []
    private var seriesContinuation: CheckedContinuation<String?, Never>?
    private var gapContinuation: CheckedContinuation<Bool, Never>?
    private var duplicateContinuation: CheckedContinuation<DuplicateResolution, Never>?

    enum DuplicateResolution {
        case skip
        case importCopy
    }

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var isRunning: Bool {
        if case .working = stage { return true }
        return false
    }

    func begin(urls: [URL]) {
        guard !isRunning else { return }
        summaryNote = nil
        stage = .working(ImportProgress(phase: .reading, completed: 0, total: 0))
        elapsed = 0
        startTimer()
        scopedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        task = Task { [weak self] in
            await self?.run(urls: urls)
        }
    }

    func cancel() {
        task?.cancel()
        resumePendingDecisions()
    }

    func dismiss() {
        stage = .idle
        summaryNote = nil
        stopTimer()
    }

    func chooseSeries(id: String?) {
        seriesChoices = nil
        seriesContinuation?.resume(returning: id)
        seriesContinuation = nil
    }

    func resolveGapWarning(proceed: Bool) {
        gapWarningSliceCount = nil
        gapContinuation?.resume(returning: proceed)
        gapContinuation = nil
    }

    func resolveDuplicate(_ resolution: DuplicateResolution) {
        duplicateChoice = nil
        duplicateContinuation?.resume(returning: resolution)
        duplicateContinuation = nil
    }

    private func resumePendingDecisions() {
        seriesChoices = nil
        gapWarningSliceCount = nil
        duplicateChoice = nil
        seriesContinuation?.resume(returning: nil)
        seriesContinuation = nil
        gapContinuation?.resume(returning: false)
        gapContinuation = nil
        duplicateContinuation?.resume(returning: .skip)
        duplicateContinuation = nil
    }

    private func run(urls: [URL]) async {
        defer {
            for url in scopedURLs { url.stopAccessingSecurityScopedResource() }
            scopedURLs = []
            stopTimer()
        }
        do {
            if let received = try await adoptPackages(in: urls) {
                if received.count > 1 {
                    summaryNote = "\(received.count) cases received with their moments and notes"
                } else if received.merged {
                    summaryNote = "Case notes and moments updated from the shared copy"
                } else {
                    summaryNote = "Case received with its moments and notes"
                }
                await environment.adopt(caseID: received.record.id)
                stage = .finished(caseID: received.record.id, label: received.record.label)
                return
            }
            let result = try await scan(urls: urls)
            try Task.checkCancellation()
            let candidate = try await selectCandidate(from: result)
            try Task.checkCancellation()

            if candidate.isGapped {
                let proceed = await withCheckedContinuation { continuation in
                    gapContinuation = continuation
                    gapWarningSliceCount = candidate.slices.count
                }
                guard proceed else { throw ImportError.cancelled }
            }

            if let existing = await environment.store.record(seriesUIDHash: candidate.seriesUIDHash) {
                let resolution = await withCheckedContinuation { continuation in
                    duplicateContinuation = continuation
                    duplicateChoice = DuplicateChoice(existingLabel: existing.label)
                }
                if resolution == .skip {
                    stage = .finished(caseID: existing.id, label: existing.label)
                    summaryNote = "Already imported. Opening the existing scan."
                    return
                }
            }

            let record = try await convert(candidate: candidate)
            summaryNote = importSummary(result: result, candidate: candidate)
            await environment.adopt(caseID: record.id)
            stage = .finished(caseID: record.id, label: record.label)
        } catch {
            if Task.isCancelled || error is CancellationError {
                stage = .failed(ImportError.cancelled.userMessage)
            } else {
                stage = .failed(AppEnvironment.message(for: error))
            }
        }
    }

    private func adoptPackages(in urls: [URL]) async throws -> (record: CaseRecord, merged: Bool, count: Int)? {
        let manager = FileManager.default
        var packageDirectories: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                if CaseStore.isCasePackage(url) {
                    packageDirectories.append(url)
                    continue
                }
                let enumerator = manager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
                while let item = enumerator?.nextObject() as? URL {
                    if item.lastPathComponent == BundleLayout.manifestName {
                        let parent = item.deletingLastPathComponent()
                        if CaseStore.isCasePackage(parent) {
                            packageDirectories.append(parent)
                        }
                    }
                }
            }
        }
        guard !packageDirectories.isEmpty else { return nil }
        let store = environment.store
        var unique: [URL] = []
        for directory in packageDirectories where !unique.contains(directory) {
            unique.append(directory)
        }
        var lastResult: (record: CaseRecord, merged: Bool)?
        for directory in unique {
            lastResult = try await store.adoptPackage(at: directory)
        }
        guard let lastResult else { return nil }
        return (lastResult.record, lastResult.merged, unique.count)
    }

    private func scan(urls: [URL]) async throws -> SeriesScanResult {
        let relay = makeRelay()
        return try await Task.detached(priority: .userInitiated) {
            try ImportPipeline.scan(urls: urls, progress: relay)
        }.value
    }

    private func convert(candidate: SeriesCandidate) async throws -> CaseRecord {
        let relay = makeRelay()
        let store = environment.store
        let label = candidate.suggestedLabel
        return try await Task.detached(priority: .userInitiated) {
            try await store.importSeries(candidate: candidate, label: label, progress: relay)
        }.value
    }

    private func selectCandidate(from result: SeriesScanResult) async throws -> SeriesCandidate {
        if result.candidates.count == 1, let only = result.candidates.first { return only }
        let recommended = result.preferredCandidate
        let choices = result.candidates.map { candidate in
            SeriesChoice(
                id: candidate.id,
                title: candidate.displayTitle,
                summary: candidate.displaySummary,
                sliceCount: candidate.slices.count,
                isGapped: candidate.isGapped,
                isRecommended: candidate.id == recommended?.id
            )
        }
        let chosenID = await withCheckedContinuation { continuation in
            seriesContinuation = continuation
            seriesChoices = choices
        }
        guard let chosenID, let candidate = result.candidates.first(where: { $0.id == chosenID }) else {
            throw ImportError.cancelled
        }
        return candidate
    }

    private func makeRelay() -> @Sendable (ImportProgress) -> Void {
        { progress in
            guard progress.completed % 8 == 0 || progress.completed == progress.total else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.stage = .working(progress)
            }
        }
    }

    private func importSummary(result: SeriesScanResult, candidate: SeriesCandidate) -> String {
        var parts = ["\(candidate.slices.count) slices imported"]
        if result.unreadableCount > 0 { parts.append("\(result.unreadableCount) unreadable") }
        if result.ignoredCount > 0 { parts.append("\(result.ignoredCount) not DICOM") }
        if candidate.isGapped { parts.append("gaps detected") }
        return parts.joined(separator: " · ")
    }

    private func startTimer() {
        stopTimer()
        let start = Date()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                await MainActor.run { [weak self] in
                    self?.elapsed = Date().timeIntervalSince(start)
                }
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }
}
