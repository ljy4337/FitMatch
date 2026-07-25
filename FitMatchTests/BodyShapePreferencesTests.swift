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

    @Test func newRecommendationStoresBodyShapeCalculationSnapshot() throws {
        let fixture = upperFixture(includeAbdomen: true, includeUpperWaist: true)
        let product = Product(name: "스냅샷 상의", category: .top, sizes: [fixture.size])
        let preferences = BodyShapePreferences(
            hasBroadShoulders: true,
            hasProminentAbdomen: true
        )

        let history = try #require(RecommendationService().recommend(
            product: product,
            selectedReferenceItem: fixture.item,
            productDetailCategory: .shortSleeve,
            bodyShapePreferences: preferences
        ))
        let snapshot = try #require(history.calculationSnapshot)

        #expect(history.comparisonSchemaVersion == 2)
        #expect(snapshot.bodyShapeSettings == preferences)
        #expect(snapshot.comparisonCoverage == history.comparisonCoverage)
        #expect(snapshot.comparisonCoverage > 0)
        #expect(snapshot.comparisonCoverage <= 1)
        #expect(snapshot.usedMeasurements.map(\.measurementCode) == history.comparedMeasurementUsages.map(\.measurementCode))
        #expect(snapshot.usedMeasurements.contains {
            $0.kind == .shoulder && $0.effectiveWeight == 1.2 * 1.25
        })
        #expect(snapshot.usedMeasurements
            .filter { $0.kind == .upperAbdomen || $0.kind == .upperWaist }
            .map(\.effectiveWeight)
            .reduce(0, +) == 1.75)
        #expect(snapshot.bodyShapeApplications.contains {
            $0.preference == .broadShoulders && $0.status == .applied
        })
        #expect(snapshot.bodyShapeApplications.contains {
            $0.preference == .prominentAbdomen && $0.status == .applied
        })
    }

    @Test func temporarySizeAnalysisReusesComparisonEngineWithoutCreatingHistory() throws {
        let fixture = upperFixture()
        let alternative = upperSize(name: "XL", shoulder: 51, chest: 57)
        alternative.displayOrder = 1
        let product = Product(name: "임시 분석 상의", category: .top, sizes: [fixture.size, alternative])
        let preferences = BodyShapePreferences(hasBroadShoulders: true)

        let analysis = try #require(RecommendationService().analyzeSizeWithoutSaving(
            alternative,
            product: product,
            referenceItem: fixture.item,
            productDetailCategory: .shortSleeve,
            comparisonMethod: "사용자 선택 임시 비교",
            excludedKinds: [],
            bodyShapePreferences: preferences,
            scorePenalty: 12
        ))
        let direct = MeasurementComparisonEngine().compare(
            productSize: alternative,
            referenceItem: fixture.item,
            productCategory: product.category,
            productDetailCategory: .shortSleeve,
            bodyShapePreferences: preferences
        )

        #expect(analysis.productSize.id == alternative.id)
        #expect(analysis.comparisonResult == direct)
        #expect(analysis.recommendationScore == max(0, direct.score - 12))
        #expect(analysis.calculationSnapshot.bodyShapeSettings == preferences)
    }

    @Test func temporarySizeAnalysisDoesNotMutateOriginalRecommendation() throws {
        let fixture = upperFixture()
        fixture.size.displayOrder = 0
        let alternative = upperSize(name: "XL", shoulder: 53, chest: 58)
        alternative.displayOrder = 1
        let product = Product(name: "원본 보존 상의", category: .top, sizes: [fixture.size, alternative])
        let original = try #require(RecommendationService().recommend(
            product: product,
            selectedReferenceItem: fixture.item,
            productDetailCategory: .shortSleeve
        ))
        let originalSizeID = original.recommendedSize.id
        let originalScore = original.recommendationScore
        let originalSnapshot = original.calculationSnapshot

        _ = RecommendationService().analyzeSizeWithoutSaving(
            alternative,
            product: product,
            referenceItem: fixture.item,
            productDetailCategory: .shortSleeve,
            comparisonMethod: original.comparisonMethod,
            excludedKinds: original.measurementExclusions.filter { $0.reason == .categoryPolicy }.map(\.kind),
            bodyShapePreferences: original.calculationSnapshot?.bodyShapeSettings ?? .none,
            scorePenalty: 0
        )

        #expect(original.recommendedSize.id == originalSizeID)
        #expect(original.recommendationScore == originalScore)
        #expect(original.calculationSnapshot == originalSnapshot)
    }

    @Test func temporarySizeAnalysisReturnsNilForInsufficientEvidence() {
        let reference = upperFixture().item
        let emptySize = ProductSize(
            name: "정보없음",
            measurements: GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0)
        )
        let product = Product(name: "실측 부족 상의", category: .top, sizes: [emptySize])

        let analysis = RecommendationService().analyzeSizeWithoutSaving(
            emptySize,
            product: product,
            referenceItem: reference,
            productDetailCategory: .shortSleeve,
            comparisonMethod: "사용자 선택 임시 비교",
            excludedKinds: [],
            bodyShapePreferences: .none,
            scorePenalty: 0
        )

        #expect(analysis == nil)
    }

    @Test func missingSelectedMeasurementStoresUnappliedReasonAndCoverage() throws {
        let fixture = upperFixture()
        let product = Product(name: "결측 상의", category: .top, sizes: [fixture.size])

        let history = try #require(RecommendationService().recommend(
            product: product,
            selectedReferenceItem: fixture.item,
            productDetailCategory: .shortSleeve,
            bodyShapePreferences: BodyShapePreferences(hasProminentAbdomen: true)
        ))
        let snapshot = try #require(history.calculationSnapshot)
        let abdomen = try #require(snapshot.bodyShapeApplications.first {
            $0.preference == .prominentAbdomen
        })

        #expect(abdomen.status == .missingBothMeasurements)
        #expect(abdomen.measurementCodes.isEmpty)
        #expect(snapshot.excludedMeasurements.contains {
            ($0.kind == .upperAbdomen || $0.kind == .upperWaist)
                && $0.reason == .missingBothValues
        })
        #expect(snapshot.comparisonCoverage < 1)
        #expect(snapshot.comparisonCoverage.isFinite)
    }

    @Test func legacyHistoryDecodesWithoutSnapshotAndNeverUsesCurrentSettings() throws {
        let fixture = upperFixture()
        let product = Product(name: "기존 기록", category: .top, sizes: [fixture.size])
        let history = RecommendationHistory(
            product: product,
            recommendedSize: fixture.size,
            userFit: fixture.item,
            totalDifference: 2,
            measurementDifferences: GarmentMeasurements(
                shoulder: 2,
                chest: 2,
                totalLength: 1,
                sleeveLength: 0
            ),
            recommendationScore: 87
        )
        let legacyUsages = [
            MeasurementComparisonUsage(
                kind: .chest,
                measurementCode: .chestWidthPitToPit
            )
        ]
        history.comparisonSchemaVersion = 1
        history.comparedMeasurementUsagesJSON = String(
            data: try JSONEncoder().encode(legacyUsages),
            encoding: .utf8
        )!
        let originalSize = history.recommendedSize.name
        let originalScore = history.recommendationScore
        let suiteName = "BodyShapePreferencesTests.history.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        BodyShapeSettingsStore(defaults: defaults).save(
            BodyShapePreferences(
                hasBroadShoulders: true,
                hasDevelopedChest: true,
                hasProminentAbdomen: true
            )
        )

        #expect(history.calculationSnapshot == nil)
        #expect(history.comparisonCoverage == 0)
        #expect(history.comparedMeasurementUsages == legacyUsages)
        #expect(history.recommendedSize.name == originalSize)
        #expect(history.recommendationScore == originalScore)
    }

    @Test func comparisonCoverageIncludesSelectedPreferenceWeightsAndClampsBounds() {
        let fixture = upperFixture()
        let result = MeasurementComparisonEngine().compare(
            productSize: fixture.size,
            referenceItem: fixture.item,
            productCategory: .top,
            productDetailCategory: .shortSleeve,
            bodyShapePreferences: BodyShapePreferences(hasBroadShoulders: true)
        )

        #expect(result.expectedWeightSum == (1.2 * 1.25) + 1.4 + 1.0 + 0.2)
        #expect(result.usedWeightSum == (1.2 * 1.25) + 1.4 + 1.0)
        #expect(result.comparisonCoverage == result.usedWeightSum / result.expectedWeightSum)

        let zero = MeasurementComparisonResult(
            status: .insufficientEvidence,
            score: 0,
            comparedItems: [],
            exclusions: [],
            averageDifference: .greatestFiniteMagnitude,
            minimumComparableCount: 1,
            requiredKinds: [],
            minimumRequiredKindCount: 0,
            requiredAllKinds: [],
            expectedWeightSum: 0,
            usedWeightSum: 0
        )
        let over = MeasurementComparisonResult(
            status: .confirmed,
            score: 100,
            comparedItems: [],
            exclusions: [],
            averageDifference: 0,
            minimumComparableCount: 0,
            requiredKinds: [],
            minimumRequiredKindCount: 0,
            requiredAllKinds: [],
            expectedWeightSum: 1,
            usedWeightSum: 2
        )
        #expect(zero.comparisonCoverage == 0)
        #expect(over.comparisonCoverage == 1)
    }

    @Test func comparisonCoverageCanReachOneHundredPercent() {
        let fixture = upperFixture()
        let result = MeasurementComparisonEngine().compare(
            productSize: fixture.size,
            referenceItem: fixture.item,
            productCategory: .top,
            productDetailCategory: .sleeveless
        )

        #expect(result.usedWeightSum == result.expectedWeightSum)
        #expect(result.comparisonCoverage == 1)
    }

    @Test func exclusionsDistinguishProductReferenceAndBothMissing() {
        let engine = MeasurementComparisonEngine()

        let productMissing = upperFixture()
        productMissing.size.measurementRecords.removeAll { $0.displayKind == .shoulder }
        #expect(engine.compare(
            productSize: productMissing.size,
            referenceItem: productMissing.item,
            productCategory: .top,
            productDetailCategory: .sleeveless
        ).exclusions.contains { $0.kind == .shoulder && $0.reason == .missingProductValue })

        let referenceMissing = upperFixture()
        referenceMissing.item.measurementRecords.removeAll { $0.displayKind == .shoulder }
        #expect(engine.compare(
            productSize: referenceMissing.size,
            referenceItem: referenceMissing.item,
            productCategory: .top,
            productDetailCategory: .sleeveless
        ).exclusions.contains { $0.kind == .shoulder && $0.reason == .missingReferenceValue })

        let bothMissing = upperFixture()
        bothMissing.size.measurementRecords.removeAll { $0.displayKind == .shoulder }
        bothMissing.item.measurementRecords.removeAll { $0.displayKind == .shoulder }
        #expect(engine.compare(
            productSize: bothMissing.size,
            referenceItem: bothMissing.item,
            productCategory: .top,
            productDetailCategory: .sleeveless
        ).exclusions.contains { $0.kind == .shoulder && $0.reason == .missingBothValues })
    }

    @Test func exclusionsKeepIncompatibleDefinitionAndCategoryPolicySeparate() {
        let incompatible = upperFixture()
        incompatible.item.measurementRecords.removeAll { $0.displayKind == .chest }
        incompatible.item.measurementRecords.append(
            record(
                value: 52,
                code: .chestWidthUniqloBodyWidth,
                kind: .chest,
                userFit: incompatible.item
            )
        )
        let incompatibleResult = MeasurementComparisonEngine().compare(
            productSize: incompatible.size,
            referenceItem: incompatible.item,
            productCategory: .top,
            productDetailCategory: .sleeveless
        )
        #expect(incompatibleResult.exclusions.contains {
            $0.kind == .chest && $0.reason == .incompatibleMeasurementCode
        })

        let categoryExcluded = upperFixture()
        let categoryResult = MeasurementComparisonEngine().compare(
            productSize: categoryExcluded.size,
            referenceItem: categoryExcluded.item,
            productCategory: .top,
            productDetailCategory: .sleeveless,
            excludedKinds: [.shoulder]
        )
        #expect(categoryResult.exclusions.contains {
            $0.kind == .shoulder && $0.reason == .categoryPolicy
        })
    }

    @Test func snapshotPresentationUsesSavedStateAndHidesUnselectedBodyShape() throws {
        let fixture = upperFixture()
        let noPreferenceResult = MeasurementComparisonEngine().compare(
            productSize: fixture.size,
            referenceItem: fixture.item,
            productCategory: .top,
            productDetailCategory: .sleeveless
        )
        let noPreference = RecommendationCalculationPresentation(
            snapshot: .make(comparison: noPreferenceResult, bodyShapeSettings: .none)
        )
        #expect(noPreference.coveragePercent == 100)
        #expect(noPreference.bodyShapeTitle == nil)
        #expect(noPreference.bodyShapeMessages.isEmpty)

        let allResult = MeasurementComparisonEngine().compare(
            productSize: fixture.size,
            referenceItem: fixture.item,
            productCategory: .top,
            productDetailCategory: .sleeveless,
            bodyShapePreferences: BodyShapePreferences(
                hasBroadShoulders: true,
                hasDevelopedChest: true
            )
        )
        let all = RecommendationCalculationPresentation(
            snapshot: .make(
                comparison: allResult,
                bodyShapeSettings: BodyShapePreferences(
                    hasBroadShoulders: true,
                    hasDevelopedChest: true
                )
            )
        )
        #expect(all.bodyShapeTitle == "선택한 체형을 모두 반영했어요")

        let partialFixture = upperFixture()
        partialFixture.size.measurementRecords.removeAll { $0.displayKind == .shoulder }
        let partialPreferences = BodyShapePreferences(
            hasBroadShoulders: true,
            hasDevelopedChest: true
        )
        let partialResult = MeasurementComparisonEngine().compare(
            productSize: partialFixture.size,
            referenceItem: partialFixture.item,
            productCategory: .top,
            productDetailCategory: .sleeveless,
            bodyShapePreferences: partialPreferences
        )
        let partial = RecommendationCalculationPresentation(
            snapshot: .make(comparison: partialResult, bodyShapeSettings: partialPreferences)
        )
        #expect(partial.bodyShapeTitle == "체형 설정 일부 반영")
        #expect(partial.bodyShapeMessages.contains {
            $0.contains("상품의 관련 치수가 없어")
        })

        let noneAppliedPreferences = BodyShapePreferences(hasProminentAbdomen: true)
        let noneAppliedResult = MeasurementComparisonEngine().compare(
            productSize: fixture.size,
            referenceItem: fixture.item,
            productCategory: .top,
            productDetailCategory: .sleeveless,
            bodyShapePreferences: noneAppliedPreferences
        )
        let noneApplied = RecommendationCalculationPresentation(
            snapshot: .make(
                comparison: noneAppliedResult,
                bodyShapeSettings: noneAppliedPreferences
            )
        )
        #expect(noneApplied.bodyShapeTitle == "체형 설정을 반영하지 못했어요")
    }

    @Test func snapshotPresentationDistinguishesExclusionMessagesAndClampsPercent() {
        let snapshot = RecommendationCalculationSnapshot(
            version: 1,
            bodyShapeSettings: .none,
            bodyShapeApplications: [],
            usedMeasurements: [],
            excludedMeasurements: [
                MeasurementComparisonExclusion(kind: .shoulder, reason: .missingProductValue, productCode: nil, referenceCode: .shoulderWidthSeamToSeam),
                MeasurementComparisonExclusion(kind: .chest, reason: .missingReferenceValue, productCode: .chestWidthPitToPit, referenceCode: nil),
                MeasurementComparisonExclusion(kind: .upperWaist, reason: .missingBothValues, productCode: nil, referenceCode: nil),
                MeasurementComparisonExclusion(kind: .sleeveLength, reason: .incompatibleMeasurementCode, productCode: .sleeveShoulderSeamToCuff, referenceCode: .sleeveRaglanNeckToCuff),
                MeasurementComparisonExclusion(kind: .hem, reason: .categoryPolicy, productCode: .hemWidthEdgeToEdge, referenceCode: .hemWidthEdgeToEdge)
            ],
            comparisonCoverage: 1.5
        )
        let presentation = RecommendationCalculationPresentation(snapshot: snapshot)

        #expect(presentation.coveragePercent == 100)
        #expect(presentation.exclusionMessages.contains("어깨너비 · 상품 치수 없음"))
        #expect(presentation.exclusionMessages.contains("가슴단면 · 기준 옷 치수 없음"))
        #expect(presentation.exclusionMessages.contains("상의 허리단면 · 상품과 기준 옷 모두 치수 없음"))
        #expect(presentation.exclusionMessages.contains("소매길이 · 측정 기준이 달라 비교 제외"))
        #expect(presentation.exclusionMessages.contains("밑단단면 · 해당 카테고리의 비교 대상이 아님"))
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
