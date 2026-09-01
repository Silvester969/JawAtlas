import Foundation

public enum JPEGLossless {
    struct HuffmanTable {
        var lookup: [UInt16: (length: Int, value: UInt8)] = [:]
        var maxLength = 0

        init(counts: [Int], values: [UInt8]) throws {
            var code: UInt16 = 0
            var valueIndex = 0
            for lengthMinusOne in 0..<16 {
                let length = lengthMinusOne + 1
                for _ in 0..<counts[lengthMinusOne] {
                    guard valueIndex < values.count else { throw DICOMError.malformedValue("huffman table") }
                    lookup[(UInt16(length) << 12) | code] = (length, values[valueIndex])
                    valueIndex += 1
                    code += 1
                }
                code <<= 1
                if counts[lengthMinusOne] > 0 { maxLength = length }
            }
        }

        func decode(_ reader: inout BitReader) throws -> UInt8 {
            var code: UInt16 = 0
            for length in 1...16 {
                code = (code << 1) | UInt16(try reader.bit())
                if let hit = lookup[(UInt16(length) << 12) | code] {
                    return hit.value
                }
            }
            throw DICOMError.malformedValue("huffman code")
        }
    }

    struct BitReader {
        let data: Data
        var byteIndex: Int
        var bitIndex = 0
        let end: Int

        init(data: Data, start: Int, end: Int) {
            self.data = data
            self.byteIndex = start
            self.end = end
        }

        mutating func bit() throws -> Int {
            guard byteIndex < end else { throw DICOMError.truncated }
            let base = data.startIndex
            var byte = data[base + byteIndex]
            if byte == 0xFF {
                let nextIndex = byteIndex + 1
                if nextIndex < end, data[base + nextIndex] != 0x00, bitIndex == 0 {
                    throw DICOMError.truncated
                }
            }
            byte = data[base + byteIndex]
            let bit = Int((byte >> (7 - bitIndex)) & 1)
            bitIndex += 1
            if bitIndex == 8 {
                bitIndex = 0
                byteIndex += 1
                if byte == 0xFF {
                    guard byteIndex < end, data[base + byteIndex] == 0x00 else {
                        if byteIndex < end { throw DICOMError.malformedValue("marker in scan") }
                        return bit
                    }
                    byteIndex += 1
                }
            }
            return bit
        }

        mutating func bits(_ count: Int) throws -> Int {
            var value = 0
            for _ in 0..<count {
                value = (value << 1) | (try bit())
            }
            return value
        }
    }

    public static func decode(fragment: Data, expectedWidth: Int, expectedHeight: Int) throws -> [UInt16] {
        let base = fragment.startIndex
        let count = fragment.count
        guard count > 20, fragment[base] == 0xFF, fragment[base + 1] == 0xD8 else {
            throw DICOMError.malformedValue("jpeg signature")
        }

        var precision = 0
        var width = 0
        var height = 0
        var predictor = 1
        var pointTransform = 0
        var table: HuffmanTable?
        var scanStart = -1
        var cursor = 2

        func readUInt16BE(_ offset: Int) throws -> Int {
            guard offset >= 0, offset + 1 < count else { throw DICOMError.truncated }
            return Int(fragment[base + offset]) << 8 | Int(fragment[base + offset + 1])
        }

        func byteAt(_ offset: Int) throws -> UInt8 {
            guard offset >= 0, offset < count else { throw DICOMError.truncated }
            return fragment[base + offset]
        }

        while cursor + 3 < count {
            guard fragment[base + cursor] == 0xFF else { throw DICOMError.malformedValue("marker") }
            let marker = fragment[base + cursor + 1]
            if marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD7) {
                cursor += 2
                continue
            }
            let segmentLength = try readUInt16BE(cursor + 2)
            guard segmentLength >= 2, cursor + 2 + segmentLength <= count else { throw DICOMError.truncated }
            let payload = cursor + 4

            switch marker {
            case 0xC3:
                precision = Int(try byteAt(payload))
                height = try readUInt16BE(payload + 1)
                width = try readUInt16BE(payload + 3)
                let components = Int(try byteAt(payload + 5))
                guard components == 1 else { throw DICOMError.unsupportedPixelFormat("jpeg components \(components)") }
            case 0xC0, 0xC1, 0xC2, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF:
                throw DICOMError.unsupportedPixelFormat("jpeg process \(String(format: "%02X", marker))")
            case 0xC4:
                var tableCursor = payload
                let tableEnd = cursor + 2 + segmentLength
                while tableCursor < tableEnd {
                    guard tableCursor + 17 <= tableEnd, tableEnd <= count else { throw DICOMError.truncated }
                    var counts = [Int](repeating: 0, count: 16)
                    var total = 0
                    for index in 0..<16 {
                        counts[index] = Int(try byteAt(tableCursor + 1 + index))
                        total += counts[index]
                    }
                    guard tableCursor + 17 + total <= tableEnd, total <= 17 * 16 else { throw DICOMError.truncated }
                    let values = try (0..<total).map { try byteAt(tableCursor + 17 + $0) }
                    table = try HuffmanTable(counts: counts, values: values)
                    tableCursor += 17 + total
                }
            case 0xDA:
                let componentCount = Int(try byteAt(payload))
                guard componentCount == 1 else { throw DICOMError.unsupportedPixelFormat("jpeg scan components") }
                predictor = Int(try byteAt(payload + 1 + componentCount * 2))
                pointTransform = Int(try byteAt(payload + 3 + componentCount * 2)) & 0x0F
                scanStart = cursor + 2 + segmentLength
            case 0xD9:
                cursor = count
            default:
                break
            }

            if scanStart >= 0 { break }
            cursor += 2 + segmentLength
        }

        guard let huffman = table, scanStart > 0,
              width == expectedWidth, height == expectedHeight,
              precision >= 2, precision <= 16,
              predictor >= 1, predictor <= 7 else {
            throw DICOMError.malformedValue("jpeg structure")
        }

        var reader = BitReader(data: fragment, start: scanStart, end: count)
        var output = [UInt16](repeating: 0, count: width * height)
        let defaultPrediction = 1 << (precision - 1 - pointTransform)
        let mask = precision == 16 ? 0xFFFF : (1 << precision) - 1

        for row in 0..<height {
            for column in 0..<width {
                let category = Int(try huffman.decode(&reader))
                guard category <= 16 else { throw DICOMError.malformedValue("jpeg category") }
                var difference = 0
                if category == 16 {
                    difference = 32768
                } else if category > 0 {
                    let raw = try reader.bits(category)
                    if raw < (1 << (category - 1)) {
                        difference = raw - (1 << category) + 1
                    } else {
                        difference = raw
                    }
                }

                let left = column > 0 ? Int(output[row * width + column - 1]) : 0
                let above = row > 0 ? Int(output[(row - 1) * width + column]) : 0
                let aboveLeft = (row > 0 && column > 0) ? Int(output[(row - 1) * width + column - 1]) : 0

                let prediction: Int
                if row == 0 && column == 0 {
                    prediction = defaultPrediction
                } else if row == 0 {
                    prediction = left
                } else if column == 0 {
                    prediction = above
                } else {
                    switch predictor {
                    case 1: prediction = left
                    case 2: prediction = above
                    case 3: prediction = aboveLeft
                    case 4: prediction = left + above - aboveLeft
                    case 5: prediction = left + ((above - aboveLeft) >> 1)
                    case 6: prediction = above + ((left - aboveLeft) >> 1)
                    default: prediction = (left + above) >> 1
                    }
                }
                output[row * width + column] = UInt16((prediction + difference) & mask)
            }
        }
        return output
    }
}
