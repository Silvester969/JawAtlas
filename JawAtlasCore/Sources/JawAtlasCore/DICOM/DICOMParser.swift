import Foundation

public enum DICOMParser {
    public static let maximumFileBytes = 512 << 20
    public static let maximumFrames = 4096
    private static let maximumNestingDepth = 8

    private enum ScanStop {
        case endOfRange
        case delimiter
        case pixelData
    }

    private struct Accumulator {
        var rows: Int?
        var columns: Int?
        var pixelSpacing: [Double] = []
        var sliceThickness: Double?
        var spacingBetweenSlices: Double?
        var position: [Double] = []
        var orientation: [Double] = []
        var rescaleSlope: Double = 1
        var rescaleIntercept: Double = 0
        var sawRescale = false
        var studyUID: String = ""
        var seriesUID: String = ""
        var imageType: String = ""
        var modality: String = ""
        var photometric: String = ""
        var samplesPerPixel: Int = 1
        var numberOfFrames: Int = 1
        var bitsAllocated: Int?
        var bitsStored: Int?
        var pixelRepresentation: Int = 0
        var pixelDataOffset: Int?
        var pixelDataLength: Int = 0
        var fragments: [ByteSpan] = []
        var identifierValues: [String] = []
    }

    public static func isDICOM(fileAt url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 160), head.count >= 8 else { return false }
        if head.count >= 132, head[128...131].elementsEqual(Array("DICM".utf8)) { return true }
        return headerlessSyntax(head: head) != nil
    }

    static func headerlessSyntax(head: Data) -> TransferSyntax? {
        guard head.count >= 8 else { return nil }
        let group = UInt16(head[0]) | (UInt16(head[1]) << 8)
        let element = UInt16(head[2]) | (UInt16(head[3]) << 8)
        guard group == 0x0008, element <= 0x2000 else { return nil }
        let vr = String(bytes: [head[4], head[5]], encoding: .ascii) ?? ""
        let knownVRs: Set<String> = ["CS", "UI", "DA", "TM", "SH", "LO", "PN", "ST", "US", "DS", "IS", "OB", "OW", "SQ", "AE", "AS", "AT", "LT", "UT", "UN"]
        if knownVRs.contains(vr) { return .explicitVRLittleEndian }
        let length = UInt32(head[4]) | (UInt32(head[5]) << 8) | (UInt32(head[6]) << 16) | (UInt32(head[7]) << 24)
        if length < 0x10000 { return .implicitVRLittleEndian }
        return nil
    }

    public static func parse(fileAt url: URL) throws -> DICOMSlice {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maximumFileBytes else { throw DICOMError.fileTooLarge }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try parse(data: data, sourceURL: url)
    }

    public static func parseExpanded(fileAt url: URL) throws -> [DICOMSlice] {
        let base = try parse(fileAt: url)
        guard base.frameCount > 1 else { return [base] }
        guard let step = SeriesBuilder.resolveSliceSpacing(
            declared: base.spacingBetweenSlicesMM,
            derived: nil,
            thickness: base.sliceThicknessMM
        ) else {
            throw DICOMError.unsupportedPixelFormat("multi-frame without slice spacing")
        }
        let normal = base.sliceNormal
        return (0..<base.frameCount).map { index in
            var frame = base
            frame.frameIndex = index
            frame.position = Vec3(
                base.position.x + normal.x * step * Double(index),
                base.position.y + normal.y * step * Double(index),
                base.position.z + normal.z * step * Double(index)
            )
            return frame
        }
    }

    public static func parse(data: Data, sourceURL: URL) throws -> DICOMSlice {
        try data.withUnsafeBytes { raw in
            try parse(bytes: raw, fullData: data, sourceURL: sourceURL)
        }
    }

    public static func parse(bytes: UnsafeRawBufferPointer, sourceURL: URL) throws -> DICOMSlice {
        try parse(bytes: bytes, fullData: nil, sourceURL: sourceURL)
    }

    private static func parse(
        bytes: UnsafeRawBufferPointer,
        fullData: Data?,
        sourceURL: URL
    ) throws -> DICOMSlice {
        var accumulator = Accumulator()

        let hasPreamble = bytes.count > 132 && ByteCursor(bytes).matches("DICM", at: 128)
        let syntax: TransferSyntax
        var cursor = ByteCursor(bytes)

        if hasPreamble {
            try cursor.seek(to: 132)
            syntax = try parseMetaGroup(&cursor, accumulator: &accumulator)
        } else {
            var head = Data()
            for index in 0..<min(bytes.count, 8) { head.append(bytes[index]) }
            guard let detected = headerlessSyntax(head: head) else { throw DICOMError.notDICOM }
            syntax = detected
        }

        switch syntax {
        case .unsupported(let name):
            throw DICOMError.unsupportedTransferSyntax(name)
        case .deflatedExplicitVRLittleEndian:
            let datasetStart = cursor.offset
            var compressed = Data()
            compressed.reserveCapacity(bytes.count - datasetStart)
            for index in datasetStart..<bytes.count { compressed.append(bytes[index]) }
            let inflated = try RawInflate.inflate(compressed, sizeHint: compressed.count * 6)
            return try inflated.withUnsafeBytes { inflatedRaw -> DICOMSlice in
                var inflatedCursor = ByteCursor(inflatedRaw)
                _ = try scan(
                    &inflatedCursor,
                    explicit: true,
                    syntax: syntax,
                    end: inflatedRaw.count,
                    depth: 0,
                    capture: true,
                    accumulator: &accumulator
                )
                return try makeSlice(
                    from: accumulator,
                    syntax: syntax,
                    datasetIsDeflated: true,
                    datasetStart: datasetStart,
                    sourceURL: sourceURL
                )
            }
        case .implicitVRLittleEndian, .explicitVRLittleEndian, .rleLossless, .jpegLossless:
            _ = try scan(
                &cursor,
                explicit: syntax.isExplicit,
                syntax: syntax,
                end: bytes.count,
                depth: 0,
                capture: true,
                accumulator: &accumulator
            )
            return try makeSlice(
                from: accumulator,
                syntax: syntax,
                datasetIsDeflated: false,
                datasetStart: 0,
                sourceURL: sourceURL
            )
        }
    }

    private static func parseMetaGroup(_ cursor: inout ByteCursor, accumulator: inout Accumulator) throws -> TransferSyntax {
        var syntaxUID: String?
        while cursor.remaining >= 8 {
            let mark = cursor.offset
            let group = try cursor.readUInt16()
            let element = try cursor.readUInt16()
            guard group == 0x0002 else {
                try cursor.seek(to: mark)
                break
            }
            let vrCode = try cursor.readUInt16()
            let length: Int
            if LongFormVR.isLongForm(vrCode) {
                _ = try cursor.readUInt16()
                length = Int(try cursor.readUInt32())
            } else {
                length = Int(try cursor.readUInt16())
            }
            guard length >= 0, length <= cursor.remaining else { throw DICOMError.truncated }
            let value = try cursor.readBytes(length)
            if DICOMTag(group, element) == .transferSyntaxUID {
                syntaxUID = ASCIIValue.string(value)
            }
            if IdentifierTags.all[DICOMTag(group, element)] != nil {
                let text = ASCIIValue.string(value)
                if !text.isEmpty { accumulator.identifierValues.append(text) }
            }
        }
        guard let uid = syntaxUID, !uid.isEmpty else { throw DICOMError.notDICOM }
        return TransferSyntax(uid: uid)
    }

    private static func scan(
        _ cursor: inout ByteCursor,
        explicit: Bool,
        syntax: TransferSyntax,
        end: Int,
        depth: Int,
        capture: Bool,
        accumulator: inout Accumulator
    ) throws -> ScanStop {
        guard depth <= maximumNestingDepth else { throw DICOMError.unsupportedStructure("nesting") }
        while cursor.offset + 8 <= end {
            let elementStart = cursor.offset
            let group = try cursor.readUInt16()
            let element = try cursor.readUInt16()
            let tag = DICOMTag(group, element)

            if group == 0xFFFE {
                let rawItemLength = try cursor.readUInt32()
                if tag == .itemDelimitation || tag == .sequenceDelimitation { return .delimiter }
                if tag == .item {
                    if rawItemLength == 0xFFFF_FFFF {
                        _ = try scan(
                            &cursor, explicit: explicit, syntax: syntax,
                            end: end, depth: depth + 1, capture: false, accumulator: &accumulator
                        )
                    } else {
                        try cursor.skip(Int(rawItemLength))
                    }
                    continue
                }
                throw DICOMError.unsupportedStructure("delimiter")
            }

            var vrCode: UInt16 = 0
            var rawLength: UInt32 = 0
            if explicit {
                vrCode = try cursor.readUInt16()
                if LongFormVR.isLongForm(vrCode) {
                    _ = try cursor.readUInt16()
                    rawLength = try cursor.readUInt32()
                } else {
                    rawLength = UInt32(try cursor.readUInt16())
                }
            } else {
                rawLength = try cursor.readUInt32()
            }

            if rawLength == 0xFFFF_FFFF {
                if tag == .pixelData {
                    guard syntax.isEncapsulated else {
                        throw DICOMError.unsupportedPixelFormat("encapsulated data in a native transfer syntax")
                    }
                    try parseFragments(&cursor, end: end, accumulator: &accumulator, capture: capture)
                    return .pixelData
                }
                _ = try scan(
                    &cursor, explicit: explicit, syntax: syntax,
                    end: end, depth: depth + 1, capture: false, accumulator: &accumulator
                )
                continue
            }

            let length = Int(rawLength)
            guard length >= 0, length <= end - cursor.offset else { throw DICOMError.truncated }

            if tag == .pixelData {
                if capture {
                    accumulator.pixelDataOffset = cursor.offset
                    accumulator.pixelDataLength = length
                }
                return .pixelData
            }

            let isSequence = explicit ? LongFormVR.isSequence(vrCode) : (ImplicitVRDictionary.vr(for: tag) == .sequence)
            if isSequence {
                try cursor.skip(length)
                guard cursor.offset > elementStart else { throw DICOMError.unsupportedStructure("stalled") }
                continue
            }

            let value = try cursor.readBytes(length)
            if capture {
                let representation = explicit ? explicitRepresentation(vrCode, tag: tag) : ImplicitVRDictionary.vr(for: tag)
                absorb(tag: tag, representation: representation, value: value, into: &accumulator)
            }
            guard cursor.offset > elementStart else { throw DICOMError.unsupportedStructure("stalled") }
        }
        return .endOfRange
    }

    private static func parseFragments(
        _ cursor: inout ByteCursor,
        end: Int,
        accumulator: inout Accumulator,
        capture: Bool
    ) throws {
        var isFirstItem = true
        var guardCounter = 0
        while cursor.offset + 8 <= end {
            guardCounter += 1
            guard guardCounter <= maximumFrames * 4 else { throw DICOMError.unsupportedStructure("fragments") }
            let group = try cursor.readUInt16()
            let element = try cursor.readUInt16()
            let length = Int(try cursor.readUInt32())
            let tag = DICOMTag(group, element)
            if tag == .sequenceDelimitation { return }
            guard tag == .item, length >= 0, length <= end - cursor.offset else {
                throw DICOMError.malformedValue("pixel fragments")
            }
            if isFirstItem {
                isFirstItem = false
                try cursor.skip(length)
                continue
            }
            if capture {
                accumulator.fragments.append(ByteSpan(offset: cursor.offset, length: length))
            }
            try cursor.skip(length)
        }
        throw DICOMError.truncated
    }

    private static func explicitRepresentation(_ vrCode: UInt16, tag: DICOMTag) -> DICOMValueRepresentation {
        if LongFormVR.isSequence(vrCode) { return .sequence }
        if vrCode == LongFormVR.pack("US") { return .us }
        if vrCode == LongFormVR.pack("DS") { return .ds }
        if vrCode == LongFormVR.pack("IS") { return .isNumeric }
        if vrCode == LongFormVR.pack("UI") { return .ui }
        if vrCode == LongFormVR.pack("CS") { return .cs }
        if LongFormVR.isUnknown(vrCode) { return ImplicitVRDictionary.vr(for: tag) }
        return .text
    }

    private static func absorb(
        tag: DICOMTag,
        representation: DICOMValueRepresentation,
        value: UnsafeRawBufferPointer,
        into accumulator: inout Accumulator
    ) {
        if IdentifierTags.all[tag] != nil {
            let text = ASCIIValue.string(value)
            if !text.isEmpty { accumulator.identifierValues.append(text) }
            return
        }
        switch tag {
        case .rows:
            accumulator.rows = unsignedShort(value, representation: representation)
        case .columns:
            accumulator.columns = unsignedShort(value, representation: representation)
        case .bitsAllocated:
            accumulator.bitsAllocated = unsignedShort(value, representation: representation)
        case .bitsStored:
            accumulator.bitsStored = unsignedShort(value, representation: representation)
        case .pixelRepresentation:
            accumulator.pixelRepresentation = unsignedShort(value, representation: representation) ?? 0
        case .samplesPerPixel:
            accumulator.samplesPerPixel = unsignedShort(value, representation: representation) ?? 1
        case .numberOfFrames:
            accumulator.numberOfFrames = Int(ASCIIValue.decimals(value).first ?? 1)
        case .pixelSpacing:
            accumulator.pixelSpacing = ASCIIValue.decimals(value)
        case .sliceThickness:
            accumulator.sliceThickness = ASCIIValue.decimals(value).first
        case .spacingBetweenSlices:
            accumulator.spacingBetweenSlices = ASCIIValue.decimals(value).first
        case .imagePositionPatient:
            accumulator.position = ASCIIValue.decimals(value)
        case .imageOrientationPatient:
            accumulator.orientation = ASCIIValue.decimals(value)
        case .rescaleSlope:
            accumulator.rescaleSlope = ASCIIValue.decimals(value).first ?? 1
            accumulator.sawRescale = true
        case .rescaleIntercept:
            accumulator.rescaleIntercept = ASCIIValue.decimals(value).first ?? 0
            accumulator.sawRescale = true
        case .studyInstanceUID:
            accumulator.studyUID = ASCIIValue.string(value)
        case .seriesInstanceUID:
            accumulator.seriesUID = ASCIIValue.string(value)
        case .imageType:
            accumulator.imageType = ASCIIValue.string(value)
        case .modality:
            accumulator.modality = ASCIIValue.string(value)
        case .photometricInterpretation:
            accumulator.photometric = ASCIIValue.string(value)
        default:
            break
        }
    }

    private static func unsignedShort(_ value: UnsafeRawBufferPointer, representation: DICOMValueRepresentation) -> Int? {
        if representation == .us || value.count == 2 {
            guard value.count >= 2 else { return nil }
            return Int(UInt16(value[0]) | (UInt16(value[1]) << 8))
        }
        return ASCIIValue.decimals(value).first.map { Int($0) }
    }

    private static func makeSlice(
        from accumulator: Accumulator,
        syntax: TransferSyntax,
        datasetIsDeflated: Bool,
        datasetStart: Int,
        sourceURL: URL
    ) throws -> DICOMSlice {
        guard let rows = accumulator.rows, rows > 0 else { throw DICOMError.missingRequiredTag("Rows") }
        guard let columns = accumulator.columns, columns > 0 else { throw DICOMError.missingRequiredTag("Columns") }
        guard let bits = accumulator.bitsAllocated else { throw DICOMError.missingRequiredTag("BitsAllocated") }
        guard bits == 16 else { throw DICOMError.unsupportedPixelFormat("BitsAllocated \(bits)") }
        guard accumulator.samplesPerPixel == 1 else { throw DICOMError.unsupportedPixelFormat("colour") }
        let frames = accumulator.numberOfFrames
        guard frames >= 1, frames <= DICOMParser.maximumFrames else {
            throw DICOMError.unsupportedPixelFormat("frame count \(frames)")
        }
        if !accumulator.photometric.isEmpty && !accumulator.photometric.hasPrefix("MONOCHROME") {
            throw DICOMError.unsupportedPixelFormat(accumulator.photometric)
        }
        guard accumulator.pixelSpacing.count >= 2,
              accumulator.pixelSpacing[0] > 0,
              accumulator.pixelSpacing[1] > 0 else {
            throw DICOMError.missingRequiredTag("PixelSpacing")
        }
        guard accumulator.position.count >= 3 else { throw DICOMError.missingRequiredTag("ImagePositionPatient") }
        guard accumulator.orientation.count >= 6 else { throw DICOMError.missingRequiredTag("ImageOrientationPatient") }

        let rowDirection = Vec3(accumulator.orientation[0], accumulator.orientation[1], accumulator.orientation[2]).normalized
        let columnDirection = Vec3(accumulator.orientation[3], accumulator.orientation[4], accumulator.orientation[5]).normalized
        guard rowDirection.length > 0.5, columnDirection.length > 0.5,
              rowDirection.cross(columnDirection).length > 0.5 else {
            throw DICOMError.malformedValue("ImageOrientationPatient")
        }
        let slope = accumulator.rescaleSlope == 0 ? 1 : accumulator.rescaleSlope
        guard slope.isFinite, accumulator.rescaleIntercept.isFinite else {
            throw DICOMError.malformedValue("Rescale")
        }

        if syntax.isEncapsulated {
            guard !accumulator.fragments.isEmpty else { throw DICOMError.missingRequiredTag("PixelData") }
            guard frames == 1 || accumulator.fragments.count == frames else {
                throw DICOMError.unsupportedPixelFormat("fragment layout")
            }
        } else {
            guard let offset = accumulator.pixelDataOffset else { throw DICOMError.missingRequiredTag("PixelData") }
            let expected = rows * columns * 2 * frames
            guard accumulator.pixelDataLength >= expected else { throw DICOMError.truncated }
            _ = offset
        }

        return DICOMSlice(
            sourceURL: sourceURL,
            rows: rows,
            columns: columns,
            rowSpacingMM: accumulator.pixelSpacing[0],
            columnSpacingMM: accumulator.pixelSpacing[1],
            sliceThicknessMM: accumulator.sliceThickness,
            spacingBetweenSlicesMM: accumulator.spacingBetweenSlices,
            position: Vec3(accumulator.position[0], accumulator.position[1], accumulator.position[2]),
            rowDirection: rowDirection,
            columnDirection: columnDirection,
            rescaleSlope: slope,
            rescaleIntercept: accumulator.rescaleIntercept,
            hasRescaleTags: accumulator.sawRescale,
            photometric: accumulator.photometric,
            studyUID: accumulator.studyUID,
            seriesUID: accumulator.seriesUID,
            imageType: accumulator.imageType,
            bitsAllocated: bits,
            bitsStored: accumulator.bitsStored ?? bits,
            pixelRepresentation: accumulator.pixelRepresentation,
            syntax: syntax,
            datasetIsDeflated: datasetIsDeflated,
            datasetStart: datasetStart,
            pixelDataOffset: accumulator.pixelDataOffset ?? 0,
            pixelDataLength: accumulator.pixelDataLength,
            fragments: accumulator.fragments,
            frameCount: frames,
            frameIndex: 0,
            identifierValues: accumulator.identifierValues
        )
    }
}
