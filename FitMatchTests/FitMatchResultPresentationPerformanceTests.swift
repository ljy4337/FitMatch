import Foundation
import Testing
@testable import FitMatch

@MainActor
struct FitMatchResultPresentationPerformanceTests {
    @Test func repeatedPresentationReusesExactlyEquivalentComparison() {
        let (size, reference) = fixture()
        let cache = FitMatchResultSupplementalComparisonCache()
        let expected = fresh(size, reference)
        for _ in 0..<100 {
            #expect(cache.comparison(productSize: size, referenceItem: reference,
                productCategory: .top, productDetailCategory: .shortSleeve) == expected)
        }
        #expect(cache.computationCount == 1)
        #expect(size.measurementRecords[0].value == 50)
        #expect(reference.measurementRecords[0].value == 52)
    }

    @Test func sameIdentityEditsInvalidateValuesSemanticsAndProvenance() {
        let (size, reference) = fixture()
        let cache = FitMatchResultSupplementalComparisonCache()
        func check() {
            #expect(cache.comparison(productSize: size, referenceItem: reference,
                productCategory: .top, productDetailCategory: .shortSleeve) == fresh(size, reference))
        }
        check()
        size.measurementRecords[0].value = 55
        check()
        reference.measurementRecords[0].semanticStatusRawValue = MeasurementSemanticStatus.unknownDefinition.rawValue
        check()
        reference.measurementRecords[0].rawLabel = "new definition"
        check()
        reference.sourcePlatformCode = "zara"
        check()
        #expect(cache.computationCount == 5)
    }

    @Test func sizeIdentityAndCategoryChangesNeverReusePreviousEntry() {
        let (size, reference) = fixture()
        let cache = FitMatchResultSupplementalComparisonCache()
        _ = cache.comparison(productSize: size, referenceItem: reference,
            productCategory: .top, productDetailCategory: .shortSleeve)
        size.id = UUID()
        _ = cache.comparison(productSize: size, referenceItem: reference,
            productCategory: .top, productDetailCategory: .shortSleeve)
        let changed = cache.comparison(productSize: size, referenceItem: reference,
            productCategory: .top, productDetailCategory: .longSleeve)
        #expect(changed == MeasurementComparisonEngine().compare(productSize: size,
            referenceItem: reference, productCategory: .top, productDetailCategory: .longSleeve))
        #expect(cache.computationCount == 3)
    }

    @Test func temporarySnapshotMatchesExistingCalculationForEveryRead() {
        let (size, reference) = fixture()
        let comparison = fresh(size, reference)
        let analysis = TemporarySizeAnalysis(productSize: size, comparisonResult: comparison,
            recommendationScore: comparison.score, comparisonSummary: nil)
        for _ in 0..<100 {
            #expect(analysis.calculationSnapshot == RecommendationCalculationSnapshot.make(comparison: comparison))
        }
        #expect(analysis.productSize.id == size.id)
        #expect(analysis.comparisonResult == comparison)
        #expect(analysis.recommendationScore == comparison.score)
    }

    private func fresh(_ size: ProductSize, _ reference: UserFit) -> MeasurementComparisonResult {
        MeasurementComparisonEngine().compare(productSize: size, referenceItem: reference,
            productCategory: .top, productDetailCategory: .shortSleeve)
    }

    private func fixture() -> (ProductSize, UserFit) {
        let measures = GarmentMeasurements(shoulder: 0, chest: 50, totalLength: 0, sleeveLength: 0)
        let size = ProductSize(name: "M", measurements: measures)
        let reference = UserFit(brandName: "Test", productName: "Long sleeve", category: .top,
            detailCategory: .longSleeve, sizeName: "L", measurements: measures,
            fitMemo: "", satisfaction: 3)
        reference.sourcePlatformCode = "uniqlo"
        let target = record(50)
        target.productSize = size
        size.measurementRecords = [target]
        let owned = record(52)
        owned.userFit = reference
        reference.measurementRecords = [owned]
        return (size, reference)
    }

    private func record(_ value: Double) -> GarmentMeasurementRecord {
        GarmentMeasurementRecord(value: value, measurementCode: .chestWidthPitToPit,
            displayKind: .chest, methodSource: "uniqlo", inputSource: .importedSizeChart,
            mappingVersion: "test", rawCode: "chest", rawLabel: "가슴단면",
            evidenceLevel: .officialText, semanticStatus: .mapped)
    }
}
