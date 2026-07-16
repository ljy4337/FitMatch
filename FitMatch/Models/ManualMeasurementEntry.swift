import Foundation

struct DirectMeasurementDefinition: Equatable {
    let kind: MeasurementKind
    let instruction: String
    let caution: String
    let validRange: ClosedRange<Double>

    var standardVersion: String { FitMatchMeasurementStandard.version }

    var rangeDescription: String {
        "\(validRange.lowerBound.formatted())~\(validRange.upperBound.formatted())cm"
    }
}

enum FitMatchMeasurementStandard {
    static let version = "fitmatch_standard_v1"

    static func definition(
        for kind: MeasurementKind,
        category: ClothingCategory? = nil
    ) -> DirectMeasurementDefinition {
        if kind == .totalLength, category?.serviceGroup == .bottom {
            return definition(
                kind,
                "허리단 위쪽부터 바깥쪽 봉제선을 따라 밑단까지 측정",
                "가랑이부터 잰 인심 길이와는 비교할 수 없습니다.",
                20...160
            )
        }

        switch kind {
        case .shoulder:
            return definition(kind, "양쪽 어깨 봉제선의 가장 바깥점을 직선으로 측정", "어깨선이 없는 라글란 옷은 이 항목을 입력하지 마세요.", 10...90)
        case .chest:
            return definition(kind, "겨드랑이 바로 아래 양쪽 끝을 수평으로 측정", "둘레가 아닌 옷의 단면값을 입력하세요.", 15...100)
        case .totalLength:
            return definition(kind, "앞면의 가장 높은 어깨점부터 밑단까지 수직으로 측정", "옷깃과 후드 길이는 포함하지 마세요.", 15...180)
        case .sleeveLength:
            return definition(kind, "어깨 봉제선부터 소매 끝까지 소매선을 따라 측정", "목 중심부터 잰 화장과는 비교할 수 없습니다.", 3...110)
        case .waist:
            return definition(kind, "허리단을 자연스럽게 편 상태에서 양쪽 끝을 수평으로 측정", "허리둘레가 아닌 단면값을 입력하세요.", 15...90)
        case .hip:
            return definition(kind, "엉덩이 부분에서 가장 넓은 지점의 양쪽 끝을 측정", "주름을 펴되 원단을 늘리지 마세요.", 20...100)
        case .thigh:
            return definition(kind, "가랑이 봉제점 바로 아래부터 바깥쪽 끝까지 측정", "한쪽 다리의 단면값을 입력하세요.", 10...60)
        case .rise:
            return definition(kind, "앞면 가랑이 봉제점부터 허리단 위까지 측정", "뒷밑위가 아닌 앞밑위를 측정하세요.", 10...50)
        case .hem:
            return definition(kind, "한쪽 바짓단의 양쪽 끝을 수평으로 측정", "양쪽 바짓단을 합산하지 마세요.", 5...90)
        case .footLength:
            return definition(kind, "신발 안쪽의 뒤꿈치 끝부터 발가락 끝까지 측정", "발의 실측 길이와 신발 외부 길이를 입력하지 마세요.", 10...40)
        case .underBust:
            return definition(kind, "밑가슴 밴드를 편 상태에서 양쪽 끝을 수평으로 측정", "밑가슴둘레가 아닌 옷의 단면값을 입력하세요.", 15...80)
        }
    }

    private static func definition(
        _ kind: MeasurementKind,
        _ instruction: String,
        _ caution: String,
        _ validRange: ClosedRange<Double>
    ) -> DirectMeasurementDefinition {
        DirectMeasurementDefinition(
            kind: kind,
            instruction: instruction,
            caution: caution,
            validRange: validRange
        )
    }
}

