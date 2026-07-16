import Foundation

enum MeasurementCode: String, Codable, CaseIterable, Hashable {
    case standardBodyChestCircumference = "standard_body_chest_circumference"
    case shoulderWidthSeamToSeam = "shoulder_width_seam_to_seam"
    case chestWidthPitToPit = "chest_width_pit_to_pit"
    case chestWidthUniqloBodyWidth = "chest_width_uniqlo_body_width"
    case bodyLengthHPSToHemFront = "body_length_hps_to_hem_front"
    case bodyLengthBackNeckToHem = "body_length_back_neck_to_hem"
    case bodyLengthMusinsaType5 = "body_length_musinsa_type_5"
    case bodyLengthMusinsaType20 = "body_length_musinsa_type_20"
    case bodyLengthMusinsaType21 = "body_length_musinsa_type_21"
    case bodyLengthUniqloBack = "body_length_uniqlo_back"
    case bodyLengthUniqloShirt = "body_length_uniqlo_shirt"
    case bodyLengthUniqloKnitFront = "body_length_uniqlo_knit_front"
    case sleeveShoulderSeamToCuff = "sleeve_shoulder_seam_to_cuff"
    case sleeveCenterBackToCuff = "sleeve_center_back_to_cuff"
    case sleeveRaglanNeckToCuff = "sleeve_raglan_neck_to_cuff"
    case waistWidthEdgeToEdge = "waist_width_edge_to_edge"
    case hipWidthAtWidest = "hip_width_at_widest"
    case thighWidthCrotchToOuter = "thigh_width_crotch_to_outer"
    case riseCrotchToWaistFront = "rise_crotch_to_waist_front"
    case hemWidthEdgeToEdge = "hem_width_edge_to_edge"
    case pantsOutseamWaistToHem = "pants_outseam_waist_to_hem"
    case pantsInseamCrotchToHem = "pants_inseam_crotch_to_hem"
    case skirtLengthWaistToHem = "skirt_length_waist_to_hem"
    case footLengthHeelToToe = "foot_length_heel_to_toe"
    case underBustWidthEdgeToEdge = "under_bust_width_edge_to_edge"
    case unknown
    case legacyUnknown = "legacy_unknown"
}

enum MeasurementDisplayKind: String, Codable, CaseIterable, Hashable {
    case unknown
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

struct SourceMeasurementMapping: Equatable {
    let code: MeasurementCode
    let evidence: MeasurementEvidenceLevel
    let mappingVersion: String
    let valueMultiplier: Double

    init(
        code: MeasurementCode,
        evidence: MeasurementEvidenceLevel,
        mappingVersion: String,
        valueMultiplier: Double = 1
    ) {
        self.code = code
        self.evidence = evidence
        self.mappingVersion = mappingVersion
        self.valueMultiplier = valueMultiplier
    }
}

enum MeasurementSourceMappingPolicy {
    static let musinsaVersion = "musinsa_actual_size_mapping_v6"
    static let uniqloVersion = "uniqlo_kr_size_chart_mapping_v5"

