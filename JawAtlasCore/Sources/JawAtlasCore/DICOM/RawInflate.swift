import Foundation
import Compression

public enum RawInflate {
    public static func inflate(_ compressed: Data, sizeHint: Int) throws -> Data {
        guard !compressed.isEmpty else { return Data() }
        var capacity = max(sizeHint, compressed.count * 4, 1 << 16)
        let ceiling = 1 << 31
        while capacity <= ceiling {
            var output = Data(count: capacity)
            let written = output.withUnsafeMutableBytes { outRaw -> Int in
                compressed.withUnsafeBytes { inRaw -> Int in
                    guard let outBase = outRaw.baseAddress, let inBase = inRaw.baseAddress else { return 0 }
                    return compression_decode_buffer(
                        outBase.assumingMemoryBound(to: UInt8.self),
                        capacity,
                        inBase.assumingMemoryBound(to: UInt8.self),
                        compressed.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }
            if written > 0 && written < capacity {
                output.removeSubrange(written..<capacity)
                return output
            }
            if written == 0 { throw DICOMError.malformedValue("deflate stream") }
            capacity *= 2
        }
        throw DICOMError.fileTooLarge
    }
}
