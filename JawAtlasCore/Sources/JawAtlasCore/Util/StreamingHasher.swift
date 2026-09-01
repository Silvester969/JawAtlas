import Foundation
import CryptoKit

public struct StreamingHasher {
    private var hasher = SHA256()

    public init() {}

    public mutating func update(_ bytes: UnsafeRawBufferPointer) {
        hasher.update(bufferPointer: bytes)
    }

    public mutating func update(_ data: Data) {
        hasher.update(data: data)
    }

    public func finalizedHex() -> String {
        hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func hex(of string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func hexOfFile(at url: URL, chunkSize: Int = 4 << 20) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
