import Foundation
import Compression
@testable import JawAtlasCore

enum FixtureSyntax {
    case explicitLittleEndian
    case implicitLittleEndian
    case deflated
    case rle
    case jpegLossless
    case headerless
    case compressed(String)

    var uid: String {
        switch self {
        case .explicitLittleEndian, .headerless: return "1.2.840.10008.1.2.1"
        case .implicitLittleEndian: return "1.2.840.10008.1.2"
        case .deflated: return "1.2.840.10008.1.2.1.99"
        case .rle: return "1.2.840.10008.1.2.5"
        case .jpegLossless: return "1.2.840.10008.1.2.4.70"
        case let .compressed(uid): return uid
        }
    }

    var isExplicit: Bool {
        if case .implicitLittleEndian = self { return false }
        return true
    }

    var isEncapsulated: Bool {
        switch self {
        case .rle, .jpegLossless: return true
        default: return false
        }
    }
}

struct FixtureSlice {
    var rows = 8
    var columns = 8
    var pixelSpacing = "0.3\\0.3"
    var sliceThickness: String? = "0.3"
    var spacingBetweenSlices: String? = "0.3"
    var position = "0\\0\\0"
    var orientation = "1\\0\\0\\0\\1\\0"
    var intercept = "-1000"
    var slope = "1"
    var studyUID = "1.2.3.4"
    var seriesUID = "1.2.3.4.5"
    var imageType = "ORIGINAL\\PRIMARY\\AXIAL"
    var bitsAllocated = 16
    var pixelRepresentation = 0
    var patientName: String? = "DOE^JANE"
    var pixels: [UInt16] = []
    var syntax = FixtureSyntax.explicitLittleEndian
    var includePixelData = true
    var includeRescale = true
    var photometric = "MONOCHROME2"
    var frames = 1
    var undefinedLengthSequence = false

