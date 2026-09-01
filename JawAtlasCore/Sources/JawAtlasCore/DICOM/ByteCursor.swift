import Foundation

public struct ByteCursor {
    public let bytes: UnsafeRawBufferPointer
    public private(set) var offset: Int

    public init(_ bytes: UnsafeRawBufferPointer, offset: Int = 0) {
        self.bytes = bytes
        self.offset = offset
    }

    public var count: Int { bytes.count }
    public var remaining: Int { max(0, bytes.count - offset) }

    public mutating func seek(to newOffset: Int) throws {
        guard newOffset >= 0, newOffset <= bytes.count else { throw DICOMError.truncated }
        offset = newOffset
    }

    public mutating func skip(_ length: Int) throws {
        guard length >= 0 else { throw DICOMError.truncated }
        let next = offset.addingReportingOverflow(length)
        guard !next.overflow, next.partialValue <= bytes.count else { throw DICOMError.truncated }
        offset = next.partialValue
    }

    public mutating func readUInt16() throws -> UInt16 {
        guard remaining >= 2 else { throw DICOMError.truncated }
        let low = UInt16(bytes[offset])
        let high = UInt16(bytes[offset + 1])
        offset += 2
        return low | (high << 8)
    }

    public mutating func readUInt32() throws -> UInt32 {
        guard remaining >= 4 else { throw DICOMError.truncated }
        var value: UInt32 = 0
        for index in 0..<4 {
            value |= UInt32(bytes[offset + index]) << (8 * UInt32(index))
        }
        offset += 4
        return value
    }

    public mutating func readBytes(_ length: Int) throws -> UnsafeRawBufferPointer {
        guard length >= 0, remaining >= length else { throw DICOMError.truncated }
        let slice = UnsafeRawBufferPointer(rebasing: bytes[offset..<(offset + length)])
        offset += length
        return slice
    }

    public func matches(_ ascii: String, at position: Int) -> Bool {
        let expected = Array(ascii.utf8)
        guard position >= 0, position + expected.count <= bytes.count else { return false }
        for (index, byte) in expected.enumerated() where bytes[position + index] != byte {
            return false
        }
        return true
    }
}

public enum ASCIIValue {
    public static func string(_ raw: UnsafeRawBufferPointer) -> String {
        var scalars = [UInt8]()
        scalars.reserveCapacity(raw.count)
        for byte in raw where byte != 0x00 {
            scalars.append(byte)
        }
        let text = String(decoding: scalars, as: UTF8.self)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func decimals(_ raw: UnsafeRawBufferPointer) -> [Double] {
        string(raw)
            .split(separator: "\\", omittingEmptySubsequences: false)
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }
}
