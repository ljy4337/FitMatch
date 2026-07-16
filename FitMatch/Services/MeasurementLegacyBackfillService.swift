import Foundation
import SwiftData

@MainActor
enum MeasurementLegacyBackfillService {
    static let migrationVersion = 2
    static let mappingVersion = "legacy_backfill_v2"

    static func run(
        modelContext: ModelContext,
        products: [Product],
        userFits: [UserFit]
    ) throws {
        do {
            for product in products {
                for size in product.sizes {
                    backfill(size, product: product, modelContext: modelContext)
                }
            }

            for item in userFits {
                if let sourceSize = item.sourceProductSize,
                   (sourceSize.measurementMigrationVersion < migrationVersion
                    || sourceSize.measurementMigrationStatus != .completed),
                   let sourceProduct = sourceSize.product ?? item.sourceProduct {
                    backfill(sourceSize, product: sourceProduct, modelContext: modelContext)
                }
                backfill(item, modelContext: modelContext)
            }

            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private static func backfill(
        _ size: ProductSize,
        product: Product,
        modelContext: ModelContext
    ) {
        guard size.measurementMigrationVersion < migrationVersion
            || size.measurementMigrationStatus != .completed else {
            return
        }

        size.measurementMigrationStatus = .inProgress
        removePreviousBackfillRecords(size.measurementRecords, modelContext: modelContext)
        let records = MeasurementLegacyBackfillFactory.records(for: size, product: product)
        for record in records {
            record.productSize = size
            modelContext.insert(record)
        }
        size.measurementSchemaVersion = 1
        size.measurementMigrationVersion = migrationVersion
        size.measurementMigrationStatus = .completed
        size.measurementMigrationErrorCode = nil
    }

    private static func backfill(
        _ item: UserFit,
        modelContext: ModelContext
    ) {
        guard item.measurementMigrationVersion < migrationVersion
            || item.measurementMigrationStatus != .completed else {
            return
        }

        item.measurementMigrationStatus = .inProgress
        removePreviousBackfillRecords(item.measurementRecords, modelContext: modelContext)
        let records = MeasurementLegacyBackfillFactory.records(for: item)
        for record in records {
            record.userFit = item
            modelContext.insert(record)
        }
        item.measurementSchemaVersion = 1
        item.measurementInputSourceRawValue = MeasurementInputSource.migratedLegacy.rawValue
        item.measurementMigrationVersion = migrationVersion
        item.measurementMigrationStatus = .completed
        item.measurementMigrationErrorCode = nil
    }

    private static func removePreviousBackfillRecords(
        _ records: [GarmentMeasurementRecord],
        modelContext: ModelContext
    ) {
        records
            .filter {
                $0.inputSourceRawValue == MeasurementInputSource.migratedLegacy.rawValue
                    && $0.mappingVersion.hasPrefix("legacy_backfill_v")
            }
            .forEach(modelContext.delete)
    }
}

enum MeasurementLegacyBackfillFactory {
    private struct LegacyValue {
        let kind: MeasurementKind
        let value: Double
    }

    static func records(for size: ProductSize, product: Product) -> [GarmentMeasurementRecord] {
        let platform = resolvedPlatformCode(for: product)
        let profile = platform == "musinsa" ? product.sizeType?.trimmingCharacters(in: .whitespacesAndNewlines) : nil

        return legacyValues(size.measurements).compactMap { legacy in
            guard legacy.value.isFinite, legacy.value > 0 else { return nil }
            let mapping = musinsaMapping(kind: legacy.kind, sizeType: profile)
            return makeRecord(
                value: legacy.value,
                kind: legacy.kind,
                code: mapping?.code ?? .legacyUnknown,
                methodSource: platformMethodSource(platform),
                methodProfile: profile.map { "musinsa_type_\($0)" },
                evidence: mapping?.evidence ?? .unknown,
                semanticStatus: mapping == nil ? .legacyUnknown : .mapped
            )
        }
    }

    static func records(for item: UserFit) -> [GarmentMeasurementRecord] {
        let sourceRecords = item.sourceProductSize?.measurementRecords ?? []
        let sourceValues = item.sourceProductSize?.measurements
        let platform = resolvedPlatformCode(for: item)

        return legacyValues(item.measurements).compactMap { legacy in
            guard legacy.value.isFinite, legacy.value > 0 else { return nil }
            let sourceValue = sourceValues?.value(for: legacy.kind) ?? 0
            let sourceRecord = sourceRecords.first {
                $0.displayKindRawValue == legacy.kind.displayKind.rawValue
                    && $0.isComparable
                    && abs(sourceValue - legacy.value) <= 0.0001
            }

            if let sourceRecord {
                return makeRecord(
                    value: legacy.value,
                    kind: legacy.kind,
                    code: sourceRecord.measurementCode,
                    methodSource: sourceRecord.methodSource,
                    methodProfile: sourceRecord.methodProfile,
                    evidence: MeasurementEvidenceLevel(rawValue: sourceRecord.evidenceLevelRawValue) ?? .unknown,
                    semanticStatus: .mapped
                )
            }

            return makeRecord(
                value: legacy.value,
                kind: legacy.kind,
                code: .legacyUnknown,
                methodSource: platformMethodSource(platform),
                methodProfile: nil,
                evidence: .unknown,
                semanticStatus: .legacyUnknown
            )
        }
    }

    private static func legacyValues(_ measurements: GarmentMeasurements) -> [LegacyValue] {
        MeasurementKind.allCases.map {
            LegacyValue(kind: $0, value: measurements.value(for: $0))
        }
    }

    private static func makeRecord(
        value: Double,
        kind: MeasurementKind,
        code: MeasurementCode,
        methodSource: String,
        methodProfile: String?,
        evidence: MeasurementEvidenceLevel,
        semanticStatus: MeasurementSemanticStatus
    ) -> GarmentMeasurementRecord {
        GarmentMeasurementRecord(
            value: value,
            measurementCode: code,
            displayKind: kind.displayKind,
            methodSource: methodSource,
            methodProfile: methodProfile,
            inputSource: .migratedLegacy,
            mappingVersion: MeasurementLegacyBackfillService.mappingVersion,
            rawLabel: "legacy_\(kind.displayKind.rawValue)",
            evidenceLevel: evidence,
            semanticStatus: semanticStatus
        )
    }

    private static func musinsaMapping(
        kind: MeasurementKind,
        sizeType: String?
    ) -> (code: MeasurementCode, evidence: MeasurementEvidenceLevel)? {
        guard let sizeType,
              let typeNumber = Int(sizeType),
              let mapping = MeasurementSourceMappingPolicy.musinsa(
                  typeNumber: typeNumber,
                  displayKind: kind.displayKind
              ) else { return nil }
        return (mapping.code, mapping.evidence)
    }

    private static func resolvedPlatformCode(for product: Product) -> String? {
        product.sourcePlatformCode ?? FitMatchTaxonomyProvider.shared.sourcePlatformCode(
            sourceName: product.sourceName,
            sourceURLString: product.sourceURLString
        )
    }

    private static func resolvedPlatformCode(for item: UserFit) -> String? {
        item.sourcePlatformCode
            ?? item.sourceProduct?.sourcePlatformCode
            ?? FitMatchTaxonomyProvider.shared.sourcePlatformCode(
                sourceName: item.sourceName,
                sourceURLString: item.sourceProduct?.sourceURLString
            )
    }

    private static func platformMethodSource(_ platform: String?) -> String {
        switch platform {
        case "musinsa": return "musinsa"
        case "uniqlo": return "uniqlo_kr"
        default: return "legacy_unknown"
        }
    }
}