    func encoded() -> Data {
        var data = Data()
        if case .headerless = syntax {
        } else {
            data = Data(repeating: 0, count: 128)
            data.append(contentsOf: Array("DICM".utf8))
            data.append(FixtureWriter.element(0x0002, 0x0010, vr: "UI", value: FixtureWriter.uid(syntax.uid), explicit: true))
        }

        let explicit = syntax.isExplicit
        var body = Data()
        body.append(FixtureWriter.element(0x0008, 0x0008, vr: "CS", value: FixtureWriter.text(imageType), explicit: explicit))
        if let patientName {
            body.append(FixtureWriter.element(0x0010, 0x0010, vr: "PN", value: FixtureWriter.text(patientName), explicit: explicit))
        }
        if undefinedLengthSequence {
            body.append(FixtureWriter.undefinedSequence(explicit: explicit))
        }
        if let sliceThickness {
            body.append(FixtureWriter.element(0x0018, 0x0050, vr: "DS", value: FixtureWriter.text(sliceThickness), explicit: explicit))
        }
        if let spacingBetweenSlices {
            body.append(FixtureWriter.element(0x0018, 0x0088, vr: "DS", value: FixtureWriter.text(spacingBetweenSlices), explicit: explicit))
        }
        body.append(FixtureWriter.element(0x0020, 0x000D, vr: "UI", value: FixtureWriter.uid(studyUID), explicit: explicit))
        body.append(FixtureWriter.element(0x0020, 0x000E, vr: "UI", value: FixtureWriter.uid(seriesUID), explicit: explicit))
        body.append(FixtureWriter.element(0x0020, 0x0032, vr: "DS", value: FixtureWriter.text(position), explicit: explicit))
        body.append(FixtureWriter.element(0x0020, 0x0037, vr: "DS", value: FixtureWriter.text(orientation), explicit: explicit))
        body.append(FixtureWriter.element(0x0028, 0x0002, vr: "US", value: FixtureWriter.uint16(1), explicit: explicit))
        body.append(FixtureWriter.element(0x0028, 0x0004, vr: "CS", value: FixtureWriter.text(photometric), explicit: explicit))
        if frames > 1 {
            body.append(FixtureWriter.element(0x0028, 0x0008, vr: "IS", value: FixtureWriter.text(String(frames)), explicit: explicit))
        }
        body.append(FixtureWriter.element(0x0028, 0x0010, vr: "US", value: FixtureWriter.uint16(UInt16(rows)), explicit: explicit))
        body.append(FixtureWriter.element(0x0028, 0x0011, vr: "US", value: FixtureWriter.uint16(UInt16(columns)), explicit: explicit))
        body.append(FixtureWriter.element(0x0028, 0x0030, vr: "DS", value: FixtureWriter.text(pixelSpacing), explicit: explicit))
        body.append(FixtureWriter.element(0x0028, 0x0100, vr: "US", value: FixtureWriter.uint16(UInt16(bitsAllocated)), explicit: explicit))
        body.append(FixtureWriter.element(0x0028, 0x0101, vr: "US", value: FixtureWriter.uint16(UInt16(bitsAllocated)), explicit: explicit))
        body.append(FixtureWriter.element(0x0028, 0x0103, vr: "US", value: FixtureWriter.uint16(UInt16(pixelRepresentation)), explicit: explicit))
        if includeRescale {
            body.append(FixtureWriter.element(0x0028, 0x1052, vr: "DS", value: FixtureWriter.text(intercept), explicit: explicit))
            body.append(FixtureWriter.element(0x0028, 0x1053, vr: "DS", value: FixtureWriter.text(slope), explicit: explicit))
        }
        if includePixelData {
            let values = pixels.isEmpty ? Array(repeating: UInt16(1200), count: rows * columns * frames) : pixels
            if syntax.isEncapsulated {
                body.append(FixtureWriter.encapsulatedPixelData(
                    values: values,
                    rows: rows,
                    columns: columns,
                    frames: frames,
                    syntax: syntax
                ))
            } else {
                var payload = Data()
                for value in values {
                    payload.append(UInt8(value & 0xFF))
                    payload.append(UInt8((value >> 8) & 0xFF))
                }
                body.append(FixtureWriter.element(0x7FE0, 0x0010, vr: "OW", value: payload, explicit: explicit))
            }
        }
        if case .deflated = syntax {
            data.append(FixtureWriter.deflate(body))
        } else {
            data.append(body)
        }
        return data
    }
}

enum FixtureWriter {
    static func text(_ value: String) -> Data {
        var data = Data(value.utf8)
        if data.count % 2 == 1 { data.append(0x20) }
        return data
    }

    static func uid(_ value: String) -> Data {
        var data = Data(value.utf8)
        if data.count % 2 == 1 { data.append(0x00) }
        return data
    }

    static func uint16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    static func uint32(_ value: UInt32) -> Data {
        var data = Data()
        for shift in stride(from: 0, to: 32, by: 8) {
            data.append(UInt8((value >> UInt32(shift)) & 0xFF))
        }
        return data
    }

    static func tag(_ group: UInt16, _ element: UInt16) -> Data {
        uint16(group) + uint16(element)
    }

    static func element(_ group: UInt16, _ element: UInt16, vr: String, value: Data, explicit: Bool) -> Data {
        var data = tag(group, element)
        let longForm = ["OB", "OW", "OF", "SQ", "UT", "UN"].contains(vr)
        if explicit {
            data.append(contentsOf: Array(vr.utf8))
            if longForm {
                data.append(uint16(0))
                data.append(uint32(UInt32(value.count)))
            } else {
                data.append(uint16(UInt16(value.count)))
            }
        } else {
            data.append(uint32(UInt32(value.count)))
        }
        data.append(value)
        return data
    }

