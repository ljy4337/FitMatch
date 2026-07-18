import Foundation

enum MeasurementCode: String, Codable, CaseIterable, Hashable {
    case standardBodyChestCircumference = "standard_body_chest_circumference"
    case shoulderWidthSeamToSeam = "shoulder_width_seam_to_seam"
    case chestWidthPitToPit = "chest_width_pit_to_pit"
    case chestCircumferenceGarment = "chest_circumference_garment"
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
    case waistCircumferenceGarment = "waist_circumference_garment"
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
    static let musinsaVersion = "musinsa_actual_size_mapping_v8"
    static let uniqloVersion = "uniqlo_kr_size_chart_mapping_v6"

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
        let setInTypes = [5, 7, 8, 9, 10, 20, 21, 38]
        let raglanTypes = [11, 22, 31]
        let sleevelessTypes = [24, 25]

        if let typeNumber, bottomTypes.contains(typeNumber) {
            switch displayKind {
            case .waist where isExactWidthLabel(normalizedLabel, labels: ["허리단면", "허리너비"]):
                return mapping(.waistWidthEdgeToEdge)
            case .hip where isExactWidthLabel(normalizedLabel, labels: ["엉덩이단면", "엉덩이너비", "힙단면", "힙너비"]):
                return mapping(.hipWidthAtWidest)
            case .thigh where isExactWidthLabel(normalizedLabel, labels: ["허벅지단면", "허벅지너비"]):
                return mapping(.thighWidthCrotchToOuter)
            case .rise where normalizedLabel == "밑위":
                return mapping(.riseCrotchToWaistFront)
            case .hem where isExactWidthLabel(normalizedLabel, labels: ["밑단단면", "밑단너비"]):
                return mapping(.hemWidthEdgeToEdge)
            case .totalLength where normalizedLabel == "인심" || normalizedLabel == "inseam":
                return mapping(.pantsInseamCrotchToHem)
            case .totalLength where normalizedLabel == "총장":
                return mapping(.pantsOutseamWaistToHem)
            default:
                return nil
            }
        }

        if typeNumber == 14 {
            switch displayKind {
            case .totalLength where normalizedLabel == "총장":
                return mapping(.skirtLengthWaistToHem)
            case .waist where isExactWidthLabel(normalizedLabel, labels: ["허리단면", "허리너비"]):
                return mapping(.waistWidthEdgeToEdge)
            case .hip where isExactWidthLabel(normalizedLabel, labels: ["엉덩이단면", "엉덩이너비", "힙단면", "힙너비"]):
                return mapping(.hipWidthAtWidest)
            case .hem where isExactWidthLabel(normalizedLabel, labels: ["밑단단면", "밑단너비"]):
                return mapping(.hemWidthEdgeToEdge)
            default:
                return nil
            }
        }

        if typeNumber == 19 {
            switch displayKind {
            case .waist where isExactWidthLabel(normalizedLabel, labels: ["허리단면", "허리너비"]):
                return mapping(.waistWidthEdgeToEdge)
            case .hip where isExactWidthLabel(normalizedLabel, labels: ["엉덩이단면", "엉덩이너비", "힙단면", "힙너비"]):
                return mapping(.hipWidthAtWidest)
            default:
                return nil
            }
        }

        // Reversible previous mapping:
        // Exact "총장" previously depended on isTopCategory, while shoulder/chest/sleeve
        // were limited to types 5, 20 and 21 and raglan sleeve to type 11.
        // Official type diagrams now drive all mappings; category inference is metadata only.
        // case (5, .totalLength): code = .bodyLengthMusinsaType5
        // case (20, .totalLength): code = .bodyLengthMusinsaType20
        // case (21, .totalLength): code = .bodyLengthMusinsaType21

        guard let typeNumber else { return nil }
        if setInTypes.contains(typeNumber) {
            switch displayKind {
            case .totalLength where normalizedLabel == "총장": return mapping(.bodyLengthBackNeckToHem)
            case .shoulder where normalizedLabel == "어깨너비": return mapping(.shoulderWidthSeamToSeam)
            case .chest where normalizedLabel == "가슴단면": return mapping(.chestWidthPitToPit)
            case .sleeveLength: return mapping(.sleeveShoulderSeamToCuff)
            case .hip where typeNumber == 38
                && isExactWidthLabel(normalizedLabel, labels: ["엉덩이단면", "엉덩이너비", "힙단면", "힙너비"]):
                return mapping(.hipWidthAtWidest)
            default: return nil
            }
        }
        if raglanTypes.contains(typeNumber) {
            switch displayKind {
            case .totalLength where normalizedLabel == "총장": return mapping(.bodyLengthBackNeckToHem)
            case .chest where normalizedLabel == "가슴단면": return mapping(.chestWidthPitToPit)
            case .sleeveLength: return mapping(.sleeveRaglanNeckToCuff)
            default: return nil
            }
        }
        if sleevelessTypes.contains(typeNumber) {
            switch displayKind {
            case .totalLength where normalizedLabel == "총장": return mapping(.bodyLengthBackNeckToHem)
            case .shoulder where normalizedLabel == "어깨너비": return mapping(.shoulderWidthSeamToSeam)
            case .chest where normalizedLabel == "가슴단면": return mapping(.chestWidthPitToPit)
            default: return nil
            }
        }
        return nil
    }

    private static func mapping(_ code: MeasurementCode) -> SourceMeasurementMapping {
        SourceMeasurementMapping(
            code: code,
            evidence: .officialDiagram,
            mappingVersion: musinsaVersion
        )
    }

    private static func isExactWidthLabel(_ label: String, labels: [String]) -> Bool {
        labels.contains(label)
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
        case "sleevelength": code = .sleeveShoulderSeamToCuff
        case "sleevelengthcb": code = .sleeveCenterBackToCuff
        case "skirtlength": code = .skirtLengthWaistToHem
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

    var isMusinsaUpperBodyCategory: Bool {
        serviceGroup == .top || serviceGroup == .outer
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
