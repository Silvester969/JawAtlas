import Foundation

public enum IncomingScanError: Error, Equatable, Sendable {
    case nothingToStage
    case sourceMissing(String)
    case stagingFailed(String)

    public var userMessage: String {
        switch self {
        case .nothingToStage:
            return "Nothing usable was received."
        case .sourceMissing:
            return "The received file could not be found."
        case .stagingFailed:
            return "The received files could not be prepared for import."
        }
    }
}

public enum IncomingScanStager {
    public static func stage(urls: [URL], into stagingDirectory: URL) throws -> [URL] {
        guard !urls.isEmpty else { throw IncomingScanError.nothingToStage }
        let manager = FileManager.default
        let sessionDirectory = stagingDirectory
            .appendingPathComponent("incoming-" + UUID().uuidString, isDirectory: true)
        do {
            try manager.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        } catch {
            throw IncomingScanError.stagingFailed(sessionDirectory.lastPathComponent)
        }
        var stagedFileCount = 0
        do {
            for url in urls {
                stagedFileCount += try stage(url, into: sessionDirectory, manager: manager)
            }
        } catch {
            try? manager.removeItem(at: sessionDirectory)
            throw error
        }
        guard stagedFileCount > 0 else {
            try? manager.removeItem(at: sessionDirectory)
            throw IncomingScanError.nothingToStage
        }
        return [sessionDirectory]
    }

    private static func stage(_ url: URL, into sessionDirectory: URL, manager: FileManager) throws -> Int {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped { url.stopAccessingSecurityScopedResource() }
        }
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw IncomingScanError.sourceMissing(url.lastPathComponent)
        }
        if isDirectory.boolValue {
            let target = uniqueTarget(named: url.lastPathComponent, in: sessionDirectory, manager: manager)
            do {
                try manager.copyItem(at: url, to: target)
            } catch {
                throw IncomingScanError.stagingFailed(url.lastPathComponent)
            }
            return 1
        }
        if isZipArchive(url) {
            let baseName = url.deletingPathExtension().lastPathComponent
            let folderName = baseName.isEmpty ? "archive" : baseName
            let target = uniqueTarget(named: folderName, in: sessionDirectory, manager: manager)
            let archive = try ZipArchive(fileAt: url)
            let extracted = try archive.extractAll(to: target)
            return extracted.count
        }
        let target = uniqueTarget(named: url.lastPathComponent, in: sessionDirectory, manager: manager)
        do {
            try manager.copyItem(at: url, to: target)
        } catch {
            throw IncomingScanError.stagingFailed(url.lastPathComponent)
        }
        return 1
    }

    private static func isZipArchive(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "zip" { return true }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4), head.count == 4 else {
            return false
        }
        return head.elementsEqual([0x50, 0x4B, 0x03, 0x04])
    }

    private static func uniqueTarget(named name: String, in directory: URL, manager: FileManager) -> URL {
        var candidate = directory.appendingPathComponent(name)
        var attempt = 1
        while manager.fileExists(atPath: candidate.path) {
            attempt += 1
            candidate = directory.appendingPathComponent("\(attempt)-" + name)
        }
        return candidate
    }
}
