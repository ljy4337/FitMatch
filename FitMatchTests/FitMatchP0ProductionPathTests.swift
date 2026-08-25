import Foundation
import SwiftData
import Testing
@testable import FitMatch

private final class FitMatchP0BundleToken {}

@MainActor
struct FitMatchP0ProductionPathTests {
    @Test func p0ExactProductCategoryChoiceDoesNotSpreadToSiblingProduct() {
        let sourcePath = "상의 > 기타 상의 > p0-(UUID().uuidString)"
        let selected = Product(
            name: "사용자가 분류한 상품",
            category: .top,
            productCode: "p0-selected-(UUID().uuidString)",
            metadata: ProductMetadata(sourceCategoryPath: sourcePath),
            sourceName: "무신사",
            sizes: []
        )
        let sibling = Product(
            name: "같은 경로의 다른 상품",
            category: .top,
            productCode: "p0-sibling-(UUID().uuidString)",
            metadata: ProductMetadata(sourceCategoryPath: sourcePath),
            sourceName: "무신사",
            sizes: []
        )

        SourceCategoryHistoryMatcher.saveMapping(
            for: selected,
            category: .shirt,
            detailCategory: .shirt
        )

        #expect(SourceCategoryHistoryMatcher.matches(
            for: selected,
            detectedDetailCategory: .other,
            userFits: []
        ).map(\.detailCategory) == [.shirt])
        #expect(SourceCategoryHistoryMatcher.matches(
            for: sibling,
            detectedDetailCategory: .other,
            userFits: []
        ).isEmpty)
    }

    // PATH-MUSINSA-PARSE-01 · Source Truth: stored actual-size API response.
    @Test func p0MusinsaCapturedFixturesPreserveOfficialMeasurements() throws {
        let expectations: [(id: String, size: String, values: [MeasurementKind: Double])] = [
            ("6294035", "XS", [.totalLength: 67, .shoulder: 54, .chest: 57, .sleeveLength: 22]),
            ("5952634", "free", [.totalLength: 66, .chest: 56, .sleeveLength: 78]),
            ("3246389", "M", [.totalLength: 106, .waist: 32, .hip: 49.5, .thigh: 32, .rise: 35, .hem: 23])
        ]
        let inputs = try corpus(named: "Musinsa1037FitPairInputs")
        let parser = MusinsaActualSizeAPIParser()

        for expected in expectations {
            let input = try #require(inputs.first { $0["product_id"] as? String == expected.id })
            let response = try #require(input["response"])
            let sourcePath = try #require(input["source_path"] as? String)
            let category = MusinsaProductMetadataParser.mapCategory(from: sourcePath)
            let result = try parser.parseActualSize(
                from: JSONSerialization.data(withJSONObject: response),
                isTopCategory: category.serviceGroup == .top
            )
            let size = try #require(result.sizes.first { $0.name == expected.size })

            for (kind, value) in expected.values {
                #expect(size.measurements.value(for: kind) == value, "무신사 \(expected.id) \(expected.size) \(kind.title) 원본값 불일치")
            }
        }
    }

    // PATH-UNIQLO-PARSE-01 · Source Truth: stored official size API response.
    @Test func p0UniqloCapturedFixturesPreserveOfficialMeasurements() throws {
        let expectations: [(id: String, size: String, values: [MeasurementKind: Double])] = [
            ("E493045", "XS", [.totalLength: 64, .shoulder: 48, .chest: 48, .sleeveLength: 44.5]),
            ("E475941", "S", [.totalLength: 76, .shoulder: 44, .chest: 53.5, .sleeveLength: 80]),
            ("E488200", "S", [.totalLength: 46.5, .shoulder: 48.5, .chest: 49, .sleeveLength: 77.5]),
            ("E488202", "S", [.waist: 34, .hip: 46.75, .thigh: 33.5, .rise: 27.5, .hem: 22.5])
        ]
        let inputs = try corpus(named: "Uniqlo243FitPairInputs")
        let parser = UniqloSizeAPIParser()

        for expected in expectations {
            let input = try #require(inputs.first { $0["product_id"] as? String == expected.id })
            let response = try #require(input["response"])
            let sizes = try parser.parseSizes(from: JSONSerialization.data(withJSONObject: response))
            let size = try #require(sizes.first { $0.name == expected.size })

            for (kind, value) in expected.values {
                #expect(size.measurements.value(for: kind) == value, "유니클로 \(expected.id) \(expected.size) \(kind.title) 원본값 불일치")
            }
        }
    }

    // PATH-CATEGORY-CONFIRM-01 · Policy Truth: official path is a graphic T-shirt.
    @Test func p0UniqloGraphicTShirtDoesNotFallIntoOtherTops() throws {
        let input = try fixture(id: "E493045", in: "Uniqlo243FitPairInputs")
        let name = try #require(input["product_name"] as? String)
        let sourcePath = try #require(input["source_path"] as? String)
        let depths = sourceDepths(sourcePath)
        let metadataParser = UniqloProductMetadataParser()
        let providerCategory = metadataParser.mapCategory(from: "\(sourcePath) \(name)")
        let providerDetail = metadataParser.mapDetailCategory(from: "\(sourcePath) \(name)")
        let response = try #require(input["response"])
        let sizes = try UniqloSizeAPIParser().parseSizes(
            from: JSONSerialization.data(withJSONObject: response)
        )
        let normalized = ParsedProductInfo(
            sourceURL: URL(string: "https://store-kr.uniqlo.com/kr/ko/products/E493045-000/00")!,
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            brandName: "UNIQLO",
            productName: name,
            category: providerCategory,
            detailCategory: providerDetail,
            sizes: sizes,
            productID: "E493045",
            sourceCategoryPath: sourcePath,
            sourceCategoryDepth1: depths.indices.contains(0) ? depths[0] : nil,
            sourceCategoryDepth2: depths.indices.contains(1) ? depths[1] : nil,
            sourceCategoryDepth3: depths.indices.contains(2) ? depths[2] : nil,
            productTargetGender: .men
        ).normalizedSizes()
        let classification = try #require(ParsedClosetClassification.resolve(
            category: providerCategory,
            detailCategory: normalized.detailCategory,
            sourceDepths: depths.map(Optional.some),
            sourcePath: sourcePath,
            productName: name
        ))

        #expect(classification.categoryCode == "tops")
        #expect(classification.detailCode == "short_sleeve")
        #expect(classification.detailCode != "other_tops")
    }

    // PATH-CLASSIFICATION-SAFETY-01 · Explicit critical contradictions must
    // require review instead of silently entering comparison.
    @Test func p1ExplicitCriticalClassificationContradictionsRequireReview() {
        let fixtures: [(
            category: ClothingCategory,
            detail: ClosetDetailCategory,
            path: String,
            name: String
        )] = [
            (.top, .longSleeve, "상의 > 긴소매 티셔츠", "반팔 티셔츠"),
            (.top, .shortSleeve, "상의 > 반소매 티셔츠", "긴팔 니트 가디건"),
            (.top, .other, "상의", "플리츠 스커트"),
            (.underwear, .underwear, "속옷", "그래픽 티셔츠")
        ]

        for fixture in fixtures {
            let audit = ParsedClosetClassification.auditExplicitContradictions(
                category: fixture.category,
                detailCategory: fixture.detail,
                sourceDepths: sourceDepths(fixture.path).map(Optional.some),
                sourcePath: fixture.path,
                productName: fixture.name
            )

            #expect(audit.requiresReview, "\(fixture.path) / \(fixture.name)이 자동 확정됐습니다.")
            #expect(!audit.conflicts.isEmpty)
        }
    }

    // PATH-CLASSIFICATION-SAFETY-01 · Compatible corroboration and reviewed
    // compound names must not be reopened by the contradiction guard.
    @Test func p1CompatibleAndAdjudicatedClassificationEvidenceRemainsSafe() {
        let safeFixtures: [(
            category: ClothingCategory,
            detail: ClosetDetailCategory,
            path: String,
            name: String
        )] = [
            (.bottom, .longPants, "하의 > 조거 팬츠", "파라슈트 카고 팬츠"),
            (.top, .sleeveless, "WOMAN > Sleeveless Tops", "Sleeveless Fine Knit Top"),
            (.top, .shirt, "셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 긴팔", "데님릴렉스셔츠재킷"),
            (.underwear, .underwear, "MEN > Innerwear", "AIRism Cotton Crew Neck T-Shirt"),
            (.top, .sleeveless, "상의 > 나시/민소매 티셔츠", "브라탑 민소매 티셔츠"),
            (.top, .longSleeve, "상의 > 긴소매 티셔츠", "그래픽 긴팔 티셔츠")
        ]

        for fixture in safeFixtures {
            let audit = ParsedClosetClassification.auditExplicitContradictions(
                category: fixture.category,
                detailCategory: fixture.detail,
                sourceDepths: sourceDepths(fixture.path).map(Optional.some),
                sourcePath: fixture.path,
                productName: fixture.name
            )

            #expect(!audit.requiresReview, "\(fixture.path) / \(fixture.name)이 오탐으로 차단됐습니다.")
        }
    }

    // PATH-CLASSIFICATION-SAFETY-01 · The conflict decision is applied after
    // the canonical profile and remains fail-closed until explicit review.
    @Test func p1ProductCreationPreservesConflictEligibilityUntilUserConfirmation() throws {
        let parsed = ParsedProductInfo(
            sourceURL: URL(string: "https://www.musinsa.com/products/p1-conflict")!,
            sourceType: .marketplace,
            sourceName: "무신사",
            brandName: "P1",
            productName: "반팔 티셔츠",
            category: .top,
            detailCategory: .longSleeve,
            sizes: [ParsedProductSize(
                name: "M",
                measurements: GarmentMeasurements(
                    shoulder: 48,
                    chest: 54,
                    totalLength: 70,
                    sleeveLength: 24
                )
            )],
            productID: "p1-conflict",
            sourceCategoryPath: "상의 > 긴소매 티셔츠",
            sourceCategoryDepth1: "상의",
            sourceCategoryDepth2: "긴소매 티셔츠",
            productTargetGender: .unisex
        )
        let viewModel = ShoppingProductViewModel(metricsRecorder: P0NoopMetricsRecorder())
        viewModel.apply(parsed)

        let blocked = try #require(viewModel.makeProductForClosetRegistration(brand: nil))
        #expect(viewModel.classificationSafetyAudit.requiresReview)
        #expect(blocked.canonicalEligibility == false)
        #expect(blocked.canonicalResolutionMethod
            == ParsedClosetClassificationSafetyAudit.conflictResolutionMethod)
        #expect(ComparisonProfileMatcher().match(
            product: blocked,
            productDetailCategory: .shortSleeve,
            userFits: []
        ).state == .requiresConfirmation)

        let adjudicated = try #require(viewModel.makeProductForClosetRegistration(
            brand: nil,
            classificationWasUserConfirmed: true
        ))
        #expect(adjudicated.canonicalEligibility != false)
        #expect(adjudicated.canonicalResolutionMethod
            != ParsedClosetClassificationSafetyAudit.conflictResolutionMethod)
    }

    // PATH-COMPARE-ELIGIBILITY-01 · Standard-size fallback must honor the same
    // classification eligibility gate as canonical measurement comparison.
    @Test func p1ClassificationConflictCannotBypassStandardSizeComparison() {
        let product = comparisonProduct(
            name: "분류 충돌 반팔 티셔츠",
            category: .top,
            detail: .shortSleeve,
            family: .tshirt,
            sourcePath: "상의 > 긴소매 티셔츠",
            measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24)
        )
        product.sizeType = StandardBodySizeChart.metadataMarker
        product.canonicalEligibility = false
        product.canonicalResolutionMethod = ParsedClosetClassificationSafetyAudit.conflictResolutionMethod

        let item = comparisonItem(
            name: "내 기준 반팔 티셔츠",
            category: .top,
            detail: .shortSleeve,
            family: .tshirt,
            sourcePath: "상의 > 반소매 티셔츠",
            measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24)
        )
        let service = RecommendationService()

        #expect(service.comparisonCompatibility(
            product: product,
            productDetailCategory: .shortSleeve,
            item: item
        ).level == .blocked)
        #expect(service.temporaryComparisonCandidates(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [item]
        ).isEmpty)
        #expect(service.referenceSelectionPlan(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [item]
        ).recommendedCandidates.isEmpty)
        #expect(service.recommend(
            product: product,
            userFits: [item],
            productDetailCategory: .shortSleeve
        ) == nil)
        #expect(service.recommend(
            product: product,
            selectedReferenceItem: item,
            productDetailCategory: .shortSleeve
        ) == nil)
        #expect(service.analyzeSizeWithoutSaving(
            product.sizes[0],
            product: product,
            referenceItem: item,
            productDetailCategory: .shortSleeve,
            comparisonMethod: "기준표 가슴둘레 비교",
            excludedKinds: [],
            scorePenalty: 0
        ) == nil)
    }

    // PATH-COMPARE-ELIGIBILITY-01 · An ineligible reference must also be
    // excluded from every standard-size candidate path.
    @Test func p1IneligibleReferenceCannotBypassStandardSizeComparison() {
        let product = comparisonProduct(
            name: "정상 반팔 티셔츠",
            category: .top,
            detail: .shortSleeve,
            family: .tshirt,
            sourcePath: "상의 > 반소매 티셔츠",
            measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24)
        )
        product.sizeType = StandardBodySizeChart.metadataMarker
        product.canonicalEligibility = true

        let item = comparisonItem(
            name: "분류 충돌 기준 옷",
            category: .top,
            detail: .shortSleeve,
            family: .tshirt,
            sourcePath: "상의 > 긴소매 티셔츠",
            measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24)
        )
        item.canonicalEligibility = false
        item.canonicalResolutionMethod = ParsedClosetClassificationSafetyAudit.conflictResolutionMethod

        let service = RecommendationService()
        #expect(service.temporaryComparisonCandidates(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [item]
        ).isEmpty)
        #expect(service.recommend(
            product: product,
            userFits: [item],
            productDetailCategory: .shortSleeve
        ) == nil)
    }

    // PATH-UNIQLO-PARSE-01 · Rise and length are different measurements.
    @Test func p0UniqloBottomLegacyLengthDoesNotReuseRise() throws {
        let inputs = try corpus(named: "Uniqlo243FitPairInputs")
        let parser = UniqloSizeAPIParser()
        var checkedProductIDs = Set<String>()
        var affectedProductIDs = Set<String>()

        for input in inputs {
            let productID = try #require(input["product_id"] as? String)
            let response = try #require(input["response"])
            let sizes = try parser.parseSizes(
                from: JSONSerialization.data(withJSONObject: response)
            )
            let bottomSizes = sizes.filter { size in
                let codes = Set(size.measurementRecords.map(\.measurementCode))
                return codes.contains(.riseCrotchToWaistFront)
                    && codes.contains(.pantsInseamCrotchToHem)
            }
            guard !bottomSizes.isEmpty else { continue }
            checkedProductIDs.insert(productID)
            if bottomSizes.contains(where: {
                $0.measurements.rise > 0
                    && $0.measurements.totalLength == $0.measurements.rise
            }) {
                affectedProductIDs.insert(productID)
            }
        }

        #expect(!checkedProductIDs.isEmpty)
        #expect(affectedProductIDs.isEmpty,
                "유니클로 하의 \(checkedProductIDs.count)개 중 \(affectedProductIDs.count)개에서 밑위가 legacy 총장으로 중복됐습니다. 상품: \(affectedProductIDs.sorted().prefix(20).joined(separator: ", "))")
    }

    // PATH-UNIQLO-PARSE-01 · Cross-layer contamination guard for bottoms.
    @Test func p0UniqloBottomKeepsRiseAndContainsNoUpperBodyMeasurements() throws {
        let input = try fixture(id: "E488202", in: "Uniqlo243FitPairInputs")
        let response = try #require(input["response"])
        let size = try #require(UniqloSizeAPIParser()
            .parseSizes(from: JSONSerialization.data(withJSONObject: response))
            .first { $0.name == "S" })
        let codes = Set(size.measurementRecords.map(\.measurementCode))
        let kinds = Set(size.measurementRecords.compactMap { record in
            MeasurementKind.allCases.first { $0.displayKind == record.displayKind }
        })

        #expect(codes.contains(.riseCrotchToWaistFront))
        #expect(codes.contains(.pantsInseamCrotchToHem))
        #expect(kinds.isDisjoint(with: [.shoulder, .chest, .sleeveLength]))
    }

    // PATH-MANUAL-COMPARE-01 · Policy Truth: same wear area can be extended manually.
    @Test func p0LongCoatAndHalfJacketAreManualOnly() {
        let product = comparisonProduct(
            name: "하이넥 사파리 하프 자켓",
            category: .outer,
            detail: .jacket,
            family: .outerwear,
            sourcePath: "아우터 > 재킷",
            measurements: GarmentMeasurements(shoulder: 50, chest: 60, totalLength: 76, sleeveLength: 62)
        )
        let coat = comparisonItem(
            name: "울 맥시 숄 롱 코트",
            category: .outer,
            detail: .coat,
            family: .outerwear,
            sourcePath: "아우터 > 롱 코트",
            measurements: GarmentMeasurements(shoulder: 52, chest: 61, totalLength: 127, sleeveLength: 50)
        )
        let matcher = ComparisonProfileMatcher()

        let automatic = matcher.match(product: product, productDetailCategory: .jacket, userFits: [coat])
        let manual = matcher.manualComparisonCompatibility(product: product, productDetailCategory: .jacket, item: coat)

        #expect(automatic.state != .compatible)
        #expect(manual.level == .extended)
        #expect(manual.reason.contains("사용자 선택 확장 비교"))
    }

    // PATH-MANUAL-COMPARE-01 · Policy Truth: different wear areas remain blocked.
    @Test func p0TopAndBottomRemainBlockedEvenWhenUserSelectsManually() {
        let product = comparisonProduct(
            name: "반팔 티셔츠",
            category: .top,
            detail: .shortSleeve,
            family: .tshirt,
            sourcePath: "상의 > 반소매 티셔츠",
            measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24)
        )
        let pants = comparisonItem(
            name: "와이드 팬츠",
            category: .bottom,
            detail: .slacks,
            family: .pants,
            sourcePath: "바지 > 긴바지",
            measurements: GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 102, sleeveLength: 0, waist: 39, hip: 52, thigh: 31)
        )

        let compatibility = ComparisonProfileMatcher().manualComparisonCompatibility(
            product: product,
            productDetailCategory: .shortSleeve,
            item: pants
        )
        #expect(compatibility.level == .blocked)
        #expect(compatibility.reason == "착용 부위가 달라 비교할 수 없어요.")
    }

    // PATH-MANUAL-COMPARE-01 · Policy Truth: outerwear needs chest plus another field.
    @Test func p0OuterWithoutChestDoesNotForceARecommendation() {
        let product = comparisonProduct(
            name: "가슴 실측 없는 사파리 재킷",
            category: .outer,
            detail: .jacket,
            family: .outerwear,
            sourcePath: "아우터 > 재킷",
            measurements: GarmentMeasurements(shoulder: 50, chest: 0, totalLength: 76, sleeveLength: 62)
        )
        let item = comparisonItem(
            name: "스타디움 재킷",
            category: .outer,
            detail: .jacket,
            family: .outerwear,
            sourcePath: "아우터 > 재킷",
            measurements: GarmentMeasurements(shoulder: 51, chest: 0, totalLength: 75, sleeveLength: 63)
        )
        let service = RecommendationService()

        #expect(service.recommend(product: product, selectedReferenceItem: item, productDetailCategory: .jacket) == nil)
        #expect(service.insufficientEvidence(product: product, selectedReferenceItem: item, productDetailCategory: .jacket) != nil)
    }

    // PATH-AUTO-COMPARE-01 · One compatible representative is the automatic basis.
    @Test func p0SingleCompatibleRepresentativeProducesAutomaticRecommendation() throws {
        let product = comparisonProduct(
            name: "새 반팔 티셔츠",
            category: .top,
            detail: .shortSleeve,
            family: .tshirt,
            sourcePath: "상의 > 반소매 티셔츠",
            measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24),
            secondSizeMeasurements: GarmentMeasurements(shoulder: 51, chest: 58, totalLength: 74, sleeveLength: 25)
        )
        let item = comparisonItem(
            name: "내 기준 반팔 티셔츠",
            category: .top,
            detail: .shortSleeve,
            family: .tshirt,
            sourcePath: "상의 > 반소매 티셔츠",
            measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24)
        )
        let service = RecommendationService()
        let plan = service.referenceSelectionPlan(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [item]
        )
        let result = try #require(service.recommend(
            product: product,
            userFits: [item],
            productDetailCategory: .shortSleeve,
            allowsGlobalFallback: false
        ))

        #expect(plan.automaticallySelectedCandidate?.userFit.id == item.id)
        #expect(result.userFit.id == item.id)
        #expect(result.recommendedSize.name == "M")
        #expect(result.calculationSnapshot != nil)
    }

    // PATH-MANUAL-COMPARE-01 · Bottom length mismatch is manual-only.
    @Test func p0ShortAndLongPantsAreManualOnly() {
        let product = comparisonProduct(
            name: "롱 와이드 팬츠",
            category: .bottom,
            detail: .longPants,
            family: .pants,
            sourcePath: "바지 > 긴바지",
            measurements: GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 104, sleeveLength: 0, waist: 39, hip: 52, thigh: 31, rise: 30, hem: 22)
        )
        let shorts = comparisonItem(
            name: "버뮤다 쇼트 팬츠",
            category: .bottom,
            detail: .shorts,
            family: .pants,
            sourcePath: "바지 > 반바지",
            measurements: GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 55, sleeveLength: 0, waist: 39, hip: 52, thigh: 31, rise: 29, hem: 27)
        )
        let matcher = ComparisonProfileMatcher()

        let automatic = matcher.match(product: product, productDetailCategory: .longPants, userFits: [shorts])
        let manual = matcher.manualComparisonCompatibility(product: product, productDetailCategory: .longPants, item: shorts)

        #expect(automatic.state != .compatible)
        #expect(manual.level == .extended)
    }

    // PATH-ALTERNATIVE-01 · Invariant: identical input and size yield the same snapshot.
    @Test func p0RecommendedSizeAndAlternativeAnalysisAgreeForSameSize() throws {
        let product = comparisonProduct(
            name: "그래픽 반팔 티셔츠",
            category: .top,
            detail: .shortSleeve,
            family: .tshirt,
            sourcePath: "상의 > 반소매 티셔츠",
            measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24),
            secondSizeMeasurements: GarmentMeasurements(shoulder: 50, chest: 57, totalLength: 73, sleeveLength: 25)
        )
        let item = comparisonItem(
            name: "내 그래픽 반팔 티셔츠",
            category: .top,
            detail: .shortSleeve,
            family: .tshirt,
            sourcePath: "상의 > 반소매 티셔츠",
            measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24)
        )
        let service = RecommendationService()
        let history = try #require(service.recommend(
            product: product,
            selectedReferenceItem: item,
            productDetailCategory: .shortSleeve
        ))
        let analysis = try #require(service.analyzeSizeWithoutSaving(
            history.recommendedSize,
            product: product,
            referenceItem: item,
            productDetailCategory: .shortSleeve,
            comparisonMethod: history.comparisonMethod,
            excludedKinds: history.measurementExclusions.filter { $0.reason == .categoryPolicy }.map(\.kind),
            scorePenalty: service.manualComparisonScorePenalty(product: product, selectedReferenceItem: item)
        ))

        #expect(analysis.recommendationScore == history.recommendationScore)
        #expect(analysis.calculationSnapshot == history.calculationSnapshot)
    }

    // PATH-AUTO-COMPARE-01 · Actual Uniqlo bottom records must not leak upper-body fields.
    @Test func p0ActualUniqloBottomRecommendationUsesOnlyBottomMeasurements() throws {
        let input = try fixture(id: "E488202", in: "Uniqlo243FitPairInputs")
        let response = try #require(input["response"])
        let parsed = try #require(UniqloSizeAPIParser()
            .parseSizes(from: JSONSerialization.data(withJSONObject: response))
            .first { $0.name == "S" })
        let size = try #require(ParsedProductSizeNormalizer.makeProductSizes(from: [parsed]).first)
        let product = Product(
            name: "코듀로이배럴레그팬츠",
            category: .bottom,
            productCode: "E488202",
            sourceURLString: "https://store-kr.uniqlo.com/kr/ko/products/E488202-000/00",
            metadata: ProductMetadata(sourceCategoryPath: "팬츠 > 와이드 팬츠 > 유틸리티"),
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            sizes: [size]
        )
        product.garmentType = .pants
        product.sleeveType = .long
        let item = UserFit(
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            sourceCategoryPath: product.sourceCategoryPath,
            brandName: "유니클로",
            productName: "내 코듀로이 팬츠",
            category: .bottom,
            detailCategory: .longPants,
            sizeName: "S",
            measurements: parsed.measurements,
            fitMemo: "",
            satisfaction: 5,
            isRepresentative: true,
            sourceProduct: product,
            sourceProductSize: size
        )
        item.garmentType = .pants
        item.sleeveType = .long
        item.measurementRecords = parsed.measurementRecords.map { $0.makeRecord(userFit: item) }
        let history = try #require(RecommendationService().recommend(
            product: product,
            selectedReferenceItem: item,
            productDetailCategory: .longPants
        ))
        let usages = history.comparedMeasurementUsages
        let kinds = Set(usages.map(\.kind))
        let allowed: Set<MeasurementKind> = [.waist, .hip, .thigh, .rise, .hem, .totalLength]

        #expect(!usages.isEmpty)
        #expect(kinds.isSubset(of: allowed))
        #expect(kinds.isDisjoint(with: [.shoulder, .chest, .sleeveLength]))
        #expect(usages.contains { $0.kind == .rise && $0.measurementCode == .riseCrotchToWaistFront })
        #expect(usages.contains { $0.kind == .totalLength && $0.measurementCode == .pantsInseamCrotchToHem })
    }

    // PATH-AUTO-COMPARE-01 · Equal candidates must remain deterministic.
    @Test func p0EqualSizeTieAlwaysKeepsFirstDisplayOrder() throws {
        let measurements = GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24)
        let product = comparisonProduct(
            name: "동점 반팔 티셔츠",
            category: .top,
            detail: .shortSleeve,
            family: .tshirt,
            sourcePath: "상의 > 반소매 티셔츠",
            measurements: measurements,
            secondSizeMeasurements: measurements
        )
        let item = comparisonItem(
            name: "내 동점 기준옷",
            category: .top,
            detail: .shortSleeve,
            family: .tshirt,
            sourcePath: "상의 > 반소매 티셔츠",
            measurements: measurements
        )

        let names = try (0..<10).map { _ in
            try #require(RecommendationService().recommend(
                product: product,
                selectedReferenceItem: item,
                productDetailCategory: .shortSleeve
            )).recommendedSize.name
        }
        #expect(Set(names) == ["M"])
    }

    // PATH-HISTORY-RELOAD-01 · Exclusions must survive in the calculation snapshot.
    @Test func p0MissingSleeveExclusionIsPersistedInSnapshot() throws {
        let product = comparisonProduct(
            name: "소매 실측 없는 반팔",
            category: .top,
            detail: .shortSleeve,
            family: .tshirt,
            sourcePath: "상의 > 반소매 티셔츠",
            measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 0)
        )
        let item = comparisonItem(
            name: "내 반팔",
            category: .top,
            detail: .shortSleeve,
            family: .tshirt,
            sourcePath: "상의 > 반소매 티셔츠",
            measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24)
        )
        let history = try #require(RecommendationService().recommend(
            product: product,
            selectedReferenceItem: item,
            productDetailCategory: .shortSleeve
        ))
        let exclusion = try #require(history.measurementExclusions.first { $0.kind == .sleeveLength })

        #expect(exclusion.reason == .missingProductValue)
        #expect(history.calculationSnapshot?.excludedMeasurements.contains(exclusion) == true)
        #expect(!history.comparedMeasurementUsages.map(\.kind).contains(.sleeveLength))
    }

    // PATH-HISTORY-RELOAD-01 · Temporary disk persistence, not the actual production store.
    @Test func p0RecommendationSurvivesTemporaryDiskReload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FitMatch-P0-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("p0.store")
        let schema = Schema(FitMatchSchemaV1.models)

        do {
            let configuration = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: FitMatchSchemaMigrationPlan.self,
                configurations: [configuration]
            )
            let context = ModelContext(container)
            let product = comparisonProduct(
                name: "저장 검증 반팔 티셔츠",
                category: .top,
                detail: .shortSleeve,
                family: .tshirt,
                sourcePath: "상의 > 반소매 티셔츠",
                measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24)
            )
            let item = comparisonItem(
                name: "내 저장 검증 반팔",
                category: .top,
                detail: .shortSleeve,
                family: .tshirt,
                sourcePath: "상의 > 반소매 티셔츠",
                measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24)
            )
            context.insert(item)
            try context.save()
            let history = try #require(RecommendationService().recommend(
                product: product,
                selectedReferenceItem: item,
                productDetailCategory: .shortSleeve
            ))
            try RecommendationHistoryStore.saveUnique(history, existing: [], modelContext: context)
        }

        let reloadConfiguration = ModelConfiguration(schema: schema, url: storeURL)
        let reloadedContainer = try ModelContainer(
            for: schema,
            migrationPlan: FitMatchSchemaMigrationPlan.self,
            configurations: [reloadConfiguration]
        )
        let reloadedContext = ModelContext(reloadedContainer)
        let histories = try reloadedContext.fetch(FetchDescriptor<RecommendationHistory>())

        #expect(histories.count == 1)
        #expect(histories.first?.recommendedSize.name == "M")
        #expect(histories.first?.calculationSnapshot != nil)
        #expect(histories.first?.comparedMeasurementUsages.map(\.kind).contains(.chest) == true)
    }

    // PATH-APP-LOAD-01 · Mirrors ContentView's startup backfill before a fresh disk reload.
    @Test func p0ExistingClosetItemSurvivesStartupBackfillAndDiskReload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FitMatch-P0-Startup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("startup.store")
        let schema = Schema(FitMatchSchemaV1.models)
        let itemID = UUID()

        do {
            let configuration = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: FitMatchSchemaMigrationPlan.self,
                configurations: [configuration]
            )
            let context = ModelContext(container)
            let legacyItem = UserFit(
                id: itemID,
                sourceName: "무신사",
                sourceCategoryPath: "상의 > 반소매 티셔츠",
                brandName: "P0",
                productName: "업데이트 전 내 반팔",
                category: .top,
                detailCategory: .shortSleeve,
                sizeName: "M",
                measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24),
                fitMemo: "기존 사용자 데이터",
                satisfaction: 5,
                isRepresentative: true
            )
            context.insert(legacyItem)
            try context.save()

            try MeasurementLegacyBackfillService.run(
                modelContext: context,
                products: [],
                userFits: [legacyItem]
            )
            #expect(legacyItem.measurementMigrationStatus == .completed)
            #expect(!legacyItem.measurementRecords.isEmpty)
        }

        let reloadConfiguration = ModelConfiguration(schema: schema, url: storeURL)
        let reloadedContainer = try ModelContainer(
            for: schema,
            migrationPlan: FitMatchSchemaMigrationPlan.self,
            configurations: [reloadConfiguration]
        )
        let reloadedContext = ModelContext(reloadedContainer)
        let items = try reloadedContext.fetch(FetchDescriptor<UserFit>())
        let reloaded = try #require(items.first { $0.id == itemID })

        #expect(items.count == 1)
        #expect(reloaded.productName == "업데이트 전 내 반팔")
        #expect(reloaded.isRepresentative)
        #expect(reloaded.measurementMigrationStatus == .completed)
        #expect(reloaded.measurementRecords.contains { $0.displayKind == .chest && $0.value == 54 })
    }

    // PATH-CATEGORY-CONFIRM-01 · Policy Truth: an ambiguous provider catch-all must not auto-select a garment.
    @Test func p0AmbiguousMusinsaOtherTopRequiresUserConfirmation() {
        let product = comparisonProduct(
            name: "멘즈 롱-슬리브드 R0 탑 / 86141R5",
            category: .top,
            detail: .other,
            family: .unknown,
            sourcePath: "스포츠/레저 > 상의 > 기타상의",
            measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 61)
        )
        product.garmentType = .unknown
        product.sleeveType = .unknown
        let closetItem = comparisonItem(
            name: "내 긴팔 티셔츠",
            category: .top,
            detail: .longSleeve,
            family: .tshirt,
            sourcePath: "상의 > 긴소매 티셔츠",
            measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 61)
        )
        let classification = ParsedClosetClassification.resolve(
            category: .top,
            detailCategory: .other,
            sourceDepths: ["스포츠/레저", "상의", "기타상의", nil],
            sourcePath: "스포츠/레저 > 상의 > 기타상의",
            productName: product.name
        )
        let result = ComparisonProfileMatcher().match(
            product: product,
            productDetailCategory: .other,
            userFits: [closetItem]
        )

        #expect(classification == nil)
        #expect(result.state != .compatible)
        #expect(result.compatibleCandidates.isEmpty)
    }

    // PATH-SHARE-DEEPLINK-01 · Headless coverage ends at the app-group handoff store.
    @Test func p0SharedURLStoreConsumesOnlyTheExpectedURL() throws {
        let suiteName = "FitMatch.P0.SharedURL.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SharedURLStore(defaults: defaults)
        let expected = try #require(URL(string: "https://www.musinsa.com/products/6294035"))

        store.savePendingProductURL(expected)
        #expect(store.clearPendingProductURL(ifMatching: "https://www.musinsa.com/products/other") == false)
        #expect(store.pendingProductURL() == expected.absoluteString)
        #expect(store.consumePendingProductURL() == expected.absoluteString)
        #expect(store.pendingProductURL() == nil)
    }

    // PATH-STATE-RETRY-01 · Controlled completion, no arbitrary sleeps.
    @Test func p0LateFirstRequestCannotOverwriteTheLatestProduct() async throws {
        let parser = P0ControlledProductParser()
        let service = ProductURLParserService(musinsaParser: parser, uniqloParser: parser)
        let viewModel = ShoppingProductViewModel(
            initialURL: "https://www.musinsa.com/products/first",
            parserService: service,
            metricsRecorder: P0NoopMetricsRecorder()
        )

        let first = Task { await viewModel.loadProductInfoFromURL() }
        await parser.waitUntilPending("first")
        viewModel.productURL = "https://www.musinsa.com/products/second"
        let second = Task { await viewModel.loadProductInfoFromURL() }
        await parser.waitUntilPending("second")
        parser.complete("second")
        #expect(await second.value)
        parser.complete("first")
        #expect(await first.value == false)

        #expect(viewModel.productName == "second")
        #expect(viewModel.productCode == "second")
        #expect(viewModel.errorMessage == nil)
    }

    // PATH-STATE-RETRY-01 · Sequential A → B → A must restore A without carrying B state.
    @Test func p0SequentialAToBToARestoresTheOriginalProductState() async {
        let parser = P0ControlledProductParser()
        let service = ProductURLParserService(musinsaParser: parser, uniqloParser: parser)
        let viewModel = ShoppingProductViewModel(
            initialURL: "https://www.musinsa.com/products/A",
            parserService: service,
            metricsRecorder: P0NoopMetricsRecorder()
        )

        let firstA = Task { await viewModel.loadProductInfoFromURL() }
        await parser.waitUntilPending("A")
        parser.complete("A")
        #expect(await firstA.value)
        let firstAName = viewModel.productName
        let firstACode = viewModel.productCode
        let firstACategory = viewModel.category
        let firstADetail = viewModel.detailCategory
        let firstASizeNames = viewModel.sizeOptions.map(\.sizeName)

        viewModel.productURL = "https://www.musinsa.com/products/B"
        let b = Task { await viewModel.loadProductInfoFromURL() }
        await parser.waitUntilPending("B")
        parser.complete("B")
        #expect(await b.value)
        #expect(viewModel.productName == "B")
        #expect(viewModel.productCode == "B")

        viewModel.productURL = "https://www.musinsa.com/products/A"
        let secondA = Task { await viewModel.loadProductInfoFromURL() }
        await parser.waitUntilPending("A")
        parser.complete("A")
        #expect(await secondA.value)

        #expect(viewModel.productName == firstAName)
        #expect(viewModel.productCode == firstACode)
        #expect(viewModel.category == firstACategory)
        #expect(viewModel.detailCategory == firstADetail)
        #expect(viewModel.sizeOptions.map(\.sizeName) == firstASizeNames)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.hasLoadedProductInfo)
    }

    // PATH-STATE-RETRY-01 · A successful retry clears the previous user-facing error.
    @Test func p0FailureThenSuccessClearsStaleError() async {
        let parser = P0ControlledProductParser()
        let service = ProductURLParserService(musinsaParser: parser, uniqloParser: parser)
        let viewModel = ShoppingProductViewModel(
            initialURL: "https://www.musinsa.com/products/failure",
            parserService: service,
            metricsRecorder: P0NoopMetricsRecorder()
        )

        let failedLoad = Task { await viewModel.loadProductInfoFromURL() }
        await parser.waitUntilPending("failure")
        parser.fail("failure")
        #expect(await failedLoad.value == false)
        #expect(viewModel.errorMessage != nil)

        viewModel.productURL = "https://www.musinsa.com/products/retry"
        let retry = Task { await viewModel.loadProductInfoFromURL() }
        await parser.waitUntilPending("retry")
        parser.complete("retry")
        #expect(await retry.value)
        #expect(viewModel.productName == "retry")
        #expect(viewModel.errorMessage == nil)
    }

    // PATH-URL-COMPARE-01 / PATH-STATE-RETRY-01 · Partial metadata remains visible, then retry fully recovers.
    @Test func p0PartialProductLoadExplainsMissingSizesAndRetryRecovers() async {
        let parser = P0ControlledProductParser()
        let service = ProductURLParserService(musinsaParser: parser, uniqloParser: parser)
        let viewModel = ShoppingProductViewModel(
            initialURL: "https://www.musinsa.com/products/partial",
            parserService: service,
            metricsRecorder: P0NoopMetricsRecorder()
        )

        let partialLoad = Task { await viewModel.loadProductInfoFromURL() }
        await parser.waitUntilPending("partial")
        parser.completePartially("partial")
        #expect(await partialLoad.value == false)
        #expect(viewModel.hasLoadedProductInfo)
        #expect(viewModel.productName == "partial")
        #expect(viewModel.productCode == "partial")
        #expect(viewModel.errorMessage?.contains("사이즈") == true)
        #expect(viewModel.sizeOptions.count == 1)

        viewModel.productURL = "https://www.musinsa.com/products/recovered"
        let retry = Task { await viewModel.loadProductInfoFromURL() }
        await parser.waitUntilPending("recovered")
        parser.complete("recovered")
        #expect(await retry.value)
        #expect(viewModel.productName == "recovered")
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.hasLoadedProductInfo)
    }

    private func corpus(named resource: String) throws -> [[String: Any]] {
        let bundle = Bundle(for: FitMatchP0BundleToken.self)
        let url = try #require(bundle.url(forResource: resource, withExtension: "json"))
        return try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]]
        )
    }

    private func fixture(id: String, in resource: String) throws -> [String: Any] {
        try #require(corpus(named: resource).first { $0["product_id"] as? String == id })
    }

    private func sourceDepths(_ path: String) -> [String] {
        path.components(separatedBy: ">").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }

    private func comparisonProduct(
        name: String,
        category: ClothingCategory,
        detail: ClosetDetailCategory,
        family: ComparisonGarmentFamily,
        sourcePath: String,
        measurements: GarmentMeasurements,
        secondSizeMeasurements: GarmentMeasurements? = nil
    ) -> Product {
        let first = ProductSize(name: "M", measurements: measurements, displayOrder: 0)
        var sizes = [first]
        if let secondSizeMeasurements {
            sizes.append(ProductSize(name: "L", measurements: secondSizeMeasurements, displayOrder: 1))
        }
        let product = Product(
            name: name,
            category: category,
            productCode: "P0-\(UUID().uuidString)",
            sourceURLString: "https://www.musinsa.com/products/p0",
            metadata: ProductMetadata(sourceCategoryPath: sourcePath, sizeType: category.serviceGroup == .bottom ? "3" : "5"),
            sourceName: "무신사",
            sizes: sizes
        )
        product.garmentType = family
        product.sleeveType = category.serviceGroup == .bottom ? .long : .short
        for size in sizes {
            size.measurementRecords = comparisonRecords(
                measurements: size.measurements,
                category: category,
                productSize: size
            )
        }
        return product
    }

    private func comparisonItem(
        name: String,
        category: ClothingCategory,
        detail: ClosetDetailCategory,
        family: ComparisonGarmentFamily,
        sourcePath: String,
        measurements: GarmentMeasurements
    ) -> UserFit {
        let item = UserFit(
            sourceName: "무신사",
            sourceCategoryPath: sourcePath,
            brandName: "P0",
            productName: name,
            category: category,
            detailCategory: detail,
            sizeName: "M",
            measurements: measurements,
            fitMemo: "",
            satisfaction: 5,
            isRepresentative: true
        )
        item.garmentType = family
        item.sleeveType = category.serviceGroup == .bottom ? .long : .short
        item.measurementRecords = comparisonRecords(
            measurements: measurements,
            category: category,
            userFit: item
        )
        return item
    }

    private func comparisonRecords(
        measurements: GarmentMeasurements,
        category: ClothingCategory,
        productSize: ProductSize? = nil,
        userFit: UserFit? = nil
    ) -> [GarmentMeasurementRecord] {
        let codes: [MeasurementKind: MeasurementCode] = category.serviceGroup == .bottom
            ? [.waist: .waistWidthEdgeToEdge, .hip: .hipWidthAtWidest, .thigh: .thighWidthCrotchToOuter,
               .rise: .riseCrotchToWaistFront, .hem: .hemWidthEdgeToEdge, .totalLength: .pantsOutseamWaistToHem]
            : [.shoulder: .shoulderWidthSeamToSeam, .chest: .chestWidthPitToPit,
               .totalLength: .bodyLengthHPSToHemFront, .sleeveLength: .sleeveShoulderSeamToCuff,
               .hem: .hemWidthEdgeToEdge]

        return codes.compactMap { kind, code in
            let value = measurements.value(for: kind)
            guard value > 0 else { return nil }
            return GarmentMeasurementRecord(
                value: value,
                measurementCode: code,
                displayKind: kind.displayKind,
                methodSource: "musinsa",
                methodProfile: "p0_official",
                inputSource: .importedSizeChart,
                mappingVersion: "p0_source_truth_v1",
                rawCode: kind.rawValue,
                rawLabel: kind.title,
                rawValueText: String(value),
                evidenceLevel: .officialText,
                semanticStatus: .mapped,
                productSize: productSize,
                userFit: userFit
            )
        }
    }
}