enum MeasurementEntrySource: String, CaseIterable, Hashable, Identifiable {
    case musinsaSizeChart = "musinsa_size_chart"
    case uniqloSizeChart = "uniqlo_size_chart"
    case otherSizeChart = "other_size_chart"
    case fitmatchMeasured = "fitmatch_measured"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .musinsaSizeChart: return "무신사 사이즈표"
        case .uniqloSizeChart: return "유니클로 사이즈표"
        case .otherSizeChart: return "다른 쇼핑몰 사이즈표"
        case .fitmatchMeasured: return "내가 직접 측정했어요"
        }
    }

    var inputSource: MeasurementInputSource {
        self == .fitmatchMeasured ? .userMeasured : .transcribedSizeChart
    }

    static func infer(from records: [GarmentMeasurementRecord]) -> MeasurementEntrySource? {
        guard let first = records.first else { return nil }
        let inputSource = MeasurementInputSource(rawValue: first.inputSourceRawValue)
        if inputSource == .userMeasured || first.methodSource == "fitmatch" {
            return .fitmatchMeasured
        }
        guard inputSource == .transcribedSizeChart else { return nil }
        switch first.methodSource {
        case "musinsa": return .musinsaSizeChart
        case "uniqlo_kr": return .uniqloSizeChart
        case "other_size_chart": return .otherSizeChart
        default: return nil
        }
    }
}

enum MusinsaSleeveMeasurementMethod: String, CaseIterable, Hashable, Identifiable {
    case setIn = "set_in"
    case raglan
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .setIn: return "어깨선부터 소매 끝"
        case .raglan: return "목선부터 소매 끝"
        case .unknown: return "잘 모르겠어요"
        }
    }

    static func infer(from records: [GarmentMeasurementRecord]) -> MusinsaSleeveMeasurementMethod {
        let profile = records.first?.methodProfile ?? ""
        if profile.contains("raglan") { return .raglan }
        if profile.contains("set_in") { return .setIn }
        return .unknown
    }
}

enum ManualMeasurementRecordFactory {
    static func records(
        source: MeasurementEntrySource,
        musinsaSleeveMethod: MusinsaSleeveMeasurementMethod,
        measurements: GarmentMeasurements,
        rawValues: [MeasurementKind: String],
        rawLabels: [MeasurementKind: String],
        kinds: [MeasurementKind],
        otherSourceName: String,
        userFit: UserFit
    ) -> [GarmentMeasurementRecord] {
        kinds.compactMap { kind in
            let value = measurements.value(for: kind)
            guard value.isFinite, value > 0 else { return nil }
            let mapping = mapping(
                for: kind,
                source: source,
                musinsaSleeveMethod: musinsaSleeveMethod,
                category: userFit.category
            )
            return GarmentMeasurementRecord(
                value: value,
                measurementCode: mapping.code,
                displayKind: kind.displayKind,
                methodSource: methodSource(for: source),
                methodProfile: methodProfile(
                    for: source,
                    musinsaSleeveMethod: musinsaSleeveMethod,
                    otherSourceName: otherSourceName
                ),
                inputSource: source.inputSource,
                standardVersion: source == .fitmatchMeasured ? FitMatchMeasurementStandard.version : nil,
                mappingVersion: "manual_measurement_mapping_v1",
                rawCode: rawCode(for: kind, source: source),
                rawLabel: rawLabel(for: kind, source: source, rawLabels: rawLabels),
                rawInfo: source == .otherSizeChart ? "출처: \(otherSourceName)" : nil,
                rawValueText: rawValues[kind],
                evidenceLevel: mapping.evidence,
                semanticStatus: mapping.status,
                userFit: userFit
            )
        }
    }

    static func guide(
        for kind: MeasurementKind,
        source: MeasurementEntrySource,
        category: ClothingCategory? = nil
    ) -> String {
        guard source == .fitmatchMeasured else {
            switch source {
            case .uniqloSizeChart where kind == .sleeveLength:
                return "목 중심부터 소매 끝까지 표시된 값을 그대로 입력"
            case .musinsaSizeChart where kind == .sleeveLength:
                return "선택한 소매 측정 기준의 값을 그대로 입력"
            default:
                return "사이즈표에 표시된 값을 변환하지 않고 입력"
            }
        }
        return FitMatchMeasurementStandard.definition(for: kind, category: category).instruction
    }

