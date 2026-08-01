import Foundation

enum MeasurementResolver {
    struct SourceDisplayRow: Identifiable {
        let id: UUID
        let title: String
        let valueText: String
    }

    struct GarmentSnapshot {
        private let measurements: GarmentMeasurements
        private let recordsByDisplayKind: [MeasurementDisplayKind?: [GarmentMeasurementRecord]]

        fileprivate init(
            measurements: GarmentMeasurements,
            records: [GarmentMeasurementRecord]
        ) {
            self.measurements = measurements
            self.recordsByDisplayKind = Dictionary(grouping: records, by: \.displayKind)
        }

        func title(for kind: MeasurementKind) -> String {
            MeasurementResolver.title(
                for: kind,
                measurementCodes: records(for: kind)
                    .filter(\.isComparable)
                    .map(\.measurementCode)
            )
        }

        func value(
            for kind: MeasurementKind,
            requiredCode: MeasurementCode? = nil
        ) -> Double? {
            let kindRecords = records(for: kind)
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

        private func records(for kind: MeasurementKind) -> [GarmentMeasurementRecord] {
            recordsByDisplayKind[MeasurementResolver.displayKind(for: kind)] ?? []
        }
    }

    static func snapshot(
        measurements: GarmentMeasurements,
        records: [GarmentMeasurementRecord]
    ) -> GarmentSnapshot {
        GarmentSnapshot(measurements: measurements, records: records)
    }

    static func sourceDisplayRows(
        records: [GarmentMeasurementRecord]
    ) -> [SourceDisplayRow] {
        let imported = records.filter {
            $0.inputSourceRawValue == MeasurementInputSource.importedSizeChart.rawValue
                || $0.inputSourceRawValue == MeasurementInputSource.transcribedSizeChart.rawValue
        }
        return imported
            .sorted {
                let lhsOrder = displayOrder($0.displayKind)
                let rhsOrder = displayOrder($1.displayKind)
                if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                return ($0.rawLabel, $0.id.uuidString) < ($1.rawLabel, $1.id.uuidString)
            }
            .map {
                SourceDisplayRow(
                    id: $0.id,
                    title: $0.rawLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? ($0.displayKind?.rawValue ?? "실측")
                        : $0.rawLabel,
                    valueText: sourceValueText(for: $0)
                )
            }
    }

    private static func sourceValueText(for record: GarmentMeasurementRecord) -> String {
        let raw = record.rawValueText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty {
            let lower = raw.lowercased()
            if lower.contains("cm") || lower.contains("mm") || lower.contains("inch") || lower.contains("인치") {
                return raw
            }
            return "\(raw) \(record.unitRawValue)"
        }
        return "\(record.value.cmText)"
    }

    private static func displayOrder(_ kind: MeasurementDisplayKind?) -> Int {
        MeasurementDisplayKind.allCases.firstIndex(of: kind ?? .unknown) ?? Int.max
    }

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
        snapshot(measurements: measurements, records: records)
            .value(for: kind, requiredCode: requiredCode)
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
        case .upperAbdomen: .upperAbdomen
        case .upperWaist: .upperWaist
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
