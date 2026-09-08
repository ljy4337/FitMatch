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
    case upperAbdomenWidthEdgeToEdge = "upper_abdomen_width_edge_to_edge"
    case upperWaistWidthEdgeToEdge = "upper_waist_width_edge_to_edge"
    case waistWidthEdgeToEdge = "waist_width_edge_to_edge"
    case waistCircumferenceGarment = "waist_circumference_garment"
    case hipWidthAtWidest = "hip_width_at_widest"
    case thighWidthCrotchToOuter = "thigh_width_crotch_to_outer"
    case riseCrotchToWaistFront = "rise_crotch_to_waist_front"
    case riseCrotchToWaistBack = "rise_crotch_to_waist_back"
    case hemWidthEdgeToEdge = "hem_width_edge_to_edge"
    case pantsOutseamWaistToHem = "pants_outseam_waist_to_hem"
    case pantsInseamCrotchToHem = "pants_inseam_crotch_to_hem"
    case skirtLengthWaistToHem = "skirt_length_waist_to_hem"
    case footLengthHeelToToe = "foot_length_heel_to_toe"
    case underBustWidthEdgeToEdge = "under_bust_width_edge_to_edge"
    case unknown
    case legacyUnknown = "legacy_unknown"
}

/// The public vNext Closet/runtime vocabulary is intentionally distinct from
/// the app's method-specific `MeasurementCode` vocabulary.  This adapter is
/// the one place where an equivalence has been explicitly verified; callers
/// must not infer a server code from a display name or a partial string.
///
/// `localCode` and `displayKind` are presentation/storage projections only.
/// The original `canonicalCode` stays on the measurement record so that two
/// facts which share a display axis (for example width and circumference) are
/// never merged into one measurement.
nonisolated struct FitMatchCanonicalMeasurementProjection: Equatable, Sendable {
    let canonicalCode: String
    let localCode: MeasurementCode
    let displayKind: MeasurementDisplayKind
}

