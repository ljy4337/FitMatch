import Foundation

enum MeasurementCode: String, Codable, CaseIterable, Hashable {
    case shoulderWidthSeamToSeam = "shoulder_width_seam_to_seam"
    case chestWidthPitToPit = "chest_width_pit_to_pit"
    case bodyLengthHPSToHemFront = "body_length_hps_to_hem_front"
    case bodyLengthBackNeckToHem = "body_length_back_neck_to_hem"
    case sleeveShoulderSeamToCuff = "sleeve_shoulder_seam_to_cuff"
    case sleeveCenterBackToCuff = "sleeve_center_back_to_cuff"
    case sleeveRaglanNeckToCuff = "sleeve_raglan_neck_to_cuff"
    case unknown
    case legacyUnknown = "legacy_unknown"
}

enum MeasurementDisplayKind: String, Codable, CaseIterable, Hashable {
    case shoulder
    case chest
    case totalLength = "total_length"
    case sleeveLength = "sleeve_length"
    case waist
    case hip
    case thigh
    case rise
    case hem
    case footLength = "foot_length"
    case underBust = "under_bust"
}

enum MeasurementUnit: String, Codable, Hashable {
    case centimeter = "cm"
}

enum MeasurementInputSource: String, Codable, Hashable {
    case importedSizeChart = "imported_size_chart"
    case transcribedSizeChart = "transcribed_size_chart"
    case userMeasured = "user_measured"
    case migratedLegacy = "migrated_legacy"
}

enum MeasurementEvidenceLevel: String, Codable, Hashable {
    case officialText = "official_text"
    case officialDiagram = "official_diagram"
    case fitmatchDefined = "fitmatch_defined"
    case unknown
}

enum MeasurementSemanticStatus: String, Codable, Hashable {
    case mapped
    case unknownDefinition = "unknown_definition"
    case legacyUnknown = "legacy_unknown"
}

enum MeasurementMigrationStatus: String, Codable, Hashable {
    case notStarted = "not_started"
    case inProgress = "in_progress"
    case completed
    case failed
}

extension MeasurementKind {
    var displayKind: MeasurementDisplayKind {
        switch self {
        case .shoulder: return .shoulder
        case .chest: return .chest
        case .totalLength: return .totalLength
        case .sleeveLength: return .sleeveLength
        case .waist: return .waist
        case .hip: return .hip
        case .thigh: return .thigh
        case .rise: return .rise
        case .hem: return .hem
        case .footLength: return .footLength
        case .underBust: return .underBust
        }
    }
}
