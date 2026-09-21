import Foundation

/// View-lifetime memo for read-only supplemental presentation. Never authorizes
/// comparisons or persists results. The existing engine remains the sole calculator.
@MainActor
final class FitMatchResultSupplementalComparisonCache {
    private var previousInput: Input?
    private var previousResult: MeasurementComparisonResult?
    private(set) var computationCount = 0

    func comparison(
        productSize: ProductSize,
        referenceItem: UserFit,
        productCategory: ClothingCategory,
        productDetailCategory: ClosetDetailCategory
    ) -> MeasurementComparisonResult {
        let input = Input(
            sizeID: productSize.id,
            referenceID: referenceItem.id,
            category: productCategory,
            detailCategory: productDetailCategory,
            productRecords: productSize.measurementRecords.map(Record.init),
            referenceRecords: referenceItem.measurementRecords.map(Record.init)
        )
        if previousInput == input, let previousResult { return previousResult }
        let result = MeasurementComparisonEngine().compare(
            productSize: productSize,
            referenceItem: referenceItem,
            productCategory: productCategory,
            productDetailCategory: productDetailCategory
        )
        previousInput = input
        previousResult = result
        computationCount += 1
        return result
    }

    private struct Input: Equatable {
        let sizeID: UUID
        let referenceID: UUID
        let category: ClothingCategory
        let detailCategory: ClosetDetailCategory
        let productRecords: [Record]
        let referenceRecords: [Record]
    }

    /// Capture every persisted scalar of a measurement, including semantic and
    /// provenance fields. Do not use IDs/updatedAt alone: edits may retain both.
    private struct Record: Equatable {
        let id: UUID
        let value: Double
        let sourceIdentity: MeasurementSourceIdentity?
        let fields: [String?]
        let createdAt: Date
        let updatedAt: Date

        init(_ record: GarmentMeasurementRecord) {
            id = record.id
            value = record.value
            sourceIdentity = record.sourceIdentity
            fields = [
                record.unitRawValue, record.measurementCodeRawValue,
                record.displayKindRawValue, record.methodSource, record.methodProfile,
                record.inputSourceRawValue, record.standardVersion, record.mappingVersion,
                record.rawCode, record.rawLabel, record.rawInfo, record.rawValueText,
                record.evidenceLevelRawValue, record.semanticStatusRawValue
            ]
            createdAt = record.createdAt
            updatedAt = record.updatedAt
        }
    }
}
