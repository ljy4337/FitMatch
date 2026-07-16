import Foundation

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
            let mapping = mapping(for: kind, source: source, musinsaSleeveMethod: musinsaSleeveMethod)
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
                standardVersion: source == .fitmatchMeasured ? "fitmatch_standard_v1" : nil,
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

    static func guide(for kind: MeasurementKind, source: MeasurementEntrySource) -> String {
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
        switch kind {
        case .shoulder: return "옷을 평평하게 놓고 양쪽 어깨 봉제선 사이"
        case .chest: return "겨드랑이 바로 아래 양쪽 끝 사이"
        case .totalLength: return "가장 높은 어깨점부터 앞 밑단까지"
        case .sleeveLength: return "어깨 봉제선부터 소매 끝까지"
        case .waist: return "허리단 양쪽 끝 사이"
        case .hip: return "엉덩이에서 가장 넓은 지점의 양쪽 끝 사이"
        case .thigh: return "가랑이점부터 바깥쪽 끝까지"
        case .rise: return "앞 가랑이점부터 허리단 위까지"
        case .hem: return "밑단 양쪽 끝 사이"
        case .footLength: return "뒤꿈치 끝부터 발가락 끝까지"
        case .underBust: return "밑가슴 밴드 양쪽 끝 사이"
        }
    }

    private static func mapping(
        for kind: MeasurementKind,
        source: MeasurementEntrySource,
        musinsaSleeveMethod: MusinsaSleeveMeasurementMethod
    ) -> (code: MeasurementCode, evidence: MeasurementEvidenceLevel, status: MeasurementSemanticStatus) {
        let code: MeasurementCode?
        switch source {
        case .fitmatchMeasured:
            code = fitmatchCode(for: kind)
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

    private static func fitmatchCode(for kind: MeasurementKind) -> MeasurementCode {
        switch kind {
        case .shoulder: return .shoulderWidthSeamToSeam
        case .chest: return .chestWidthPitToPit
        case .totalLength: return .bodyLengthHPSToHemFront
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
            return rawLabels[kind]?.trimmed ?? kind.title
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
