import Foundation
import Testing
@testable import FitMatch

@Suite(.serialized)
@MainActor
struct BodyShapeRemovalTests {
    private let legacyPreferencesKey = "FitMatch.bodyShape.preferences"
    private let legacyCompletionKey = "FitMatch.bodyShape.completedVersion"

    @Test func legacyBodyShapeValuesDoNotChangeRecommendation() throws {
        let defaults = UserDefaults.standard
        let originalPreferences = defaults.object(forKey: legacyPreferencesKey)
        let originalCompletion = defaults.object(forKey: legacyCompletionKey)
        defer {
            restore(originalPreferences, forKey: legacyPreferencesKey, in: defaults)
            restore(originalCompletion, forKey: legacyCompletionKey, in: defaults)
        }

        let fixture = upperFixture()
        let product = Product(
            name: "체형 비의존 검증",
            category: .top,
            sizes: [
                upperSize(name: "S", shoulder: 46, chest: 56),
                upperSize(name: "M", shoulder: 50, chest: 52)
            ]
        )

        defaults.set(Data(#"{"hasBroadShoulders":true,"hasDevelopedChest":false}"#.utf8), forKey: legacyPreferencesKey)
        defaults.set(1, forKey: legacyCompletionKey)
        let bodyShapeA = try recommendationSignature(product: product, reference: fixture.item)

        defaults.set(Data(#"{"hasBroadShoulders":false,"hasDevelopedChest":true}"#.utf8), forKey: legacyPreferencesKey)
        defaults.set(1, forKey: legacyCompletionKey)
        let bodyShapeB = try recommendationSignature(product: product, reference: fixture.item)

        defaults.removeObject(forKey: legacyPreferencesKey)
        defaults.removeObject(forKey: legacyCompletionKey)
        let bodyShapeNil = try recommendationSignature(product: product, reference: fixture.item)

        #expect(bodyShapeA == bodyShapeB)
        #expect(bodyShapeB == bodyShapeNil)
    }

    @Test func categoryBaseWeightsRemainUnchanged() throws {
        let fixture = upperFixture()
        let result = MeasurementComparisonEngine().compare(
            productSize: fixture.size,
            referenceItem: fixture.item,
            productCategory: .top,
            productDetailCategory: .shortSleeve
        )

        #expect(try #require(result.comparedItems.first { $0.kind == .shoulder }).weight == 1.2)
        #expect(try #require(result.comparedItems.first { $0.kind == .chest }).weight == 1.4)
        #expect(try #require(result.comparedItems.first { $0.kind == .totalLength }).weight == 1.0)
        #expect(try #require(result.comparedItems.first { $0.kind == .sleeveLength }).weight == 0.2)
        #expect(result.expectedWeightSum == 3.8)
    }

    @Test func formerBodyShapeOnlyMeasurementsDoNotEnterTopRecommendation() {
        let fixture = upperFixture(includeAbdomen: true)
        let result = MeasurementComparisonEngine().compare(
            productSize: fixture.size,
            referenceItem: fixture.item,
            productCategory: .top,
            productDetailCategory: .shortSleeve
        )

        #expect(!result.comparedKinds.contains(.upperAbdomen))
        #expect(!result.comparedKinds.contains(.upperWaist))
        #expect(result.status == .confirmed)
    }

    @Test func newSnapshotContainsNoBodyShapeState() throws {
        let fixture = upperFixture()
        let product = Product(name: "스냅샷 검증", category: .top, sizes: [fixture.size])
        let history = try #require(RecommendationService().recommend(
            product: product,
            selectedReferenceItem: fixture.item,
            productDetailCategory: .shortSleeve
        ))
        let snapshot = try #require(history.calculationSnapshot)
        let comparisonData = history.comparisonData
        let json = try #require(String(data: JSONEncoder().encode(snapshot), encoding: .utf8))

        #expect(snapshot.version == RecommendationCalculationSnapshot.currentVersion)
        #expect(snapshot.usedMeasurements.map(\.measurementCode) == history.comparedMeasurementUsages.map(\.measurementCode))
        #expect(comparisonData.calculationSnapshot == history.calculationSnapshot)
        #expect(comparisonData.comparedMeasurementUsages == history.comparedMeasurementUsages)
        #expect(comparisonData.measurementExclusions == history.measurementExclusions)
        #expect(!json.localizedCaseInsensitiveContains("bodyShape"))
        #expect(!json.localizedCaseInsensitiveContains("physique"))
    }

    @Test func temporarySizeAnalysisUsesSameComparisonEngine() throws {
        let fixture = upperFixture()
        let alternative = upperSize(name: "XL", shoulder: 51, chest: 57)
        let product = Product(name: "임시 분석 검증", category: .top, sizes: [fixture.size, alternative])
        let analysis = try #require(RecommendationService().analyzeSizeWithoutSaving(
            alternative,
            product: product,
            referenceItem: fixture.item,
            productDetailCategory: .shortSleeve,
            comparisonMethod: "사용자 선택 직접 비교",
            excludedKinds: [],
            scorePenalty: 12
        ))
        let direct = MeasurementComparisonEngine().compare(
            productSize: alternative,
            referenceItem: fixture.item,
            productCategory: product.category,
            productDetailCategory: .shortSleeve
        )

        #expect(analysis.comparisonResult == direct)
        #expect(analysis.recommendationScore == max(0, direct.score - 12))
        #expect(analysis.calculationSnapshot == .make(comparison: direct))
    }