@MainActor
private final class P0ControlledProductParser: ProductURLParsing {
    private var continuations: [String: CheckedContinuation<ParsedProductInfo, Error>] = [:]

    func canParse(_ url: URL) -> Bool { true }

    func parse(from url: URL) async throws -> ParsedProductInfo {
        let key = url.lastPathComponent
        return try await withCheckedThrowingContinuation { continuation in
            continuations[key] = continuation
        }
    }

    func complete(_ key: String) {
        guard let continuation = continuations.removeValue(forKey: key) else { return }
        continuation.resume(returning: ParsedProductInfo(
            sourceURL: URL(string: "https://www.musinsa.com/products/\(key)")!,
            sourceType: .marketplace,
            sourceName: "무신사",
            brandName: "P0",
            productName: key,
            category: .top,
            detailCategory: .shortSleeve,
            sizes: [ParsedProductSize(
                name: "M",
                measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24)
            )],
            productID: key,
            sourceCategoryPath: "상의 > 반소매 티셔츠",
            productTargetGender: .unisex
        ))
    }

    func fail(_ key: String) {
        continuations.removeValue(forKey: key)?.resume(throwing: P0ControlledParserError.failed)
    }

    func completePartially(_ key: String) {
        guard let continuation = continuations.removeValue(forKey: key) else { return }
        continuation.resume(throwing: ProductURLParserPartialError(productInfo: ParsedProductInfo(
            sourceURL: URL(string: "https://www.musinsa.com/products/\(key)")!,
            sourceType: .marketplace,
            sourceName: "무신사",
            brandName: "P0",
            productName: key,
            category: .top,
            detailCategory: .shortSleeve,
            sizes: [],
            productID: key,
            sourceCategoryPath: "상의 > 반소매 티셔츠",
            productTargetGender: .unisex
        )))
    }

    func waitUntilPending(_ key: String) async {
        while continuations[key] == nil {
            await Task.yield()
        }
    }
}

private enum P0ControlledParserError: Error {
    case failed
}

private struct P0NoopMetricsRecorder: FitMatchMetricsRecording {
    func record(_ event: FitMatchMetricEvent) {}
}
