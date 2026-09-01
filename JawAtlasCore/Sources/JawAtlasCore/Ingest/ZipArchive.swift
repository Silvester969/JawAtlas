import Foundation
import Compression

public enum ZipArchiveError: Error, Equatable, Sendable {
    case unreadable(String)
    case notZipArchive
    case truncated
    case malformed(String)
    case unsupportedCompressionMethod(UInt16)
    case unsafeEntryPath(String)
    case declaredSizeTooLarge
    case tooManyEntries(Int)
    case decompressionFailed(String)
    case extractionFailed(String)

    public var userMessage: String {
        switch self {
        case .unreadable:
            return "This ZIP archive could not be read from this device."
        case .notZipArchive:
            return "This file is not a ZIP archive."
        case .truncated:
            return "This ZIP archive is incomplete or damaged."
        case .malformed:
            return "This ZIP archive could not be read."
        case .unsupportedCompressionMethod:
            return "This ZIP archive uses a compression format this app cannot open."
        case .unsafeEntryPath:
            return "This ZIP archive contains unsafe file paths and was not opened."
        case .declaredSizeTooLarge:
            return "This ZIP archive is too large to unpack on this device."
        case .tooManyEntries:
            return "This ZIP archive contains too many files."
        case .decompressionFailed:
            return "A file inside this ZIP archive could not be unpacked."
        case .extractionFailed:
            return "Files from this ZIP archive could not be saved."
        }
    }
}

public struct ZipArchive: Sendable {
    public struct Entry: Equatable, Sendable {
        public let name: String
        public let method: UInt16
        public let compressedSize: UInt64
        public let uncompressedSize: UInt64
        public let localHeaderOffset: UInt64
        public let isDirectory: Bool
        public let isSymbolicLink: Bool
    }

    public static let maximumEntryCount = 20000
    public static let maximumExpandedByteCount: UInt64 = 4 << 30

    private static let storedMethod: UInt16 = 0
    private static let deflateMethod: UInt16 = 8
    private static let endOfCentralDirectorySignature: UInt32 = 0x0605_4B50
    private static let zip64LocatorSignature: UInt32 = 0x0706_4B50
    private static let zip64EndOfCentralDirectorySignature: UInt32 = 0x0606_4B50
    private static let centralDirectorySignature: UInt32 = 0x0201_4B50
    private static let localHeaderSignature: UInt32 = 0x0403_4B50
    private static let zip64ExtraFieldID: UInt16 = 0x0001

    public let entries: [Entry]
    private let data: Data

    public init(fileAt url: URL) throws {
        let contents: Data
        do {
            contents = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw ZipArchiveError.unreadable(url.lastPathComponent)
        }
        try self.init(data: contents)
    }

    public init(data: Data) throws {
        self.data = data
        let reader = ZipByteWindow(data: data)
        let directory = try ZipArchive.locateCentralDirectory(reader: reader)
        self.entries = try ZipArchive.parseCentralDirectory(reader: reader, directory: directory)
    }

    private struct CentralDirectoryLocation {
        let entryCount: UInt64
        let offset: UInt64
    }

    private static func locateCentralDirectory(reader: ZipByteWindow) throws -> CentralDirectoryLocation {
        guard reader.count >= 22 else { throw ZipArchiveError.truncated }
        let lowestOffset = max(0, reader.count - 22 - 65535)
        var eocdOffset = -1
        var cursor = reader.count - 22
        while cursor >= lowestOffset {
            if try reader.u32(cursor) == endOfCentralDirectorySignature {
                eocdOffset = cursor
                break
            }
            cursor -= 1
        }
        guard eocdOffset >= 0 else { throw ZipArchiveError.notZipArchive }

        var entryCount = UInt64(try reader.u16(eocdOffset + 10))
        var directoryOffset = UInt64(try reader.u32(eocdOffset + 16))
        let directorySize = UInt64(try reader.u32(eocdOffset + 12))

        if entryCount == 0xFFFF || directoryOffset == 0xFFFF_FFFF || directorySize == 0xFFFF_FFFF {
            let locatorOffset = eocdOffset - 20
            guard locatorOffset >= 0, try reader.u32(locatorOffset) == zip64LocatorSignature else {
                throw ZipArchiveError.malformed("zip64 locator missing")
            }
            let recordOffsetValue = try reader.u64(locatorOffset + 8)
            guard let recordOffset = Int(exactly: recordOffsetValue), recordOffset >= 0,
                  recordOffset <= reader.count - 56 else {
                throw ZipArchiveError.truncated
            }
            guard try reader.u32(recordOffset) == zip64EndOfCentralDirectorySignature else {
                throw ZipArchiveError.malformed("zip64 record missing")
            }
            entryCount = try reader.u64(recordOffset + 32)
            directoryOffset = try reader.u64(recordOffset + 48)
        }
        guard entryCount <= UInt64(maximumEntryCount) else {
            throw ZipArchiveError.tooManyEntries(Int(clamping: entryCount))
        }
        return CentralDirectoryLocation(entryCount: entryCount, offset: directoryOffset)
    }

