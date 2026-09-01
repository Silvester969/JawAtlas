import Foundation

public actor CaseStore {
    public let root: URL
    public let casesDirectory: URL
    public let stagingDirectory: URL
    private var cache: [CaseRecord] = []

    public init(root: URL) {
        self.root = root
        self.casesDirectory = root.appendingPathComponent("Cases", isDirectory: true)
        self.stagingDirectory = root.appendingPathComponent("Staging", isDirectory: true)
    }

    public static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("JawAtlas", isDirectory: true)
    }

    public func prepare() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: casesDirectory, withIntermediateDirectories: true)
        try manager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        sweep()
    }

    public func sweep() {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(
            at: casesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for entry in entries {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDirectory else {
                try? manager.removeItem(at: entry)
                continue
            }
            let residue = (try? manager.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)) ?? []
            for file in residue where file.lastPathComponent.hasSuffix(BundleLayout.partialSuffix)
                || file.lastPathComponent.hasSuffix(BundleLayout.temporarySuffix) {
                try? manager.removeItem(at: file)
            }
            if (try? IntegrityVerifier.loadManifest(in: entry)) == nil {
                try? manager.removeItem(at: entry)
            }
        }
        clearStaging()
    }

    public func clearStaging() {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(at: stagingDirectory, includingPropertiesForKeys: nil) else { return }
        for entry in entries { try? manager.removeItem(at: entry) }
    }

    @discardableResult
    public func reload() -> [CaseRecord] {
        let manager = FileManager.default
        var records: [CaseRecord] = []
        let entries = (try? manager.contentsOfDirectory(
            at: casesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for entry in entries {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDirectory else { continue }
            guard let manifest = try? IntegrityVerifier.loadManifest(in: entry) else { continue }
            var status = CaseRecord.Status.ready
            do {
                try IntegrityVerifier.quickCheck(manifest: manifest, directory: entry)
            } catch let error as VolumeError {
                status = .unreadable(error.userMessage)
            } catch {
                status = .unreadable(VolumeError.bundleCorrupt("unknown").userMessage)
            }
            records.append(
                CaseRecord(
                    id: manifest.caseID,
                    label: manifest.label,
                    importedAt: manifest.importedAt,
                    dimensions: manifest.dimensions,
                    spacingMM: manifest.spacingMM,
                    isGapped: manifest.isGapped,
                    seriesUIDHash: manifest.seriesUIDHash,
                    patientTag: manifest.patientTag,
                    volumeByteCount: manifest.volumeByteCount,
                    storageByteCount: CaseStore.directorySize(at: entry),
                    directory: entry,
                    status: status
                )
            )
        }
        records.sort { $0.importedAt > $1.importedAt }
        cache = records
        return records
    }

    public func records() -> [CaseRecord] { cache }

    public func record(id: String) -> CaseRecord? { cache.first { $0.id == id } }

    public func record(seriesUIDHash hash: String) -> CaseRecord? {
        cache.first { $0.seriesUIDHash == hash }
    }

    public func delete(id: String) {
        guard let record = cache.first(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: record.directory)
        cache.removeAll { $0.id == id }
    }

    public func setPatientTag(id: String, to tag: String?) throws {
        guard let record = cache.first(where: { $0.id == id }) else { throw VolumeError.caseMissing(id) }
        var manifest = try IntegrityVerifier.loadManifest(in: record.directory)
        let trimmed = tag?.trimmingCharacters(in: .whitespacesAndNewlines)
        manifest.patientTag = (trimmed?.isEmpty ?? true) ? nil : trimmed
        let data = try BundleManifest.encoder().encode(manifest)
        try data.write(to: BundleLayout.manifestURL(in: record.directory), options: [.atomic])
        if let index = cache.firstIndex(where: { $0.id == id }) {
            cache[index].patientTag = manifest.patientTag
        }
    }

    public static func isCasePackage(_ directory: URL) -> Bool {
        (try? IntegrityVerifier.loadManifest(in: directory)) != nil
    }

    public func adoptPackage(at packageDirectory: URL) throws -> (record: CaseRecord, merged: Bool) {
        let manifest = try IntegrityVerifier.loadManifest(in: packageDirectory)
        try IntegrityVerifier.quickCheck(manifest: manifest, directory: packageDirectory)
        let manager = FileManager.default

        if let existing = cache.first(where: { $0.seriesUIDHash == manifest.seriesUIDHash }) {
            let incomingStory = BundleLayout.storyURL(in: packageDirectory)
            if manager.fileExists(atPath: incomingStory.path) {
                let target = BundleLayout.storyURL(in: existing.directory)
                try? manager.removeItem(at: target)
                try manager.copyItem(at: incomingStory, to: target)
            }
            var existingManifest = try IntegrityVerifier.loadManifest(in: existing.directory)
            existingManifest.label = manifest.label
            existingManifest.patientTag = manifest.patientTag
            let data = try BundleManifest.encoder().encode(existingManifest)
            try data.write(to: BundleLayout.manifestURL(in: existing.directory), options: [.atomic])
            reload()
            guard let updated = cache.first(where: { $0.id == existing.id }) else {
                throw VolumeError.caseMissing(existing.id)
            }
            return (updated, true)
        }

        var identifier = manifest.caseID
        var destination = casesDirectory.appendingPathComponent(identifier, isDirectory: true)
        if manager.fileExists(atPath: destination.path) {
            identifier = UUID().uuidString
            destination = casesDirectory.appendingPathComponent(identifier, isDirectory: true)
        }
        try manager.copyItem(at: packageDirectory, to: destination)
        if identifier != manifest.caseID {
            var adjusted = manifest
            adjusted.caseID = identifier
            let data = try BundleManifest.encoder().encode(adjusted)
            try data.write(to: BundleLayout.manifestURL(in: destination), options: [.atomic])
        }
        BundleConverter.applyFileProtection(in: destination)
        reload()
        guard let adopted = cache.first(where: { $0.id == identifier }) else {
            throw VolumeError.bundleCorrupt("adoption failed")
        }
        return (adopted, false)
    }

    public func exportPackage(id: String, to destination: URL) throws {
        guard let record = cache.first(where: { $0.id == id }) else { throw VolumeError.caseMissing(id) }
        try ZipWriter.writeArchive(of: record.directory, to: destination)
    }

    public func rename(id: String, to label: String) throws {
        guard let record = cache.first(where: { $0.id == id }) else { throw VolumeError.caseMissing(id) }
        var manifest = try IntegrityVerifier.loadManifest(in: record.directory)
        manifest.label = label
        let data = try BundleManifest.encoder().encode(manifest)
        try data.write(to: BundleLayout.manifestURL(in: record.directory), options: [.atomic])
        if let index = cache.firstIndex(where: { $0.id == id }) {
            cache[index].label = label
        }
    }

    public func totalStorageBytes() -> Int64 {
        cache.reduce(0) { $0 + $1.storageByteCount }
    }

    public func makeHandle(forCaseID id: String) throws -> VolumeHandle {
        let directory: URL
        if let record = cache.first(where: { $0.id == id }) {
            directory = record.directory
        } else {
            directory = casesDirectory.appendingPathComponent(id, isDirectory: true)
        }
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw VolumeError.caseMissing(id)
        }
        let manifest = try IntegrityVerifier.loadManifest(in: directory)
        try IntegrityVerifier.quickCheck(manifest: manifest, directory: directory)
        let mapping = try VolumeMapping(url: BundleLayout.volumeURL(in: directory))
        return VolumeHandle(caseID: id, manifest: manifest, mapping: mapping)
    }

    public func importSeries(
        candidate: SeriesCandidate,
        label: String,
        progress: @Sendable (ImportProgress) -> Void = { _ in }
    ) throws -> CaseRecord {
        let record = try BundleConverter.convert(
            candidate: candidate,
            label: label,
            casesDirectory: casesDirectory,
            progress: progress
        )
        reload()
        return cache.first { $0.id == record.id } ?? record
    }

    public static func directorySize(at url: URL) -> Int64 {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }
}
