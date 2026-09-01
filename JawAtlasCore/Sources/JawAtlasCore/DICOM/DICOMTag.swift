import Foundation

public struct DICOMTag: Hashable, Sendable {
    public let group: UInt16
    public let element: UInt16

    public init(_ group: UInt16, _ element: UInt16) {
        self.group = group
        self.element = element
    }

    public var isPrivate: Bool { group % 2 == 1 }

    public static let transferSyntaxUID = DICOMTag(0x0002, 0x0010)
    public static let imageType = DICOMTag(0x0008, 0x0008)
    public static let modality = DICOMTag(0x0008, 0x0060)
    public static let studyInstanceUID = DICOMTag(0x0020, 0x000D)
    public static let seriesInstanceUID = DICOMTag(0x0020, 0x000E)
    public static let imagePositionPatient = DICOMTag(0x0020, 0x0032)
    public static let imageOrientationPatient = DICOMTag(0x0020, 0x0037)
    public static let sliceThickness = DICOMTag(0x0018, 0x0050)
    public static let spacingBetweenSlices = DICOMTag(0x0018, 0x0088)
    public static let rows = DICOMTag(0x0028, 0x0010)
    public static let columns = DICOMTag(0x0028, 0x0011)
    public static let pixelSpacing = DICOMTag(0x0028, 0x0030)
    public static let bitsAllocated = DICOMTag(0x0028, 0x0100)
    public static let bitsStored = DICOMTag(0x0028, 0x0101)
    public static let pixelRepresentation = DICOMTag(0x0028, 0x0103)
    public static let samplesPerPixel = DICOMTag(0x0028, 0x0002)
    public static let photometricInterpretation = DICOMTag(0x0028, 0x0004)
    public static let numberOfFrames = DICOMTag(0x0028, 0x0008)
    public static let rescaleIntercept = DICOMTag(0x0028, 0x1052)
    public static let rescaleSlope = DICOMTag(0x0028, 0x1053)
    public static let pixelData = DICOMTag(0x7FE0, 0x0010)

    public static let item = DICOMTag(0xFFFE, 0xE000)
    public static let itemDelimitation = DICOMTag(0xFFFE, 0xE00D)
    public static let sequenceDelimitation = DICOMTag(0xFFFE, 0xE0DD)
}

public enum IdentifierTags {
    public static let all: [DICOMTag: String] = [
        DICOMTag(0x0010, 0x0010): "PatientName",
        DICOMTag(0x0010, 0x0020): "PatientID",
        DICOMTag(0x0010, 0x0021): "IssuerOfPatientID",
        DICOMTag(0x0010, 0x0030): "PatientBirthDate",
        DICOMTag(0x0010, 0x0040): "PatientSex",
        DICOMTag(0x0010, 0x1000): "OtherPatientIDs",
        DICOMTag(0x0010, 0x1001): "OtherPatientNames",
        DICOMTag(0x0010, 0x1010): "PatientAge",
        DICOMTag(0x0010, 0x1040): "PatientAddress",
        DICOMTag(0x0008, 0x0050): "AccessionNumber",
        DICOMTag(0x0008, 0x0080): "InstitutionName",
        DICOMTag(0x0008, 0x0081): "InstitutionAddress",
        DICOMTag(0x0008, 0x0090): "ReferringPhysicianName",
        DICOMTag(0x0008, 0x1048): "PhysiciansOfRecord",
        DICOMTag(0x0008, 0x1050): "PerformingPhysicianName",
        DICOMTag(0x0008, 0x1070): "OperatorsName"
    ]
}

public enum ImplicitVRDictionary {
    public static func vr(for tag: DICOMTag) -> DICOMValueRepresentation {
        switch tag {
        case .rows, .columns, .bitsAllocated, .bitsStored, .pixelRepresentation, .samplesPerPixel:
            return .us
        case .pixelSpacing, .sliceThickness, .spacingBetweenSlices, .imagePositionPatient,
             .imageOrientationPatient, .rescaleIntercept, .rescaleSlope:
            return .ds
        case .studyInstanceUID, .seriesInstanceUID:
            return .ui
        case .imageType, .modality, .photometricInterpretation:
            return .cs
        case .numberOfFrames:
            return .isNumeric
        case .pixelData:
            return .ow
        default:
            return IdentifierTags.all[tag] != nil ? .text : .unknown
        }
    }
}

public enum DICOMValueRepresentation: Sendable {
    case us
    case ds
    case ui
    case cs
    case ow
    case text
    case isNumeric
    case sequence
    case unknown
}