nonisolated enum FitMatchCanonicalMeasurementCode {
    /// These are the current server comparison vocabulary.  Future server
    /// codes can still be retained as raw facts after hydration, but they are
    /// deliberately not assigned a local comparison/display meaning here.
    static let activeCodes: Set<String> = [
        "back_length",
        "chest_circumference",
        "chest_width",
        "front_rise",
        "hem_circumference",
        "hem_width",
        "hip_circumference",
        "hip_width",
        "outseam",
        "shoulder_width",
        "sleeve_length",
        "thigh_circumference",
        "thigh_width",
        "total_length",
        "under_bust_circumference",
        "under_bust_width",
        "waist_circumference",
        "waist_width"
    ]

    /// Projects one exact server-issued canonical code for local storage and
    /// UI.  No width/circumference conversion occurs here.
    static func projection(
        for canonicalCode: String,
        basisCode: String? = nil
    ) -> FitMatchCanonicalMeasurementProjection? {
        let code = canonicalCode.trimmingCharacters(in: .whitespacesAndNewlines)
        switch code {
        case "back_length":
            return projection(code, .bodyLengthBackNeckToHem, .totalLength)
        case "total_length":
            let localCode: MeasurementCode
            switch basisCode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "waist_to_skirt_hem":
                localCode = .skirtLengthWaistToHem
            case "waist_to_hem", "waist_to_outseam":
                localCode = .pantsOutseamWaistToHem
            default:
                localCode = .bodyLengthBackNeckToHem
            }
            return projection(code, localCode, .totalLength)
        case "outseam":
            return projection(code, .pantsOutseamWaistToHem, .totalLength)
        case "shoulder_width":
            return projection(code, .shoulderWidthSeamToSeam, .shoulder)
        case "chest_width":
            return projection(code, .chestWidthPitToPit, .chest)
        case "chest_circumference":
            return projection(code, .chestCircumferenceGarment, .chest)
        case "sleeve_length":
            let localCode: MeasurementCode
            switch basisCode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "sleeve_center_back_to_cuff":
                localCode = .sleeveCenterBackToCuff
            case "sleeve_raglan_neck_to_cuff":
                localCode = .sleeveRaglanNeckToCuff
            case "sleeve_shoulder_seam_to_cuff":
                localCode = .sleeveShoulderSeamToCuff
            default:
                // `sleeve_length` alone does not prove whether a retailer
                // measured from the shoulder seam, neck, or centre back.
                // Retain the canonical fact for the server-owned comparison
                // path, but do not turn an unspecified/raglan basis into a
                // shoulder-seam local measurement.
                localCode = .unknown
            }
            return projection(code, localCode, .sleeveLength)
        case "waist_width":
            return projection(code, .waistWidthEdgeToEdge, .waist)
        case "waist_circumference":
            return projection(code, .waistCircumferenceGarment, .waist)
        case "hip_width":
            return projection(code, .hipWidthAtWidest, .hip)
        case "thigh_width":
            return projection(code, .thighWidthCrotchToOuter, .thigh)
        case "front_rise":
            return projection(code, .riseCrotchToWaistFront, .rise)
        case "hem_width":
            return projection(code, .hemWidthEdgeToEdge, .hem)
        case "under_bust_width":
            return projection(code, .underBustWidthEdgeToEdge, .underBust)
        // The app has no exact local semantic code for these circumference
        // facts.  Preserve their original code/value/unit but do not project
        // them onto the corresponding width axis.
        case "hem_circumference", "hip_circumference", "thigh_circumference",
             "under_bust_circumference":
            return projection(code, .unknown, .unknown)
        default:
            return nil
        }
    }

    /// Maps an app-local measurement code to the one verified server code
    /// with the same meaning.  A nil result is a contract error at the
    /// transport boundary, never a reason to silently drop a positive value.
    static func canonicalCode(for localCode: MeasurementCode) -> String? {
        switch localCode {
        case .shoulderWidthSeamToSeam:
            return "shoulder_width"
        case .chestWidthPitToPit, .chestWidthUniqloBodyWidth:
            return "chest_width"
        case .chestCircumferenceGarment:
            return "chest_circumference"
        case .bodyLengthHPSToHemFront, .bodyLengthUniqloKnitFront,
             .skirtLengthWaistToHem:
            return "total_length"
        case .bodyLengthBackNeckToHem, .bodyLengthMusinsaType5,
             .bodyLengthMusinsaType20, .bodyLengthMusinsaType21,
             .bodyLengthUniqloBack, .bodyLengthUniqloShirt:
            return "back_length"
        case .sleeveShoulderSeamToCuff:
            return "sleeve_length"
        case .waistWidthEdgeToEdge:
            return "waist_width"
        case .waistCircumferenceGarment:
            return "waist_circumference"
        case .hipWidthAtWidest:
            return "hip_width"
        case .thighWidthCrotchToOuter:
            return "thigh_width"
        case .riseCrotchToWaistFront:
            return "front_rise"
        case .hemWidthEdgeToEdge:
            return "hem_width"
        case .pantsOutseamWaistToHem:
            return "outseam"
        case .underBustWidthEdgeToEdge:
            return "under_bust_width"
        case .standardBodyChestCircumference,
             .sleeveCenterBackToCuff,
             .sleeveRaglanNeckToCuff,
             .upperAbdomenWidthEdgeToEdge,
             .upperWaistWidthEdgeToEdge,
             .riseCrotchToWaistBack,
             .pantsInseamCrotchToHem,
             .footLengthHeelToToe,
             .unknown,
             .legacyUnknown:
            return nil
        }
    }

    /// Exact compatibility for rows that pre-date measurement records.  The
    /// aliases are historical field names, not a string-pattern fallback.
    static func canonicalCode(forTransportRawCode rawCode: String) -> String? {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if activeCodes.contains(code) { return code }
        if let localCode = MeasurementCode(rawValue: code),
           let canonical = canonicalCode(for: localCode) {
            return canonical
        }
        switch code {
        case "body_length": return "back_length"
        case "rise": return "front_rise"
        case "pants_outseam": return "outseam"
        default: return nil
        }
    }

    private static func projection(
        _ canonicalCode: String,
        _ localCode: MeasurementCode,
        _ displayKind: MeasurementDisplayKind
    ) -> FitMatchCanonicalMeasurementProjection {
        FitMatchCanonicalMeasurementProjection(
            canonicalCode: canonicalCode,
            localCode: localCode,
            displayKind: displayKind
        )
    }
}

