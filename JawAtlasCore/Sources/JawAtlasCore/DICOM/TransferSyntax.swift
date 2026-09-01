import Foundation

public enum TransferSyntax: Equatable, Sendable {
    case implicitVRLittleEndian
    case explicitVRLittleEndian
    case deflatedExplicitVRLittleEndian
    case rleLossless
    case jpegLossless
    case unsupported(String)

    public init(uid: String) {
        switch uid {
        case "1.2.840.10008.1.2":
            self = .implicitVRLittleEndian
        case "1.2.840.10008.1.2.1":
            self = .explicitVRLittleEndian
        case "1.2.840.10008.1.2.1.99":
            self = .deflatedExplicitVRLittleEndian
        case "1.2.840.10008.1.2.5":
            self = .rleLossless
        case "1.2.840.10008.1.2.4.70", "1.2.840.10008.1.2.4.57":
            self = .jpegLossless
        default:
            self = .unsupported(TransferSyntax.describe(uid))
        }
    }

    public var isExplicit: Bool {
        switch self {
        case .implicitVRLittleEndian:
            return false
        default:
            return true
        }
    }

    public var isEncapsulated: Bool {
        switch self {
        case .rleLossless, .jpegLossless:
            return true
        default:
            return false
        }
    }

    static func describe(_ uid: String) -> String {
        switch uid {
        case "1.2.840.10008.1.2.2":
            return "big-endian (\(uid)) — re-export as little-endian"
        case "1.2.840.10008.1.2.4.50", "1.2.840.10008.1.2.4.51":
            return "lossy JPEG (\(uid)) — re-export uncompressed or lossless"
        case "1.2.840.10008.1.2.4.90", "1.2.840.10008.1.2.4.91":
            return "JPEG 2000 (\(uid)) — re-export uncompressed or JPEG lossless"
        case "1.2.840.10008.1.2.4.80", "1.2.840.10008.1.2.4.81":
            return "JPEG-LS (\(uid)) — re-export uncompressed or JPEG lossless"
        default:
            return uid
        }
    }
}

public enum LongFormVR {
    private static let codes: Set<UInt16> = {
        let names = ["OB", "OW", "OF", "OD", "OL", "OV", "SQ", "UT", "UN", "UC", "UR", "SV", "UV"]
        var set = Set<UInt16>()
        for name in names {
            let bytes = Array(name.utf8)
            set.insert(UInt16(bytes[0]) | (UInt16(bytes[1]) << 8))
        }
        return set
    }()

    public static func isLongForm(_ code: UInt16) -> Bool { codes.contains(code) }

    public static func isSequence(_ code: UInt16) -> Bool { code == pack("SQ") }

    public static func isUnknown(_ code: UInt16) -> Bool { code == pack("UN") }

    public static func pack(_ name: String) -> UInt16 {
        let bytes = Array(name.utf8)
        guard bytes.count == 2 else { return 0 }
        return UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
    }

    public static func name(_ code: UInt16) -> String {
        String(bytes: [UInt8(code & 0xFF), UInt8((code >> 8) & 0xFF)], encoding: .ascii) ?? "??"
    }
}
