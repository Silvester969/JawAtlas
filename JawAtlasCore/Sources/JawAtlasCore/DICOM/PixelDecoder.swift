import Foundation

public enum PixelDecoder {
    public static func decodeFrame(
        fileAt url: URL,
        slice: DICOMSlice,
        calibrationOffset: Double = 0,
        into output: inout [Int16]
    ) throws {
        let fileData = try Data(contentsOf: url, options: [.mappedIfSafe])
        let dataset: Data
        if slice.datasetIsDeflated {
            guard slice.datasetStart <= fileData.count else { throw DICOMError.truncated }
            let compressed = fileData.subdata(in: (fileData.startIndex + slice.datasetStart)..<fileData.endIndex)
            dataset = try RawInflate.inflate(compressed, sizeHint: compressed.count * 6)
        } else {
            dataset = fileData
        }
        try decodeFrame(dataset: dataset, slice: slice, calibrationOffset: calibrationOffset, into: &output)
    }

    static func decodeFrame(
        dataset: Data,
        slice: DICOMSlice,
        calibrationOffset: Double,
        into output: inout [Int16]
    ) throws {
        let voxels = slice.voxelsPerSlice
        guard output.count == voxels else { throw DICOMError.malformedValue("buffer") }

        switch slice.syntax {
        case .rleLossless:
            let fragment = try fragmentData(dataset: dataset, slice: slice)
            let words = try RLECodec.decodeSixteenBit(fragment: fragment, pixelCount: voxels)
            convert(words: words, slice: slice, calibrationOffset: calibrationOffset, into: &output)
        case .jpegLossless:
            let fragment = try fragmentData(dataset: dataset, slice: slice)
            let words = try JPEGLossless.decode(
                fragment: fragment,
                expectedWidth: slice.columns,
                expectedHeight: slice.rows
            )
            convert(words: words, slice: slice, calibrationOffset: calibrationOffset, into: &output)
        case .implicitVRLittleEndian, .explicitVRLittleEndian, .deflatedExplicitVRLittleEndian:
            let frameBytes = voxels * 2
            let start = slice.pixelDataOffset + slice.frameIndex * frameBytes
            guard start >= 0, start + frameBytes <= dataset.count,
                  start + frameBytes <= slice.pixelDataOffset + slice.pixelDataLength else {
                throw DICOMError.truncated
            }
            try dataset.withUnsafeBytes { raw in
                try decodeNative(bytes: raw, start: start, slice: slice, calibrationOffset: calibrationOffset, into: &output)
            }
        case .unsupported(let name):
            throw DICOMError.unsupportedTransferSyntax(name)
        }
    }

    private static func fragmentData(dataset: Data, slice: DICOMSlice) throws -> Data {
        guard !slice.fragments.isEmpty else { throw DICOMError.missingRequiredTag("PixelData") }
        let spans: [ByteSpan]
        if slice.frameCount == 1 {
            spans = slice.fragments
        } else {
            guard slice.frameIndex < slice.fragments.count else { throw DICOMError.truncated }
            spans = [slice.fragments[slice.frameIndex]]
        }
        var combined = Data()
        for span in spans {
            guard span.offset >= 0, span.length >= 0, span.offset + span.length <= dataset.count else {
                throw DICOMError.truncated
            }
            combined.append(dataset.subdata(in: (dataset.startIndex + span.offset)..<(dataset.startIndex + span.offset + span.length)))
        }
        return combined
    }

    private static func decodeNative(
        bytes: UnsafeRawBufferPointer,
        start: Int,
        slice: DICOMSlice,
        calibrationOffset: Double,
        into output: inout [Int16]
    ) throws {
        let voxels = slice.voxelsPerSlice
        guard start + voxels * 2 <= bytes.count else { throw DICOMError.truncated }
        var words = [UInt16](repeating: 0, count: voxels)
        for index in 0..<voxels {
            let low = UInt16(bytes[start + index * 2])
            let high = UInt16(bytes[start + index * 2 + 1])
            words[index] = low | (high << 8)
        }
        convert(words: words, slice: slice, calibrationOffset: calibrationOffset, into: &output)
    }

    static func convert(
        words: [UInt16],
        slice: DICOMSlice,
        calibrationOffset: Double,
        into output: inout [Int16]
    ) {
        let voxels = min(words.count, output.count)
        let signed = slice.pixelRepresentation == 1
        let slope = slice.rescaleSlope
        let intercept = slice.rescaleIntercept + calibrationOffset
        let invert = slice.isInvertedGrey
        let storedMax = Int32((1 << min(max(slice.bitsStored, 1), 16)) - 1)
        let integerFastPath = slope == 1 && intercept == intercept.rounded() && abs(intercept) < 32000

        output.withUnsafeMutableBufferPointer { destination in
            let interceptInt = Int32(integerFastPath ? intercept : 0)
            for index in 0..<voxels {
                var raw = signed ? Int32(Int16(bitPattern: words[index])) : Int32(words[index])
                if invert { raw = storedMax - raw }
                let value: Int32
                if integerFastPath {
                    value = raw + interceptInt
                } else {
                    let scaled = (Double(raw) * slope + intercept).rounded()
                    value = scaled.isFinite ? Int32(max(-2147483000, min(2147483000, scaled))) : 0
                }
                destination[index] = Int16(clamping: value)
            }
        }
    }

    public static func decodeHounsfield(bytes: UnsafeRawBufferPointer, slice: DICOMSlice, into output: inout [Int16]) throws {
        guard !slice.syntax.isEncapsulated, !slice.datasetIsDeflated else {
            throw DICOMError.unsupportedStructure("use decodeFrame")
        }
        let frameBytes = slice.voxelsPerSlice * 2
        let start = slice.pixelDataOffset + slice.frameIndex * frameBytes
        try decodeNative(bytes: bytes, start: start, slice: slice, calibrationOffset: 0, into: &output)
    }

    public static func decodeHounsfield(fileAt url: URL, slice: DICOMSlice, into output: inout [Int16]) throws {
        try decodeFrame(fileAt: url, slice: slice, into: &output)
    }
}