extension MeasurementCode {
    /// Presentation-only counterpart to the method-specific local code. This
    /// retains established legacy Closet labels without treating an unknown
    /// future server identifier as a guessed comparison axis.
    nonisolated var presentationDisplayKind: MeasurementDisplayKind? {
        switch self {
        case .standardBodyChestCircumference,
             .chestWidthPitToPit,
             .chestCircumferenceGarment,
             .chestWidthUniqloBodyWidth:
            return .chest
        case .shoulderWidthSeamToSeam:
            return .shoulder
        case .bodyLengthHPSToHemFront,
             .bodyLengthBackNeckToHem,
             .bodyLengthMusinsaType5,
             .bodyLengthMusinsaType20,
             .bodyLengthMusinsaType21,
             .bodyLengthUniqloBack,
             .bodyLengthUniqloShirt,
             .bodyLengthUniqloKnitFront,
             .pantsOutseamWaistToHem,
             .pantsInseamCrotchToHem,
             .skirtLengthWaistToHem:
            return .totalLength
        case .sleeveShoulderSeamToCuff,
             .sleeveCenterBackToCuff,
             .sleeveRaglanNeckToCuff:
            return .sleeveLength
        case .upperAbdomenWidthEdgeToEdge:
            return .upperAbdomen
        case .upperWaistWidthEdgeToEdge:
            return .upperWaist
        case .waistWidthEdgeToEdge, .waistCircumferenceGarment:
            return .waist
        case .hipWidthAtWidest:
            return .hip
        case .thighWidthCrotchToOuter:
            return .thigh
        case .riseCrotchToWaistFront, .riseCrotchToWaistBack:
            return .rise
        case .hemWidthEdgeToEdge:
            return .hem
        case .footLengthHeelToToe:
            return .footLength
        case .underBustWidthEdgeToEdge:
            return .underBust
        case .unknown, .legacyUnknown:
            return nil
        }
    }
}

extension MeasurementCode {
    var comparisonDefinition: String? {
        switch self {
        case .standardBodyChestCircumference: return "신체 가슴둘레"
        case .shoulderWidthSeamToSeam: return "양쪽 어깨 봉제선 사이"
        case .chestWidthPitToPit, .chestWidthUniqloBodyWidth: return "겨드랑이 사이 가슴 단면"
        case .chestCircumferenceGarment: return "옷의 가슴둘레"
        case .bodyLengthHPSToHemFront: return "어깨 최고점부터 앞 밑단까지"
        case .bodyLengthBackNeckToHem, .bodyLengthMusinsaType5,
             .bodyLengthMusinsaType20, .bodyLengthMusinsaType21,
             .bodyLengthUniqloBack, .bodyLengthUniqloShirt:
            return "뒤 목점부터 밑단까지"
        case .bodyLengthUniqloKnitFront: return "앞 목점부터 밑단까지"
        case .sleeveShoulderSeamToCuff: return "어깨 봉제선부터 소매 끝까지"
        case .sleeveCenterBackToCuff: return "등 중심부터 소매 끝까지"
        case .sleeveRaglanNeckToCuff: return "목점부터 소매 끝까지(래글런)"
        case .upperAbdomenWidthEdgeToEdge: return "복부 단면"
        case .upperWaistWidthEdgeToEdge, .waistWidthEdgeToEdge: return "허리 단면"
        case .waistCircumferenceGarment: return "옷의 허리둘레"
        case .hipWidthAtWidest: return "엉덩이 최대 단면"
        case .thighWidthCrotchToOuter: return "밑위점부터 바깥선까지 허벅지 단면"
        case .riseCrotchToWaistFront: return "앞 밑위"
        case .riseCrotchToWaistBack: return "뒤 밑위"
        case .hemWidthEdgeToEdge: return "밑단 단면"
        case .pantsOutseamWaistToHem: return "허리부터 밑단까지 바깥쪽 총장"
        case .pantsInseamCrotchToHem: return "밑위부터 밑단까지 안쪽 길이"
        case .skirtLengthWaistToHem: return "허리부터 밑단까지 스커트 길이"
        case .footLengthHeelToToe: return "뒤꿈치부터 발끝까지"
        case .underBustWidthEdgeToEdge: return "밑가슴 단면"
        case .unknown, .legacyUnknown: return nil
        }
    }
}

enum MeasurementDisplayKind: String, Codable, CaseIterable, Hashable {
    case unknown
    case shoulder
    case chest
    case totalLength = "total_length"
    case sleeveLength = "sleeve_length"
    case upperAbdomen = "upper_abdomen"
    case upperWaist = "upper_waist"
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
    static let uniqloVersion = "uniqlo_kr_size_chart_mapping_v7"

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

        if isTopCategory {
            switch displayKind {
            case .upperAbdomen where normalizedLabel == "복부단면":
                return mapping(.upperAbdomenWidthEdgeToEdge)
            case .upperWaist where normalizedLabel == "허리단면":
                return mapping(.upperWaistWidthEdgeToEdge)
            default:
                break
            }
        }

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
        case "waistproductsize", "waistproductsizebottoms":
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
    nonisolated var displayKind: MeasurementDisplayKind {
        switch self {
        case .shoulder: return .shoulder
        case .chest: return .chest
        case .totalLength: return .totalLength
        case .sleeveLength: return .sleeveLength
        case .upperAbdomen: return .upperAbdomen
        case .upperWaist: return .upperWaist
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
