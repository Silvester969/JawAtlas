import Foundation

public enum ZipWriter {
    private static let crcTable: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (value >> 1) ^ 0xEDB88320 : value >> 1
            }
            return value
        }
    }()

    public static func crc32(of data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { raw in
            for byte in raw {
                crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFFFFFF
    }

    private struct Entry {
        var name: String
        var crc: UInt32
        var size: UInt32
        var offset: UInt32
    }

    public static func writeArchive(of directory: URL, to destination: URL) throws {
        let manager = FileManager.default
        let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        manager.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        var entries: [Entry] = []
        var offset: UInt32 = 0

        for file in files {
            let data = try Data(contentsOf: file, options: [.mappedIfSafe])
            guard data.count < 0xFFFF_0000 else { throw ImportError.writeFailed("file too large to package") }
            let name = file.lastPathComponent
            let nameBytes = Data(name.utf8)
            let crc = crc32(of: data)
            let size = UInt32(data.count)

            var header = Data()
            header.append(uint32: 0x04034B50)
            header.append(uint16: 20)
            header.append(uint16: 0)
            header.append(uint16: 0)
            header.append(uint16: 0x548C)
            header.append(uint16: 0x5B15)
            header.append(uint32: crc)
            header.append(uint32: size)
            header.append(uint32: size)
            header.append(uint16: UInt16(nameBytes.count))
            header.append(uint16: 0)
            header.append(nameBytes)

            try output.write(contentsOf: header)
            try output.write(contentsOf: data)
            entries.append(Entry(name: name, crc: crc, size: size, offset: offset))
            offset += UInt32(header.count) + size
        }

        let centralStart = offset
        var centralSize: UInt32 = 0
        for entry in entries {
            let nameBytes = Data(entry.name.utf8)
            var record = Data()
            record.append(uint32: 0x02014B50)
            record.append(uint16: 20)
            record.append(uint16: 20)
            record.append(uint16: 0)
            record.append(uint16: 0)
            record.append(uint16: 0x548C)
            record.append(uint16: 0x5B15)
            record.append(uint32: entry.crc)
            record.append(uint32: entry.size)
            record.append(uint32: entry.size)
            record.append(uint16: UInt16(nameBytes.count))
            record.append(uint16: 0)
            record.append(uint16: 0)
            record.append(uint16: 0)
            record.append(uint16: 0)
            record.append(uint32: 0)
            record.append(uint32: entry.offset)
            record.append(nameBytes)
            try output.write(contentsOf: record)
            centralSize += UInt32(record.count)
        }

        var end = Data()
        end.append(uint32: 0x06054B50)
        end.append(uint16: 0)
        end.append(uint16: 0)
        end.append(uint16: UInt16(entries.count))
        end.append(uint16: UInt16(entries.count))
        end.append(uint32: centralSize)
        end.append(uint32: centralStart)
        end.append(uint16: 0)
        try output.write(contentsOf: end)
        try output.synchronize()
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func append(uint32 value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
