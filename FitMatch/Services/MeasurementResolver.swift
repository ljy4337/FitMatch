import Foundation

enum MeasurementResolver {
    static func title(
        for kind: MeasurementKind,
        records: [GarmentMeasurementRecord]
    ) -> String {
        title(
            for: kind,
            measurementCodes: records
                .filter { $0.displayKind == displayKind(for: kind) && $0.isComparable }
                .map(\.measurementCode)
        )
    }

    static func title(
        for kind: MeasurementKind,
        records: [ParsedMeasurement]
    ) -> String {
        title(
            for: kind,
            measurementCodes: records
                .filter {
                    $0.displayKind == displayKind(for: kind)
                        && $0.semanticStatus == .mapped
                        && $0.measurementCode != .unknown
                        && $0.measurementCode != .legacyUnknown
                }
                .map(\.measurementCode)
        )
    }

    static func value(
        for kind: MeasurementKind,
        measurements: GarmentMeasurements,
        records: [GarmentMeasurementRecord],
        requiredCode: MeasurementCode? = nil
    ) -> Double? {
        let kindRecords = records.filter { $0.displayKind == displayKind(for: kind) }
        let mapped = kindRecords.filter {
            $0.isComparable && (requiredCode == nil || $0.measurementCode == requiredCode)
        }
        if requiredCode != nil {
            return mapped.count == 1 ? mapped[0].value : nil
        }
        if mapped.count == 1 { return mapped[0].value }
        if !kindRecords.isEmpty { return nil }
        let legacy = measurements.value(for: kind)
        return legacy.isFinite && legacy > 0 ? legacy : nil
    }

    static func value(
        for kind: MeasurementKind,
        measurements: GarmentMeasurements,
        records: [ParsedMeasurement]
    ) -> Double? {
        let kindRecords = records.filter { $0.displayKind == displayKind(for: kind) }
        let mapped = kindRecords.filter {
            $0.value.isFinite && $0.value > 0
                && $0.measurementCode != .unknown
                && $0.measurementCode != .legacyUnknown
                && $0.semanticStatus == .mapped
        }
        if mapped.count == 1 { return mapped[0].value }
        if !kindRecords.isEmpty { return nil }
        let legacy = measurements.value(for: kind)
        return legacy.isFinite && legacy > 0 ? legacy : nil
    }

    static func displayKind(for kind: MeasurementKind) -> MeasurementDisplayKind {
        switch kind {
        case .shoulder: .shoulder
        case .chest: .chest
        case .totalLength: .totalLength
        case .sleeveLength: .sleeveLength
        case .waist: .waist
        case .hip: .hip
        case .thigh: .thigh
        case .rise: .rise
        case .hem: .hem
        case .footLength: .footLength
        case .underBust: .underBust
        }
    }

    private static func title(
        for kind: MeasurementKind,
        measurementCodes: [MeasurementCode]
    ) -> String {
        guard Set(measurementCodes).count == 1, let code = measurementCodes.first else {
            return kind.title
        }
        switch code {
        case .chestCircumferenceGarment:
            return "가슴둘레"
        case .waistCircumferenceGarment:
            return "허리둘레"
        case .sleeveCenterBackToCuff:
            return "화장"
        default:
            return kind.title
        }
    }
}