    private static func parseCentralDirectory(
        reader: ZipByteWindow,
        directory: CentralDirectoryLocation
    ) throws -> [Entry] {
        guard let startOffset = Int(exactly: directory.offset), startOffset >= 0,
              startOffset <= reader.count else {
            throw ZipArchiveError.truncated
        }
        var offset = startOffset
        var parsed: [Entry] = []
        parsed.reserveCapacity(Int(directory.entryCount))
        var totalDeclaredBytes: UInt64 = 0

        for _ in 0..<directory.entryCount {
            guard try reader.u32(offset) == centralDirectorySignature else {
                throw ZipArchiveError.malformed("central directory entry")
            }
            let versionMadeBy = try reader.u16(offset + 4)
            let method = try reader.u16(offset + 10)
            var compressedSize = UInt64(try reader.u32(offset + 20))
            var uncompressedSize = UInt64(try reader.u32(offset + 24))
            let nameLength = Int(try reader.u16(offset + 28))
            let extraLength = Int(try reader.u16(offset + 30))
            let commentLength = Int(try reader.u16(offset + 32))
            let externalAttributes = try reader.u32(offset + 38)
            var localHeaderOffset = UInt64(try reader.u32(offset + 42))

            let nameData = try reader.bytes(offset + 46, nameLength)
            let name = String(decoding: nameData, as: UTF8.self)

            var fieldOffset = offset + 46 + nameLength
            let extraEnd = fieldOffset + extraLength
            while fieldOffset + 4 <= extraEnd {
                let fieldID = try reader.u16(fieldOffset)
                let fieldSize = Int(try reader.u16(fieldOffset + 2))
                var valueOffset = fieldOffset + 4
                let fieldEnd = valueOffset + fieldSize
                guard fieldEnd <= extraEnd else { throw ZipArchiveError.malformed("extra field") }
                if fieldID == zip64ExtraFieldID {
                    if uncompressedSize == 0xFFFF_FFFF {
                        guard valueOffset + 8 <= fieldEnd else { throw ZipArchiveError.malformed("zip64 sizes") }
                        uncompressedSize = try reader.u64(valueOffset)
                        valueOffset += 8
                    }
                    if compressedSize == 0xFFFF_FFFF {
                        guard valueOffset + 8 <= fieldEnd else { throw ZipArchiveError.malformed("zip64 sizes") }
                        compressedSize = try reader.u64(valueOffset)
                        valueOffset += 8
                    }
                    if localHeaderOffset == 0xFFFF_FFFF {
                        guard valueOffset + 8 <= fieldEnd else { throw ZipArchiveError.malformed("zip64 offset") }
                        localHeaderOffset = try reader.u64(valueOffset)
                        valueOffset += 8
                    }
                }
                fieldOffset = fieldEnd
            }

            let madeOnUnix = (versionMadeBy >> 8) == 3
            let unixMode = UInt16(truncatingIfNeeded: externalAttributes >> 16)
            let isSymbolicLink = madeOnUnix && (unixMode & 0xF000) == 0xA000
            let isDirectory = name.hasSuffix("/") || (madeOnUnix && (unixMode & 0xF000) == 0x4000)

            if !isDirectory && !isSymbolicLink {
                let (sum, overflow) = totalDeclaredBytes.addingReportingOverflow(uncompressedSize)
                guard !overflow, sum <= maximumExpandedByteCount else {
                    throw ZipArchiveError.declaredSizeTooLarge
                }
                totalDeclaredBytes = sum
            }

            parsed.append(
                Entry(
                    name: name,
                    method: method,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localHeaderOffset,
                    isDirectory: isDirectory,
                    isSymbolicLink: isSymbolicLink
                )
            )
            offset = extraEnd + commentLength
        }
        return parsed
    }

