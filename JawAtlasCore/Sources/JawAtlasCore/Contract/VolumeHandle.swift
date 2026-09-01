import Foundation

public struct VolumeHandle: @unchecked Sendable {
    public let caseID: String
    public let dimensions: (Int32, Int32, Int32)
    public let spacingMM: (Double, Double, Double)
    public let orientation: [Float]
    public let originMM: (Double, Double, Double)
    public let huBuffer: UnsafeRawPointer
    public let byteCount: Int
    public let isGapped: Bool

    private let mapping: VolumeMapping

    init(caseID: String, manifest: BundleManifest, mapping: VolumeMapping) {
        self.caseID = caseID
        self.dimensions = (Int32(manifest.dimensions[0]), Int32(manifest.dimensions[1]), Int32(manifest.dimensions[2]))
        self.spacingMM = (manifest.spacingMM[0], manifest.spacingMM[1], manifest.spacingMM[2])
        self.orientation = manifest.flatOrientation
        self.originMM = (manifest.originMM[0], manifest.originMM[1], manifest.originMM[2])
        self.huBuffer = UnsafeRawPointer(mapping.base)
        self.byteCount = mapping.length
        self.isGapped = manifest.isGapped
        self.mapping = mapping
    }

    public func close() {
        mapping.unmap()
    }

    public var voxelCount: Int { byteCount / 2 }

    public var width: Int { Int(dimensions.0) }
    public var height: Int { Int(dimensions.1) }
    public var depth: Int { Int(dimensions.2) }

    public func sliceRange(_ k: Int) -> Range<Int>? {
        guard k >= 0, k < depth else { return nil }
        let perSlice = width * height
        return (k * perSlice)..<((k + 1) * perSlice)
    }

    public func withSlice<T>(_ k: Int, _ body: (UnsafeBufferPointer<Int16>) throws -> T) rethrows -> T? {
        guard let range = sliceRange(k) else { return nil }
        let typed = huBuffer.bindMemory(to: Int16.self, capacity: voxelCount)
        let buffer = UnsafeBufferPointer(start: typed + range.lowerBound, count: range.count)
        return try body(buffer)
    }
}

final class VolumeMapping: @unchecked Sendable {
    let base: UnsafeMutableRawPointer
    let length: Int
    private var isMapped = true
    private let lock = NSLock()

    init(url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw VolumeError.caseMissing(url.lastPathComponent) }
        defer { close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_size > 0 else {
            throw VolumeError.bundleCorrupt("empty volume")
        }
        let size = Int(status.st_size)
        guard let pointer = mmap(nil, size, PROT_READ, MAP_FILE | MAP_PRIVATE, descriptor, 0),
              pointer != MAP_FAILED else {
            throw VolumeError.mappingFailed
        }
        self.base = pointer
        self.length = size
    }

    func unmap() {
        lock.lock()
        defer { lock.unlock() }
        guard isMapped else { return }
        munmap(base, length)
        isMapped = false
    }

    deinit {
        unmap()
    }
}
