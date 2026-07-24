import Foundation
import Testing
@testable import FitMatch

@MainActor
struct BodyShapePreferencesTests {
    @Test func emptyPreferencesPreserveLegacyScoreAndIgnoreNewAbdomenRecords() {
        let fixture = upperFixture(includeAbdomen: true, includeUpperWaist: true)
        let engine = MeasurementComparisonEngine()
        let legacy = engine.compare(
            productSize: fixture.size,
            referenceItem: fixture.item,
            productCategory: .top,
            productDetailCategory: .shortSleeve
        )
        let explicitEmpty = engine.compare(
            productSize: fixture.size,
            referenceItem: fixture.item,
            productCategory: .top,
            productDetailCategory: .shortSleeve,
            bodyShapePreferences: .none
        )

        #expect(legacy == explicitEmpty)
        #expect(!legacy.comparedKinds.contains(.upperAbdomen))
        #expect(!legacy.comparedKinds.contains(.upperWaist))
    }

    @Test func broadShouldersAndDevelopedChestApplyExactlyOnceToTheirOwnWeights() throws {
        let fixture = upperFixture()
        let result = MeasurementComparisonEngine().compare(
            productSize: fixture.size,
            referenceItem: fixture.item,
            productCategory: .top,
            productDetailCategory: .shortSleeve,
            bodyShapePreferences: BodyShapePreferences(
                hasBroadShoulders: true,
                hasDevelopedChest: true
            )
        )

        #expect(try #require(result.comparedItems.first { $0.kind == .shoulder }).weight == 1.2 * 1.25)
        #expect(try #require(result.comparedItems.first { $0.kind == .chest }).weight == 1.4 * 1.25)
        #expect(try #require(result.comparedItems.first { $0.kind == .totalLength }).weight == 1.0)
    }

    @Test func oneAvailableAbdomenMeasurementReceivesWholeGroupWeight() throws {
        let fixture = upperFixture(includeAbdomen: true)
        let result = abdomenComparison(fixture)
        let abdomen = try #require(result.comparedItems.first { $0.kind == .upperAbdomen })

        #expect(abdomen.weight == 1.75)
        #expect(!result.comparedKinds.contains(.upperWaist))
    }

    @Test func twoAvailableAbdomenMeasurementsSplitButDoNotIncreaseGroupWeight() {
        let fixture = upperFixture(includeAbdomen: true, includeUpperWaist: true)
        let result = abdomenComparison(fixture)
        let abdomenItems = result.comparedItems.filter {
            $0.kind == .upperAbdomen || $0.kind == .upperWaist
        }

        #expect(abdomenItems.count == 2)
        #expect(abdomenItems.allSatisfy { $0.weight == 0.875 })
        #expect(abdomenItems.map(\.weight).reduce(0, +) == 1.75)
    }

    @Test func missingAbdomenMeasurementsDoNotInterruptExistingComparison() {
        let result = abdomenComparison(upperFixture())

        #expect(result.status == .confirmed)
        #expect(result.score.isMultiple(of: 1))
        #expect(result.comparedItems.allSatisfy { $0.weight.isFinite })
        #expect(!result.comparedKinds.contains(.upperAbdomen))
        #expect(!result.comparedKinds.contains(.upperWaist))
    }

