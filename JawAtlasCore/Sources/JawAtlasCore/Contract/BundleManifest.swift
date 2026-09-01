import Foundation

public struct BundleManifest: Codable, Equatable, Sendable {
    public static let formatIdentifier = "jawatlas.bundle"
    public static let currentVersion = 1

    public var format: String
    public var version: Int
    public var caseID: String
    public var label: String
    public var importedAt: Date
    public var dtype: String
    public var endian: String
    public var huRescaled: Bool
    public var dimensions: [Int]
    public var spacingMM: [Double]
    public var orientation: [[Float]]
    public var originMM: [Double]
    public var voxelCount: Int
    public var volumeByteCount: Int
    public var volumeSHA256: String
    public var isGapped: Bool
    public var seriesUIDHash: String
    public var patientTag: String?

    public init(
        caseID: String,
        label: String,
        importedAt: Date,
        dimensions: [Int],
        spacingMM: [Double],
        orientation: [[Float]],
        originMM: [Double],
        volumeSHA256: String,
        isGapped: Bool,
        seriesUIDHash: String
    ) {
        self.format = BundleManifest.formatIdentifier
        self.version = BundleManifest.currentVersion
        self.caseID = caseID
        self.label = label
        self.importedAt = importedAt
        self.dtype = "int16"
        self.endian = "little"
        self.huRescaled = true
        self.dimensions = dimensions
        self.spacingMM = spacingMM
        self.orientation = orientation
        self.originMM = originMM
        self.voxelCount = dimensions.reduce(1, *)
        self.volumeByteCount = dimensions.reduce(1, *) * 2
        self.volumeSHA256 = volumeSHA256
        self.isGapped = isGapped
        self.seriesUIDHash = seriesUIDHash
        self.patientTag = nil
    }

    public var flatOrientation: [Float] { orientation.flatMap { $0 } }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func validated() throws -> BundleManifest {
        guard format == BundleManifest.formatIdentifier else {
            throw VolumeError.bundleCorrupt("format")
        }
        guard version <= BundleManifest.currentVersion else {
            throw VolumeError.versionUnsupported(version)
        }
        guard version == BundleManifest.currentVersion else {
            throw VolumeError.bundleCorrupt("version")
        }
        guard dimensions.count == 3, dimensions.allSatisfy({ $0 > 0 }) else {
            throw VolumeError.bundleCorrupt("dimensions")
        }
        guard spacingMM.count == 3, spacingMM.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw VolumeError.bundleCorrupt("spacing")
        }
        guard originMM.count == 3, originMM.allSatisfy({ $0.isFinite }) else {
            throw VolumeError.bundleCorrupt("origin")
        }
        guard orientation.count == 3, orientation.allSatisfy({ $0.count == 4 }) else {
            throw VolumeError.bundleCorrupt("orientation")
        }
        guard dtype == "int16", endian == "little", huRescaled else {
            throw VolumeError.bundleCorrupt("payload")
        }
        guard voxelCount == dimensions.reduce(1, *), volumeByteCount == voxelCount * 2 else {
            throw VolumeError.bundleCorrupt("counts")
        }
        return self
    }
}

public enum BundleLayout {
    public static let manifestName = "manifest.json"
    public static let volumeName = "volume.i16"
    public static let thumbnailName = "thumbnail.png"
    public static let storyName = "story.json"
    public static let partialSuffix = ".part"
    public static let temporarySuffix = ".tmp"

    public static func manifestURL(in directory: URL) -> URL { directory.appendingPathComponent(manifestName) }
    public static func volumeURL(in directory: URL) -> URL { directory.appendingPathComponent(volumeName) }
    public static func thumbnailURL(in directory: URL) -> URL { directory.appendingPathComponent(thumbnailName) }
    public static func storyURL(in directory: URL) -> URL { directory.appendingPathComponent(storyName) }
}