    static func musinsa(
        typeNumber: Int?,
        displayKind: MeasurementDisplayKind?,
        rawLabel: String? = nil,
        isTopCategory: Bool = false
    ) -> SourceMeasurementMapping? {
        let normalizedLabel = rawLabel?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let bottomTypes = [6, 23, 42]

        if let typeNumber, bottomTypes.contains(typeNumber) {
            switch displayKind {
            case .waist where isExplicitWidthLabel(normalizedLabel, subject: "허리"):
                return mapping(.waistWidthEdgeToEdge)
            case .hip where isExplicitWidthLabel(normalizedLabel, subject: "엉덩이")
                || isExplicitWidthLabel(normalizedLabel, subject: "힙"):
                return mapping(.hipWidthAtWidest)
            case .thigh:
                return mapping(.thighWidthCrotchToOuter)
            case .rise:
                return mapping(.riseCrotchToWaistFront)
            case .hem:
                return mapping(.hemWidthEdgeToEdge)
            case .totalLength where normalizedLabel.contains("인심") || normalizedLabel.contains("inseam"):
                return mapping(.pantsInseamCrotchToHem)
            case .totalLength where normalizedLabel.contains("총장"):
                return mapping(.pantsOutseamWaistToHem)
            default:
                return nil
            }
        }

        if typeNumber == 14,
           displayKind == .totalLength,
           normalizedLabel.contains("총장") {
            return mapping(.skirtLengthWaistToHem)
        }

        if isTopCategory,
           displayKind == .totalLength,
           normalizedLabel == "총장" {
            return SourceMeasurementMapping(
                code: .bodyLengthBackNeckToHem,
                evidence: .officialDiagram,
                mappingVersion: musinsaVersion
            )
        }

        switch (typeNumber, displayKind) {
        case (5, .shoulder), (20, .shoulder), (21, .shoulder):
            return SourceMeasurementMapping(
                code: .shoulderWidthSeamToSeam,
                evidence: .officialDiagram,
                mappingVersion: musinsaVersion
            )
        case (5, .chest), (20, .chest), (21, .chest):
            return SourceMeasurementMapping(
                code: .chestWidthPitToPit,
                evidence: .officialDiagram,
                mappingVersion: musinsaVersion
            )
        // Reversible previous mapping:
        // Musinsa top total length was mapped only for types 5, 20 and 21.
        // Replaced by the common top-length rule so all verified Musinsa top
        // measurements labeled "총장" use bodyLengthBackNeckToHem.
        // case (5, .totalLength): code = .bodyLengthMusinsaType5
        // case (20, .totalLength): code = .bodyLengthMusinsaType20
        // case (21, .totalLength): code = .bodyLengthMusinsaType21
        case (5, .sleeveLength), (20, .sleeveLength), (21, .sleeveLength):
            return SourceMeasurementMapping(
                code: .sleeveShoulderSeamToCuff,
                evidence: .officialDiagram,
                mappingVersion: musinsaVersion
            )
        case (11, .sleeveLength):
            return SourceMeasurementMapping(
                code: .sleeveRaglanNeckToCuff,
                evidence: .officialDiagram,
                mappingVersion: musinsaVersion
            )
        default:
            return nil
        }
    }

    private static func mapping(_ code: MeasurementCode) -> SourceMeasurementMapping {
        SourceMeasurementMapping(
            code: code,
            evidence: .officialDiagram,
            mappingVersion: musinsaVersion
        )
    }

    private static func isExplicitWidthLabel(_ label: String, subject: String) -> Bool {
        label.contains(subject) && (label.contains("단면") || label.contains("너비") || label.contains("width"))
    }

    static func uniqlo(rawCode: String) -> SourceMeasurementMapping? {
        let normalizedRawCode = rawCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        let code: MeasurementCode
        switch normalizedRawCode {
        case "shoulderwidth": code = .shoulderWidthSeamToSeam
        // Reversible previous mapping: "bodywidth" used .chestWidthUniqloBodyWidth.
        case "bodywidth": code = .chestWidthPitToPit
        // Reversible previous mappings:
        // "bodylengthback" used .bodyLengthUniqloBack.
        // "bodylength" used .bodyLengthUniqloShirt.
        // "knitbodylengthfront" used .bodyLengthUniqloKnitFront.
        case "bodylengthback", "bodylength", "knitbodylengthfront": code = .bodyLengthBackNeckToHem
        case "sleevelengthcb": code = .sleeveCenterBackToCuff
        case "waistproductsize":
            return SourceMeasurementMapping(
                code: .waistWidthEdgeToEdge,
                evidence: .officialText,
                mappingVersion: uniqloVersion,
                valueMultiplier: 0.5
            )
        case "hipproductsize":
            return SourceMeasurementMapping(
                code: .hipWidthAtWidest,
                evidence: .officialText,
                mappingVersion: uniqloVersion,
                valueMultiplier: 0.5
            )
        case "thigh": code = .thighWidthCrotchToOuter
        case "risinglength": code = .riseCrotchToWaistFront
        case "bottomwidth": code = .hemWidthEdgeToEdge
        case "inseam": code = .pantsInseamCrotchToHem
        default: return nil
        }
        return SourceMeasurementMapping(
            code: code,
            evidence: .officialText,
            mappingVersion: uniqloVersion
        )
    }
}

extension ClothingCategory {
    var isMusinsaTopCategory: Bool {
        serviceGroup == .top
    }
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
