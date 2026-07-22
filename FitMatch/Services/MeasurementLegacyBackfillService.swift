import Foundation
import SwiftData

@MainActor
enum MeasurementLegacyBackfillService {
    static let migrationVersion = 9
    static let mappingVersion = "legacy_backfill_v9"

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
        let canonicalRecords = nonLegacyRecords(in: size.measurementRecords)
        removePreviousBackfillRecords(size.measurementRecords, modelContext: modelContext)
        if canonicalRecords.isEmpty {
            let records = MeasurementLegacyBackfillFactory.records(for: size, product: product)
            for record in records {
                record.productSize = size
                modelContext.insert(record)
            }
        } else {
            let convertedValues = upgradeSourceMappings(
                in: canonicalRecords,
                isTopCategory: product.category.isMusinsaUpperBodyCategory
            )
            applyConvertedValues(convertedValues, to: &size.measurements)
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
        let canonicalRecords = nonLegacyRecords(in: item.measurementRecords)
        removePreviousBackfillRecords(item.measurementRecords, modelContext: modelContext)
        if canonicalRecords.isEmpty {
            let records = MeasurementLegacyBackfillFactory.records(for: item)
            for record in records {
                record.userFit = item
                modelContext.insert(record)
            }
        } else {
            let convertedValues = upgradeSourceMappings(
                in: canonicalRecords,
                isTopCategory: item.category.isMusinsaUpperBodyCategory
            )
            applyConvertedValues(convertedValues, to: &item.measurements)
        }
        item.measurementSchemaVersion = 1
        item.measurementInputSourceRawValue = canonicalRecords.first?.inputSourceRawValue
            ?? MeasurementInputSource.migratedLegacy.rawValue
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

    private static func nonLegacyRecords(
        in records: [GarmentMeasurementRecord]
    ) -> [GarmentMeasurementRecord] {
        records.filter {
            $0.inputSourceRawValue != MeasurementInputSource.migratedLegacy.rawValue
        }
    }

    private static func upgradeSourceMappings(
        in records: [GarmentMeasurementRecord],
        isTopCategory: Bool
    ) -> [MeasurementDisplayKind: Double] {
        var convertedValues: [MeasurementDisplayKind: Double] = [:]
        for record in records {
            let migratedCommonCode = commonCodeReplacingLegacyPlatformCode(
                record,
                isTopCategory: isTopCategory
            )
            let mapping: SourceMeasurementMapping?
            switch record.methodSource {
            case "uniqlo_kr":
                mapping = record.rawCode.flatMap {
                    MeasurementSourceMappingPolicy.uniqlo(rawCode: $0)
                }
            case "musinsa":
                let typeNumber = record.methodProfile
                    .flatMap { profile -> Int? in
                        guard profile.hasPrefix("musinsa_type_") else { return nil }
                        return Int(profile.dropFirst("musinsa_type_".count))
                    }
                mapping = MeasurementSourceMappingPolicy.musinsa(
                    typeNumber: typeNumber,
                    displayKind: record.displayKind,
                    rawLabel: record.rawLabel,
                    isTopCategory: isTopCategory
                )
            default:
                mapping = nil
            }

            guard mapping != nil || migratedCommonCode != nil else { continue }
            let alreadyNormalizedPlatformValue =
                record.mappingVersion == mapping?.mappingVersion
                || (record.methodSource == "uniqlo_kr"
                    && record.mappingVersion == "uniqlo_kr_size_chart_mapping_v5")
            if let mapping,
               mapping.valueMultiplier != 1,
               !alreadyNormalizedPlatformValue {
                record.value *= mapping.valueMultiplier
                if let displayKind = record.displayKind {
                    convertedValues[displayKind] = record.value
                }
            }
            record.measurementCodeRawValue = (mapping?.code ?? migratedCommonCode ?? record.measurementCode).rawValue
            if let mapping {
                record.evidenceLevelRawValue = mapping.evidence.rawValue
                record.mappingVersion = mapping.mappingVersion
            } else {
                record.mappingVersion = mappingVersion
            }
            record.semanticStatusRawValue = MeasurementSemanticStatus.mapped.rawValue
            record.updatedAt = Date()
        }
        return convertedValues
    }

    private static func applyConvertedValues(
        _ values: [MeasurementDisplayKind: Double],
        to measurements: inout GarmentMeasurements
    ) {
        if let waist = values[.waist] { measurements.waist = waist }
        if let hip = values[.hip] { measurements.hip = hip }
    }

    private static func commonCodeReplacingLegacyPlatformCode(
        _ record: GarmentMeasurementRecord,
        isTopCategory: Bool
    ) -> MeasurementCode? {
        switch record.measurementCode {
        case .chestWidthUniqloBodyWidth:
            return .chestWidthPitToPit
        case .bodyLengthUniqloBack,
             .bodyLengthUniqloShirt,
             .bodyLengthUniqloKnitFront:
            return .bodyLengthBackNeckToHem
        case .bodyLengthMusinsaType5,
             .bodyLengthMusinsaType20,
             .bodyLengthMusinsaType21:
            return isVerifiedLegacyMusinsaTopTotalLength(record)
                ? .bodyLengthBackNeckToHem
                : nil
        default:
            return nil
        }
    }

    private static func isVerifiedLegacyMusinsaTopTotalLength(
        _ record: GarmentMeasurementRecord
    ) -> Bool {
        record.methodSource == "musinsa"
            && record.displayKind == .totalLength
            && record.rawLabel.trimmingCharacters(in: .whitespacesAndNewlines) == "총장"
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
            let mapping = musinsaMapping(
                kind: legacy.kind,
                sizeType: profile,
                isTopCategory: product.category.isMusinsaUpperBodyCategory
            )
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
        sizeType: String?,
        isTopCategory: Bool
    ) -> (code: MeasurementCode, evidence: MeasurementEvidenceLevel)? {
        guard let sizeType,
              let typeNumber = Int(sizeType),
              let mapping = MeasurementSourceMappingPolicy.musinsa(
                  typeNumber: typeNumber,
                  displayKind: kind.displayKind,
                  rawLabel: officialMusinsaLegacyLabel(for: kind),
                  isTopCategory: isTopCategory
              ) else { return nil }
        return (mapping.code, mapping.evidence)
    }

    private static func officialMusinsaLegacyLabel(for kind: MeasurementKind) -> String? {
        switch kind {
        case .totalLength: return "총장"
        case .shoulder: return "어깨너비"
        case .chest: return "가슴단면"
        case .sleeveLength: return "소매길이"
        case .waist: return "허리단면"
        case .hip: return "엉덩이단면"
        case .thigh: return "허벅지단면"
        case .rise: return "밑위"
        case .hem: return "밑단단면"
        case .underBust, .footLength: return nil
        }
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