    static func deflate(_ body: Data) -> Data {
        var output = Data(count: body.count + 4096)
        let written = output.withUnsafeMutableBytes { outRaw -> Int in
            body.withUnsafeBytes { inRaw -> Int in
                guard let outBase = outRaw.baseAddress, let inBase = inRaw.baseAddress else { return 0 }
                return compression_encode_buffer(
                    outBase.assumingMemoryBound(to: UInt8.self),
                    body.count + 4096,
                    inBase.assumingMemoryBound(to: UInt8.self),
                    body.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        output.removeSubrange(written..<output.count)
        return output
    }

    static func encapsulatedPixelData(
        values: [UInt16],
        rows: Int,
        columns: Int,
        frames: Int,
        syntax: FixtureSyntax
    ) -> Data {
        var data = tag(0x7FE0, 0x0010)
        data.append(contentsOf: Array("OB".utf8))
        data.append(uint16(0))
        data.append(uint32(0xFFFF_FFFF))
        data.append(tag(0xFFFE, 0xE000))
        data.append(uint32(0))
        let perFrame = rows * columns
        for frame in 0..<frames {
            let framePixels = Array(values[(frame * perFrame)..<((frame + 1) * perFrame)])
            var fragment: Data
            switch syntax {
            case .rle:
                fragment = RLECodec.encodeSixteenBit(framePixels)
            case .jpegLossless:
                fragment = FixtureJPEGLossless.encode(pixels: framePixels, width: columns, height: rows, precision: 16)
            default:
                fragment = Data()
            }
            if fragment.count % 2 == 1 { fragment.append(0) }
            data.append(tag(0xFFFE, 0xE000))
            data.append(uint32(UInt32(fragment.count)))
            data.append(fragment)
        }
        data.append(tag(0xFFFE, 0xE0DD))
        data.append(uint32(0))
        return data
    }

    static func undefinedSequence(explicit: Bool) -> Data {
        var data = tag(0x0008, 0x1140)
        if explicit {
            data.append(contentsOf: Array("SQ".utf8))
            data.append(uint16(0))
        }
        data.append(uint32(0xFFFF_FFFF))
        data.append(tag(0xFFFE, 0xE000))
        data.append(uint32(0xFFFF_FFFF))
        data.append(element(0x0008, 0x1150, vr: "UI", value: uid("1.2.840.10008.5.1.4.1.1.2"), explicit: explicit))
        data.append(tag(0xFFFE, 0xE00D))
        data.append(uint32(0))
        data.append(tag(0xFFFE, 0xE0DD))
        data.append(uint32(0))
        return data
    }
}

enum FixtureSeries {
    static func write(
        into directory: URL,
        slices: Int,
        spacing: Double = 0.3,
        rows: Int = 8,
        columns: Int = 8,
        syntax: FixtureSyntax = .explicitLittleEndian,
        pixelRepresentation: Int = 0,
        orientation: String = "1\\0\\0\\0\\1\\0",
        gapAt: Int? = nil,
        patientName: String? = "DOE^JANE",
        seriesUID: String = "1.2.3.4.5",
        valueFor: (Int, Int) -> UInt16 = { index, voxel in UInt16(1000 + (index * 7 + voxel) % 500) }
    ) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = []
        var z = 0.0
        for index in 0..<slices {
            if let gapAt, index == gapAt { z += spacing * 4 }
            var fixture = FixtureSlice()
            fixture.rows = rows
            fixture.columns = columns
            fixture.syntax = syntax
            fixture.pixelRepresentation = pixelRepresentation
            fixture.orientation = orientation
            fixture.position = "0\\0\\\(z)"
            fixture.spacingBetweenSlices = nil
            fixture.sliceThickness = "61.2"
            fixture.patientName = patientName
            fixture.seriesUID = seriesUID
            fixture.pixels = (0..<(rows * columns)).map { valueFor(index, $0) }
            let url = directory.appendingPathComponent(String(format: "slice-%04d.dcm", index))
            try fixture.encoded().write(to: url)
            urls.append(url)
            z += spacing
        }
        return urls
    }
}
