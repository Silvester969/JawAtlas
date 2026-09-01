import Foundation

public enum VolumeError: Error, Equatable, Sendable {
    case bundleCorrupt(String)
    case hashMismatch
    case versionUnsupported(Int)
    case caseMissing(String)
    case mappingFailed

    public var userMessage: String {
        switch self {
        case .bundleCorrupt:
            return "This scan could not be opened. The file appears incomplete or damaged."
        case .hashMismatch:
            return "This scan failed its integrity check and may be damaged."
        case .versionUnsupported:
            return "This scan was stored by a newer version of JawAtlas."
        case .caseMissing:
            return "This scan is no longer stored on this device."
        case .mappingFailed:
            return "This scan could not be loaded into memory."
        }
    }
}

public enum ImportError: Error, Equatable, Sendable {
    case nothingSelected
    case noReadableFiles(unreadable: Int, ignored: Int)
    case noUsableSeries(unreadable: Int, ignored: Int)
    case insufficientSlices(found: Int, minimum: Int)
    case inconsistentGeometry(String)
    case spacingUnresolvable
    case identifierLeak(String)
    case diskFull
    case writeFailed(String)
    case cancelled

    public var userMessage: String {
        switch self {
        case .nothingSelected:
            return "No files were selected."
        case let .noReadableFiles(unreadable, ignored):
            return "No scan slices could be read. \(unreadable) file\(unreadable == 1 ? "" : "s") unreadable, \(ignored) not DICOM."
        case let .noUsableSeries(unreadable, ignored):
            return "No complete scan series was found. \(unreadable) file\(unreadable == 1 ? "" : "s") unreadable, \(ignored) not DICOM."
        case let .insufficientSlices(found, minimum):
            return "This series has only \(found) usable slice\(found == 1 ? "" : "s"); at least \(minimum) are needed to build a volume."
        case let .inconsistentGeometry(detail):
            return "The slices in this series do not fit together: \(detail)."
        case .spacingUnresolvable:
            return "The slice spacing of this series could not be determined."
        case .identifierLeak:
            return "Import was stopped because patient details could not be safely removed."
        case .diskFull:
            return "There is not enough free space on this device to import this scan."
        case let .writeFailed(detail):
            return "The scan could not be saved: \(detail)."
        case .cancelled:
            return "Import cancelled."
        }
    }
}

public enum DICOMError: Error, Equatable, Sendable {
    case notDICOM
    case truncated
    case fileTooLarge
    case unsupportedTransferSyntax(String)
    case unsupportedPixelFormat(String)
    case missingRequiredTag(String)
    case malformedValue(String)
    case unsupportedStructure(String)
}