    private static func mapping(
        for kind: MeasurementKind,
        source: MeasurementEntrySource,
        musinsaSleeveMethod: MusinsaSleeveMeasurementMethod,
        category: ClothingCategory
    ) -> (code: MeasurementCode, evidence: MeasurementEvidenceLevel, status: MeasurementSemanticStatus) {
        let code: MeasurementCode?
        switch source {
        case .fitmatchMeasured:
            code = fitmatchCode(for: kind, category: category)
        case .uniqloSizeChart:
            switch kind {
            case .shoulder: code = .shoulderWidthSeamToSeam
            case .sleeveLength: code = .sleeveCenterBackToCuff
            default: code = nil
            }
        case .musinsaSizeChart:
            switch (musinsaSleeveMethod, kind) {
            case (.setIn, .shoulder): code = .shoulderWidthSeamToSeam
            case (.setIn, .sleeveLength): code = .sleeveShoulderSeamToCuff
            case (.raglan, .sleeveLength): code = .sleeveRaglanNeckToCuff
            default: code = nil
            }
        case .otherSizeChart:
            code = nil
        }
        guard let code else { return (.unknown, .unknown, .unknownDefinition) }
        let evidence: MeasurementEvidenceLevel
        switch source {
        case .fitmatchMeasured: evidence = .fitmatchDefined
        case .uniqloSizeChart: evidence = .officialText
        case .musinsaSizeChart: evidence = .officialDiagram
        case .otherSizeChart: evidence = .unknown
        }
        return (code, evidence, .mapped)
    }

    private static func fitmatchCode(
        for kind: MeasurementKind,
        category: ClothingCategory
    ) -> MeasurementCode {
        switch kind {
        case .shoulder: return .shoulderWidthSeamToSeam
        case .chest: return .chestWidthPitToPit
        case .totalLength:
            return category.serviceGroup == .bottom
                ? .pantsOutseamWaistToHem
                : .bodyLengthHPSToHemFront
        case .sleeveLength: return .sleeveShoulderSeamToCuff
        case .waist: return .waistWidthEdgeToEdge
        case .hip: return .hipWidthAtWidest
        case .thigh: return .thighWidthCrotchToOuter
        case .rise: return .riseCrotchToWaistFront
        case .hem: return .hemWidthEdgeToEdge
        case .footLength: return .footLengthHeelToToe
        case .underBust: return .underBustWidthEdgeToEdge
        }
    }

    private static func methodSource(for source: MeasurementEntrySource) -> String {
        switch source {
        case .musinsaSizeChart: return "musinsa"
        case .uniqloSizeChart: return "uniqlo_kr"
        case .otherSizeChart: return "other_size_chart"
        case .fitmatchMeasured: return "fitmatch"
        }
    }

    private static func methodProfile(
        for source: MeasurementEntrySource,
        musinsaSleeveMethod: MusinsaSleeveMeasurementMethod,
        otherSourceName: String
    ) -> String {
        switch source {
        case .musinsaSizeChart: return "musinsa_manual_\(musinsaSleeveMethod.rawValue)"
        case .uniqloSizeChart: return "uniqlo_size_chart_manual"
        case .otherSizeChart: return "other_size_chart_manual:\(otherSourceName)"
        case .fitmatchMeasured: return "fitmatch_standard_v1"
        }
    }

    private static func rawCode(for kind: MeasurementKind, source: MeasurementEntrySource) -> String? {
        guard source == .uniqloSizeChart else { return nil }
        switch kind {
        case .shoulder: return "shoulder-width"
        case .chest: return "body-width"
        case .sleeveLength: return "sleeve-length-cb"
        default: return nil
        }
    }

    private static func rawLabel(
        for kind: MeasurementKind,
        source: MeasurementEntrySource,
        rawLabels: [MeasurementKind: String]
    ) -> String {
        if source == .otherSizeChart {
            let rawLabel = rawLabels[kind]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return rawLabel.isEmpty ? kind.title : rawLabel
        }
        guard source == .uniqloSizeChart else { return kind.title }
        switch kind {
        case .shoulder: return "어깨너비"
        case .chest: return "가슴너비"
        case .totalLength: return "전체 길이"
        case .sleeveLength: return "소매길이"
        default: return kind.title
        }
    }
}