    private func recommendationSignature(
        product: Product,
        reference: UserFit
    ) throws -> RecommendationSignature {
        let history = try #require(RecommendationService().recommend(
            product: product,
            selectedReferenceItem: reference,
            productDetailCategory: .shortSleeve
        ))
        return RecommendationSignature(
            sizeName: history.recommendedSize.name,
            score: history.recommendationScore,
            snapshotVersion: history.calculationSnapshot?.version,
            measurementCodes: history.calculationSnapshot?.usedMeasurements.map {
                $0.measurementCode.rawValue
            } ?? [],
            comparisonCoverage: history.calculationSnapshot?.comparisonCoverage
        )
    }

    private func restore(_ value: Any?, forKey key: String, in defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func upperFixture(
        includeAbdomen: Bool = false
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
            record(value: 70, code: .bodyLengthBackNeckToHem, kind: .totalLength, productSize: size),
            record(value: 24, code: .sleeveShoulderSeamToCuff, kind: .sleeveLength, productSize: size)
        ]
        item.measurementRecords = [
            record(value: 46, code: .shoulderWidthSeamToSeam, kind: .shoulder, userFit: item),
            record(value: 52, code: .chestWidthPitToPit, kind: .chest, userFit: item),
            record(value: 69, code: .bodyLengthBackNeckToHem, kind: .totalLength, userFit: item),
            record(value: 23, code: .sleeveShoulderSeamToCuff, kind: .sleeveLength, userFit: item)
        ]
        if includeAbdomen {
            size.measurementRecords.append(
                record(value: 55, code: .upperAbdomenWidthEdgeToEdge, kind: .upperAbdomen, productSize: size)
            )
            item.measurementRecords.append(
                record(value: 51, code: .upperAbdomenWidthEdgeToEdge, kind: .upperAbdomen, userFit: item)
            )
        }
        return (size, item)
    }

    private func upperSize(name: String, shoulder: Double, chest: Double) -> ProductSize {
        let size = ProductSize(
            name: name,
            measurements: GarmentMeasurements(shoulder: shoulder, chest: chest, totalLength: 70, sleeveLength: 24)
        )
        size.measurementRecords = [
            record(value: shoulder, code: .shoulderWidthSeamToSeam, kind: .shoulder, productSize: size),
            record(value: chest, code: .chestWidthPitToPit, kind: .chest, productSize: size),
            record(value: 70, code: .bodyLengthBackNeckToHem, kind: .totalLength, productSize: size),
            record(value: 24, code: .sleeveShoulderSeamToCuff, kind: .sleeveLength, productSize: size)
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

private struct RecommendationSignature: Equatable {
    let sizeName: String
    let score: Int
    let snapshotVersion: Int?
    let measurementCodes: [String]
    let comparisonCoverage: Double?
}
