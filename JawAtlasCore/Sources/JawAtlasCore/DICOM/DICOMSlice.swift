import Foundation

public struct ByteSpan: Sendable, Equatable {
    public let offset: Int
    public let length: Int

    public init(offset: Int, length: Int) {
        self.offset = offset
        self.length = length
    }
}

public struct DICOMSlice: Sendable {
    public var sourceURL: URL
    public var rows: Int
    public var columns: Int
    public var rowSpacingMM: Double
    public var columnSpacingMM: Double
    public var sliceThicknessMM: Double?
    public var spacingBetweenSlicesMM: Double?
    public var position: Vec3
    public var rowDirection: Vec3
    public var columnDirection: Vec3
    public var rescaleSlope: Double
    public var rescaleIntercept: Double
    public var hasRescaleTags: Bool
    public var photometric: String
    public var studyUID: String
    public var seriesUID: String
    public var imageType: String
    public var bitsAllocated: Int
    public var bitsStored: Int
    public var pixelRepresentation: Int
    public var syntax: TransferSyntax
    public var datasetIsDeflated: Bool
    public var datasetStart: Int
    public var pixelDataOffset: Int
    public var pixelDataLength: Int
    public var fragments: [ByteSpan]
    public var frameCount: Int
    public var frameIndex: Int
    public var identifierValues: [String]

    public var sliceNormal: Vec3 { rowDirection.cross(columnDirection).normalized }

    public var positionAlongNormal: Double { position.dot(sliceNormal) }

    public var voxelsPerSlice: Int { rows * columns }

    public var isInvertedGrey: Bool {
        photometric == "MONOCHROME1" && !hasRescaleTags
    }
}
