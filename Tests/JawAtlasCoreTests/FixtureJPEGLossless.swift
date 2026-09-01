import Foundation
@testable import JawAtlasCore

enum FixtureJPEGLossless {
    private static let counts = [0, 1, 5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0]
    private static let symbols: [UInt8] = Array(0...16)

    private static func codeTable() -> [UInt8: (code: UInt16, length: Int)] {
        var table: [UInt8: (UInt16, Int)] = [:]
        var code: UInt16 = 0
        var symbolIndex = 0
        for lengthMinusOne in 0..<16 {
            for _ in 0..<counts[lengthMinusOne] {
                table[symbols[symbolIndex]] = (code, lengthMinusOne + 1)
                symbolIndex += 1
                code += 1
            }
            code <<= 1
        }
        return table
    }

    private struct BitWriter {
        var bytes = Data()
        var current: UInt8 = 0
        var filled = 0

        mutating func append(_ value: Int, bits: Int) {
            guard bits > 0 else { return }
            for shift in stride(from: bits - 1, through: 0, by: -1) {
                current = (current << 1) | UInt8((value >> shift) & 1)
                filled += 1
                if filled == 8 {
                    bytes.append(current)
                    if current == 0xFF { bytes.append(0x00) }
                    current = 0
                    filled = 0
                }
            }
        }

        mutating func finish() {
            while filled != 0 { append(1, bits: 1) }
        }
    }

    static func encode(pixels: [UInt16], width: Int, height: Int, precision: Int) -> Data {
        let table = codeTable()
        var writer = BitWriter()
        let mask = precision == 16 ? 0xFFFF : (1 << precision) - 1
        let initial = 1 << (precision - 1)

        for row in 0..<height {
            for column in 0..<width {
                let value = Int(pixels[row * width + column])
                let prediction: Int
                if row == 0 && column == 0 {
                    prediction = initial
                } else if row == 0 {
                    prediction = Int(pixels[row * width + column - 1])
                } else if column == 0 {
                    prediction = Int(pixels[(row - 1) * width + column])
                } else {
                    prediction = Int(pixels[row * width + column - 1])
                }
                var difference = (value - prediction) & mask
                if difference > mask / 2 { difference -= mask + 1 }
                let category = difference == 0 ? 0 : (32 - abs(Int32(difference)).leadingZeroBitCount)
                let huffman = table[UInt8(category)] ?? (0, 0)
                writer.append(Int(huffman.code), bits: huffman.length)
                if category > 0 && category < 16 {
                    let raw = difference < 0 ? difference + (1 << category) - 1 : difference
                    writer.append(raw, bits: category)
                }
            }
        }
        writer.finish()

        var jpeg = Data([0xFF, 0xD8])
        var sof = Data([0xFF, 0xC3])
        sof.append(bigEndian16(11))
        sof.append(UInt8(precision))
        sof.append(bigEndian16(height))
        sof.append(bigEndian16(width))
        sof.append(contentsOf: [1, 1, 0x11, 0])
        jpeg.append(sof)

        var dht = Data([0xFF, 0xC4])
        dht.append(bigEndian16(2 + 1 + 16 + symbols.count))
        dht.append(0x00)
        dht.append(contentsOf: counts.map { UInt8($0) })
        dht.append(contentsOf: symbols)
        jpeg.append(dht)

        var sos = Data([0xFF, 0xDA])
        sos.append(bigEndian16(8))
        sos.append(contentsOf: [1, 1, 0x00, 1, 0, 0])
        jpeg.append(sos)

        jpeg.append(writer.bytes)
        jpeg.append(contentsOf: [0xFF, 0xD9])
        return jpeg
    }

    private static func bigEndian16(_ value: Int) -> Data {
        Data([UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }
}