    @Test func upperWaistNeverMatchesBottomWaist() {
        let fixture = upperFixture(includeUpperWaist: true)
        fixture.item.measurementRecords.removeAll { $0.displayKind == .upperWaist }
        fixture.item.measurementRecords.append(
            record(value: 49, code: .waistWidthEdgeToEdge, kind: .waist, userFit: fixture.item)
        )
        let result = abdomenComparison(fixture)

        #expect(!result.comparedKinds.contains(.upperWaist))
        #expect(!result.comparedKinds.contains(.waist))
        #expect(result.exclusions.contains {
            $0.kind == .upperWaist && $0.reason == .missingReferenceValue
        })
    }

    @Test func lowerBodyPreferencesOnlyMultiplySelectedLowerKinds() throws {
        let fixture = lowerFixture()
        let result = MeasurementComparisonEngine().compare(
            productSize: fixture.size,
            referenceItem: fixture.item,
            productCategory: .bottom,
            productDetailCategory: .longPants,
            bodyShapePreferences: BodyShapePreferences(
                hasProminentLowerWaist: true,
                hasDevelopedHips: true,
                hasDevelopedThighs: true
            )
        )

        #expect(try #require(result.comparedItems.first { $0.kind == .waist }).weight == 1.4 * 1.25)
        #expect(try #require(result.comparedItems.first { $0.kind == .hip }).weight == 1.2 * 1.25)
        #expect(try #require(result.comparedItems.first { $0.kind == .thigh }).weight == 0.9 * 1.25)
        #expect(!result.comparedKinds.contains(.upperWaist))
    }

    @Test func settingsPersistSelectionsCompletionAndVersion() throws {
        let suiteName = "BodyShapePreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BodyShapeSettingsStore(defaults: defaults)
        let preferences = BodyShapePreferences(
            hasBroadShoulders: true,
            hasDevelopedChest: true,
            hasProminentAbdomen: true,
            hasProminentLowerWaist: true,
            hasDevelopedHips: true,
            hasDevelopedThighs: true
        )

        #expect(store.load() == .none)
        #expect(store.completedVersion == 0)
        store.save(preferences)
        store.markCompleted()
        #expect(BodyShapeSettingsStore(defaults: defaults).load() == preferences)
        #expect(BodyShapeSettingsStore(defaults: defaults).completedVersion == BodyShapeSettingsStore.dataVersion)
    }

    @Test func musinsaMapsOnlyExactConfirmedUpperAbdomenLabels() {
        #expect(MeasurementSourceMappingPolicy.musinsa(
            typeNumber: 5,
            displayKind: .upperAbdomen,
            rawLabel: "복부단면",
            isTopCategory: true
        )?.code == .upperAbdomenWidthEdgeToEdge)
        #expect(MeasurementSourceMappingPolicy.musinsa(
            typeNumber: 5,
            displayKind: .upperWaist,
            rawLabel: "허리단면",
            isTopCategory: true
        )?.code == .upperWaistWidthEdgeToEdge)
        #expect(MeasurementSourceMappingPolicy.musinsa(
            typeNumber: 5,
            displayKind: .upperAbdomen,
            rawLabel: "배너비",
            isTopCategory: true
        ) == nil)
        #expect(MeasurementSourceMappingPolicy.musinsa(
            typeNumber: 6,
            displayKind: .waist,
            rawLabel: "허리단면",
            isTopCategory: false
        )?.code == .waistWidthEdgeToEdge)
    }

    @Test func broadShoulderPreferenceCanDeterministicallyChangeRecommendedUpperSize() throws {
        let reference = upperFixture().item
        let shoulderFit = upperSize(name: "S", shoulder: 46, chest: 56)
        let chestFit = upperSize(name: "M", shoulder: 50, chest: 52)
        let product = Product(name: "상의 경계", category: .top, sizes: [shoulderFit, chestFit])

        let baseline = try #require(RecommendationService().recommend(
            product: product,
            selectedReferenceItem: reference,
            productDetailCategory: .shortSleeve
        ))
        let preferred = try #require(RecommendationService().recommend(
            product: product,
            selectedReferenceItem: reference,
            productDetailCategory: .shortSleeve,
            bodyShapePreferences: BodyShapePreferences(hasBroadShoulders: true)
        ))

        #expect(baseline.recommendedSize.name == "M")
        #expect(preferred.recommendedSize.name == "S")
    }

    @Test func lowerWaistPreferenceCanDeterministicallyChangeRecommendedBottomSize() throws {
        let reference = lowerFixture().item
        let waistFit = lowerSize(name: "S", waist: 40, hip: 55)
        let hipFit = lowerSize(name: "M", waist: 43, hip: 51)
        let product = Product(name: "하의 경계", category: .bottom, sizes: [waistFit, hipFit])

        let baseline = try #require(RecommendationService().recommend(
            product: product,
            selectedReferenceItem: reference,
            productDetailCategory: .longPants
        ))
        let preferred = try #require(RecommendationService().recommend(
            product: product,
            selectedReferenceItem: reference,
            productDetailCategory: .longPants,
            bodyShapePreferences: BodyShapePreferences(hasProminentLowerWaist: true)
        ))

        #expect(baseline.recommendedSize.name == "M")
        #expect(preferred.recommendedSize.name == "S")
    }

    private func abdomenComparison(
        _ fixture: (size: ProductSize, item: UserFit)
    ) -> MeasurementComparisonResult {
        MeasurementComparisonEngine().compare(
            productSize: fixture.size,
            referenceItem: fixture.item,
            productCategory: .top,
            productDetailCategory: .shortSleeve,
            bodyShapePreferences: BodyShapePreferences(hasProminentAbdomen: true)
        )
    }

    private func upperFixture(
        includeAbdomen: Bool = false,
        includeUpperWaist: Bool = false
    ) -> (size: ProductSize, item: UserFit) {
        let size = ProductSize(
            name: "L",
            measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24)
        )
        let item = UserFit(
            brandName: "기준",
            productName: "상의",
            category: .top,
            detailCategory: .shortSleeve,
            sizeName: "M",
            measurements: GarmentMeasurements(shoulder: 46, chest: 52, totalLength: 69, sleeveLength: 23),
            fitMemo: "",
            satisfaction: 4
        )
        size.measurementRecords = [
            record(value: 48, code: .shoulderWidthSeamToSeam, kind: .shoulder, productSize: size),
            record(value: 54, code: .chestWidthPitToPit, kind: .chest, productSize: size),
            record(value: 70, code: .bodyLengthBackNeckToHem, kind: .totalLength, productSize: size)
        ]
        item.measurementRecords = [
            record(value: 46, code: .shoulderWidthSeamToSeam, kind: .shoulder, userFit: item),
            record(value: 52, code: .chestWidthPitToPit, kind: .chest, userFit: item),
            record(value: 69, code: .bodyLengthBackNeckToHem, kind: .totalLength, userFit: item)
        ]
        if includeAbdomen {
            size.measurementRecords.append(record(value: 55, code: .upperAbdomenWidthEdgeToEdge, kind: .upperAbdomen, productSize: size))
            item.measurementRecords.append(record(value: 51, code: .upperAbdomenWidthEdgeToEdge, kind: .upperAbdomen, userFit: item))
        }
        if includeUpperWaist {
            size.measurementRecords.append(record(value: 53, code: .upperWaistWidthEdgeToEdge, kind: .upperWaist, productSize: size))
            item.measurementRecords.append(record(value: 50, code: .upperWaistWidthEdgeToEdge, kind: .upperWaist, userFit: item))
        }
        return (size, item)
    }

    private func lowerFixture() -> (size: ProductSize, item: UserFit) {
        let size = ProductSize(name: "L", measurements: GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 101, sleeveLength: 0))
        let item = UserFit(
            brandName: "기준",
            productName: "하의",
            category: .bottom,
            detailCategory: .longPants,
            sizeName: "M",
            measurements: GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 100, sleeveLength: 0),
            fitMemo: "",
            satisfaction: 4
        )
        size.measurementRecords = [
            record(value: 42, code: .waistWidthEdgeToEdge, kind: .waist, productSize: size),
            record(value: 53, code: .hipWidthAtWidest, kind: .hip, productSize: size),
            record(value: 32, code: .thighWidthCrotchToOuter, kind: .thigh, productSize: size)
        ]
        item.measurementRecords = [
            record(value: 40, code: .waistWidthEdgeToEdge, kind: .waist, userFit: item),
            record(value: 51, code: .hipWidthAtWidest, kind: .hip, userFit: item),
            record(value: 30, code: .thighWidthCrotchToOuter, kind: .thigh, userFit: item)
        ]
        return (size, item)
    }

    private func upperSize(name: String, shoulder: Double, chest: Double) -> ProductSize {
        let size = ProductSize(
            name: name,
            measurements: GarmentMeasurements(shoulder: shoulder, chest: chest, totalLength: 0, sleeveLength: 0)
        )
        size.measurementRecords = [
            record(value: shoulder, code: .shoulderWidthSeamToSeam, kind: .shoulder, productSize: size),
            record(value: chest, code: .chestWidthPitToPit, kind: .chest, productSize: size)
        ]
        return size
    }

    private func lowerSize(name: String, waist: Double, hip: Double) -> ProductSize {
        let size = ProductSize(
            name: name,
            measurements: GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0)
        )
        size.measurementRecords = [
            record(value: waist, code: .waistWidthEdgeToEdge, kind: .waist, productSize: size),
            record(value: hip, code: .hipWidthAtWidest, kind: .hip, productSize: size)
        ]
        return size
    }

    private func record(
        value: Double,
        code: MeasurementCode,
        kind: MeasurementKind,
        productSize: ProductSize? = nil,
        userFit: UserFit? = nil
    ) -> GarmentMeasurementRecord {
        GarmentMeasurementRecord(
            value: value,
            measurementCode: code,
            displayKind: kind.displayKind,
            methodSource: "test",
            inputSource: .importedSizeChart,
            mappingVersion: "test",
            rawLabel: kind.title,
            evidenceLevel: .officialText,
            semanticStatus: .mapped,
            productSize: productSize,
            userFit: userFit
        )
    }
}