    public func extractData(of entry: Entry) throws -> Data {
        guard !entry.isDirectory, !entry.isSymbolicLink else { return Data() }
        guard entry.method == ZipArchive.storedMethod || entry.method == ZipArchive.deflateMethod else {
            throw ZipArchiveError.unsupportedCompressionMethod(entry.method)
        }
        let reader = ZipByteWindow(data: data)
        guard let headerOffset = Int(exactly: entry.localHeaderOffset), headerOffset >= 0,
              headerOffset <= reader.count - 30 else {
            throw ZipArchiveError.truncated
        }
        guard try reader.u32(headerOffset) == ZipArchive.localHeaderSignature else {
            throw ZipArchiveError.malformed("local header")
        }
        let nameLength = Int(try reader.u16(headerOffset + 26))
        let extraLength = Int(try reader.u16(headerOffset + 28))
        guard let compressedCount = Int(exactly: entry.compressedSize),
              let expectedCount = Int(exactly: entry.uncompressedSize) else {
            throw ZipArchiveError.declaredSizeTooLarge
        }
        let payloadOffset = headerOffset + 30 + nameLength + extraLength
        let payload = try reader.bytes(payloadOffset, compressedCount)
        if entry.method == ZipArchive.storedMethod {
            guard payload.count == expectedCount else {
                throw ZipArchiveError.malformed("stored size mismatch")
            }
            return payload
        }
        return try ZipArchive.inflate(payload, expectedByteCount: expectedCount, entryName: entry.name)
    }

    @discardableResult
    public func extractAll(to destination: URL) throws -> [URL] {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            throw ZipArchiveError.extractionFailed(destination.lastPathComponent)
        }
        var written: [URL] = []
        for entry in entries {
            if entry.isDirectory || entry.isSymbolicLink { continue }
            let components = try ZipArchive.sanitizedPathComponents(of: entry.name)
            guard !components.isEmpty else { continue }
            var target = destination
            for component in components {
                target.appendPathComponent(component)
            }
            let payload = try extractData(of: entry)
            do {
                try manager.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try payload.write(to: target, options: [.atomic])
            } catch {
                throw ZipArchiveError.extractionFailed(entry.name)
            }
            written.append(target)
        }
        return written
    }

    private static func sanitizedPathComponents(of name: String) throws -> [String] {
        guard !name.isEmpty else { return [] }
        guard !name.contains("\u{0}") else { throw ZipArchiveError.unsafeEntryPath(name) }
        let normalized = name.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.hasPrefix("/") else { throw ZipArchiveError.unsafeEntryPath(name) }
        var components: [String] = []
        for piece in normalized.split(separator: "/") {
            if piece == "." { continue }
            guard piece != ".." else { throw ZipArchiveError.unsafeEntryPath(name) }
            components.append(String(piece))
        }
        return components
    }

    private static func inflate(_ compressed: Data, expectedByteCount: Int, entryName: String) throws -> Data {
        guard expectedByteCount > 0 else { return Data() }
        guard !compressed.isEmpty else { throw ZipArchiveError.decompressionFailed(entryName) }
        var output = Data(count: expectedByteCount)
        let writtenCount = output.withUnsafeMutableBytes { destination in
            compressed.withUnsafeBytes { source -> Int in
                guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
                      let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return compression_decode_buffer(
                    destinationBase,
                    expectedByteCount,
                    sourceBase,
                    source.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard writtenCount == expectedByteCount else {
            throw ZipArchiveError.decompressionFailed(entryName)
        }
        return output
    }
}

private struct ZipByteWindow {
    let data: Data

    var count: Int { data.count }

    func u8(_ offset: Int) throws -> UInt8 {
        guard offset >= 0, offset < data.count else { throw ZipArchiveError.truncated }
        return data[data.startIndex + offset]
    }

    func u16(_ offset: Int) throws -> UInt16 {
        let low = try u8(offset)
        let high = try u8(offset + 1)
        return UInt16(low) | (UInt16(high) << 8)
    }

    func u32(_ offset: Int) throws -> UInt32 {
        let low = try u16(offset)
        let high = try u16(offset + 2)
        return UInt32(low) | (UInt32(high) << 16)
    }

    func u64(_ offset: Int) throws -> UInt64 {
        let low = try u32(offset)
        let high = try u32(offset + 4)
        return UInt64(low) | (UInt64(high) << 32)
    }

    func bytes(_ offset: Int, _ length: Int) throws -> Data {
        guard offset >= 0, length >= 0, offset <= data.count, data.count - offset >= length else {
            throw ZipArchiveError.truncated
        }
        let start = data.startIndex + offset
        return data.subdata(in: start..<(start + length))
    }
}
