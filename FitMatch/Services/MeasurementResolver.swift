import Foundation

enum MeasurementResolver {
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
}
