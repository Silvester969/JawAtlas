import Foundation

public enum RLECodec {
    public static func decodeSixteenBit(fragment: Data, pixelCount: Int) throws -> [UInt16] {
        guard fragment.count >= 64 else { throw DICOMError.malformedValue("RLE header") }
        let segmentCount = Int(readUInt32(fragment, 0))
        guard segmentCount == 2 else { throw DICOMError.unsupportedPixelFormat("RLE segments \(segmentCount)") }
        let highOffset = Int(readUInt32(fragment, 4))
        let lowOffset = Int(readUInt32(fragment, 8))
        guard highOffset >= 64, lowOffset > highOffset, lowOffset <= fragment.count else {
            throw DICOMError.malformedValue("RLE offsets")
        }
        let high = try unpackBits(fragment, from: highOffset, to: lowOffset, expected: pixelCount)
        let low = try unpackBits(fragment, from: lowOffset, to: fragment.count, expected: pixelCount)
        var output = [UInt16](repeating: 0, count: pixelCount)
        for index in 0..<pixelCount {
            output[index] = (UInt16(high[index]) << 8) | UInt16(low[index])
        }
        return output
    }

    static func unpackBits(_ data: Data, from start: Int, to end: Int, expected: Int) throws -> [UInt8] {
        var output = [UInt8]()
        output.reserveCapacity(expected)
        var cursor = start
        let base = data.startIndex
        while cursor < end, output.count < expected {
            let control = Int8(bitPattern: data[base + cursor])
            cursor += 1
            if control >= 0 {
                let runLength = Int(control) + 1
                guard cursor + runLength <= end else { throw DICOMError.truncated }
                for offset in 0..<runLength {
                    output.append(data[base + cursor + offset])
                }
                cursor += runLength
            } else if control != -128 {
                let runLength = 1 - Int(control)
                guard cursor < end else { throw DICOMError.truncated }
                let value = data[base + cursor]
                cursor += 1
                output.append(contentsOf: repeatElement(value, count: runLength))
            }
        }
        guard output.count >= expected else { throw DICOMError.truncated }
        if output.count > expected { output.removeSubrange(expected...) }
        return output
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        let base = data.startIndex + offset
        return UInt32(data[base])
            | (UInt32(data[base + 1]) << 8)
            | (UInt32(data[base + 2]) << 16)
            | (UInt32(data[base + 3]) << 24)
    }

    public static func encodeSixteenBit(_ pixels: [UInt16]) -> Data {
        let high = pixels.map { UInt8($0 >> 8) }
        let low = pixels.map { UInt8($0 & 0xFF) }
        let packedHigh = packBits(high)
        let packedLow = packBits(low)
        var header = Data(count: 64)
        writeUInt32(&header, 0, 2)
        writeUInt32(&header, 4, 64)
        writeUInt32(&header, 8, UInt32(64 + packedHigh.count))
        var output = header
        output.append(packedHigh)
        output.append(packedLow)
        if output.count % 2 == 1 { output.append(0) }
        return output
    }

    static func packBits(_ bytes: [UInt8]) -> Data {
        var output = Data()
        var index = 0
        while index < bytes.count {
            var runLength = 1
            while index + runLength < bytes.count,
                  runLength < 128,
                  bytes[index + runLength] == bytes[index] {
                runLength += 1
            }
            if runLength >= 2 {
                output.append(UInt8(bitPattern: Int8(1 - runLength)))
                output.append(bytes[index])
                index += runLength
            } else {
                var literalLength = 1
                while index + literalLength < bytes.count,
                      literalLength < 128,
                      !(index + literalLength + 1 < bytes.count
                        && bytes[index + literalLength] == bytes[index + literalLength + 1]) {
                    literalLength += 1
                }
                output.append(UInt8(literalLength - 1))
                output.append(contentsOf: bytes[index..<(index + literalLength)])
                index += literalLength
            }
        }
        return output
    }

    private static func writeUInt32(_ data: inout Data, _ offset: Int, _ value: UInt32) {
        data[offset] = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
        data[offset + 2] = UInt8((value >> 16) & 0xFF)
        data[offset + 3] = UInt8((value >> 24) & 0xFF)
    }
}
