import Foundation
import SwiftData
import Testing
@testable import FitMatch

private final class ThreeProductFixtureBundleToken {}

@MainActor
struct ProductLevelFallbackRegressionTests {
    @Test func musinsaOptionOrderPrefixIsRemovedOnlyFromValidSizeTokens() {
        #expect(SizeTokenNormalizer.displayName(for: "0. S") == "S")
        #expect(SizeTokenNormalizer.displayName(for: "12. XL") == "XL")
        #expect(SizeTokenNormalizer.displayName(for: "1. 빈티지") == "1. 빈티지")
        #expect(ParsedProductSizeNormalizer.normalizedSizeKey(for: "0. S") == "S")
    }

    @Test func resolvedLongPantsWithEnoughMeasurementsRecoverProductFallbackEligibility() {
        let size = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 0, totalLength: 104, sleeveLength: 0,
                waist: 39, hip: 53, thigh: 33, rise: 31, hem: 24
            )
        )
        let product = Product(
            name: "하프 밴딩 세미 커브드 팬츠",
            category: .bottom,
            sourceName: "무신사",
            sizes: [size]
        )
        product.canonicalEligibility = false
        product.canonicalResolutionMethod = "product_level_fallback"
        product.garmentType = .pants
        product.sleeveType = .long

        let item = UserFit(
            sourceName: "무신사",
            brandName: "테스트",
            gender: .men,
            productName: "긴바지",
            category: .bottom,
            detailCategory: .longPants,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 0, totalLength: 104, sleeveLength: 0,
                waist: 39, hip: 53, thigh: 33, rise: 31, hem: 24
            ),
            fitMemo: "",
            satisfaction: 3
        )
        item.genderCode = "male"
        item.garmentType = .pants
        item.sleeveType = .long

        let compatibility = ComparisonProfileMatcher().comparisonCompatibility(
            product: product,
            productDetailCategory: .longPants,
            item: item
        )

        #expect(product.canonicalEligibility == true)
        #expect(compatibility.level.isAllowed)
        let secondCompatibility = ComparisonProfileMatcher().comparisonCompatibility(
            product: product,
            productDetailCategory: .longPants,
            item: item
        )
        #expect(product.canonicalEligibility == true)
        #expect(secondCompatibility.level == compatibility.level)
        #expect(secondCompatibility.reason == compatibility.reason)
    }

    @Test func unresolvedFallbackWithoutEnoughMeasurementsStaysBlocked() {
        let product = Product(
            name: "기타 상품",
            category: .bottom,
            sourceName: "무신사",
            sizes: [ProductSize(
                name: "FREE",
                measurements: GarmentMeasurements(
                    shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0,
                    waist: 39
                )
            )]
        )
        product.canonicalEligibility = false
        product.canonicalResolutionMethod = "product_level_fallback"
        product.garmentType = .pants
        product.sleeveType = .long

        _ = ComparisonProfileMatcher().profile(for: product, detailCategory: .longPants)
        #expect(product.canonicalEligibility == false)
    }

    @Test func fallbackRecoveryRejectsSetsShortLengthsAndNonFallbackPolicies() {
        let measurements = GarmentMeasurements(
            shoulder: 0, chest: 0, totalLength: 104, sleeveLength: 0,
            waist: 39, hip: 53, thigh: 33, rise: 31, hem: 24
        )
        let cases: [(String, ComparisonLengthType, String)] = [
            ("팬츠 포함 상하의 세트", .long, "product_level_fallback"),
            ("하프 밴딩 쇼츠 팬츠", .short, "product_level_fallback"),
            ("하프 밴딩 긴바지 팬츠", .long, "existing_db_decision")
        ]
        for (name, length, method) in cases {
            let product = Product(
                name: name,
                category: .bottom,
                sourceName: "무신사",
                sizes: [ProductSize(name: "M", measurements: measurements)]
            )
            product.canonicalEligibility = false
            product.canonicalResolutionMethod = method
            product.garmentType = .pants
            product.sleeveType = length
            _ = ComparisonProfileMatcher().profile(for: product, detailCategory: .longPants)
            #expect(product.canonicalEligibility == false, Comment(rawValue: name))
        }
    }

    @Test func storedActualSizeFixturesPreserveSixMeasurementsAndChooseHighestScore() throws {
        let fixtures = try loadActualSizeFixtures()
        #expect(Set(fixtures.keys) == Set(["6566713", "5020093", "3467384"]))

        let expectedNames: [String: [String]] = [
            "6566713": ["S", "M", "L", "XL"],
            "5020093": ["S", "M", "L", "XL"],
            "3467384": ["S", "M", "L", "XL"]
        ]
        for (id, sizes) in fixtures {
            let productSizes = ParsedProductSizeNormalizer.makeProductSizes(from: sizes)
            #expect(productSizes.map(\.name) == expectedNames[id])
            for size in productSizes {
                let kinds = Set(size.measurementRecords.map(\.displayKind))
                #expect(kinds.isSuperset(of: [.waist, .hip, .thigh, .rise, .hem, .totalLength]))
            }
        }

        let products = fixtures.mapValues { makeFixtureProduct(sizes: $0) }
        for (targetID, target) in products {
            for (referenceID, reference) in products where referenceID != targetID {
                for referenceSize in reference.sizes {
                    let item = makeFixtureUserFit(product: reference, size: referenceSize)
                    let result = try #require(RecommendationService().recommend(
                        product: target,
                        selectedReferenceItem: item,
                        productDetailCategory: .longPants
                    ))
                    let analyses = target.sizes.compactMap {
                        RecommendationService().analyzeSizeWithoutSaving(
                            $0,
                            product: target,
                            referenceItem: item,
                            productDetailCategory: .longPants,
                            comparisonMethod: "사용자 선택 직접 비교",
                            excludedKinds: [],
                            scorePenalty: 0
                        )
                    }
                    let bestScore = try #require(analyses.map(\.recommendationScore).max())
                    #expect(result.recommendationScore == bestScore)
                    #expect(analyses.contains {
                        $0.productSize.name == result.recommendedSize.name
                            && $0.recommendationScore == bestScore
                    })
                    #expect(Set(result.comparedMeasurementUsages.map(\.kind))
                        .isSuperset(of: [.waist, .hip, .thigh, .rise, .hem, .totalLength]))
                }
            }
        }
    }

    @Test func legacyStoredPrefixedSizeAndFallbackEligibilityRecoverAfterDiskReload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FitMatch-Legacy-Pants-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("legacy.store")
        let schema = Schema(FitMatchSchemaV1.models)
        let productID = UUID()
        let itemID = UUID()
        let measurements = GarmentMeasurements(
            shoulder: 0, chest: 0, totalLength: 104, sleeveLength: 0,
            waist: 39, hip: 53, thigh: 33, rise: 31, hem: 24
        )

        do {
            let configuration = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: FitMatchSchemaMigrationPlan.self,
                configurations: [configuration]
            )
            let context = ModelContext(container)
            let product = Product(
                id: productID,
                name: "레거시 세미 커브드 팬츠",
                category: .bottom,
                sourceName: "무신사",
                sizes: [ProductSize(name: "0. S", measurements: measurements)]
            )
            product.sizes[0].measurementRecords = officialBottomRecords(
                measurements: measurements,
                productSize: product.sizes[0]
            )
            product.canonicalEligibility = false
            product.canonicalResolutionMethod = "product_level_fallback"
            product.garmentType = .pants
            product.sleeveType = .long
            let item = UserFit(
                id: itemID,
                sourceName: "무신사",
                brandName: "레거시",
                gender: .men,
                productName: "기존 저장 긴바지",
                category: .bottom,
                detailCategory: .longPants,
                sizeName: "0. S",
                measurements: measurements,
                fitMemo: "",
                satisfaction: 3
            )
            item.canonicalEligibility = false
            item.canonicalResolutionMethod = "product_level_fallback"
            item.garmentType = .pants
            item.sleeveType = .long
            item.replaceMeasurementRecords(with: product.sizes[0].measurementRecords)
            context.insert(product)
            context.insert(item)
            try context.save()
        }

        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: FitMatchSchemaMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let products = try context.fetch(FetchDescriptor<Product>())
        let items = try context.fetch(FetchDescriptor<UserFit>())
        let product = try #require(products.first { $0.id == productID })
        let item = try #require(items.first { $0.id == itemID })

        try MeasurementLegacyBackfillService.run(
            modelContext: context,
            products: products,
            userFits: items
        )

        #expect(product.sizes.first?.name == "0. S")
        #expect(SizeTokenNormalizer.displayName(for: product.sizes[0].name) == "S")
        #expect(SizeTokenNormalizer.displayName(for: item.sizeName) == "S")
        #expect(!product.sizes[0].measurementRecords.isEmpty)
        #expect(!item.measurementRecords.isEmpty)
        let compatibility = ComparisonProfileMatcher().manualComparisonCompatibility(
            product: product,
            productDetailCategory: .longPants,
            item: item
        )
        #expect(compatibility.level.isAllowed)
        #expect(product.canonicalEligibility == true)
        #expect(item.canonicalEligibility == true)
        let result = try #require(RecommendationService().recommend(
            product: product,
            selectedReferenceItem: item,
            productDetailCategory: .longPants
        ))
        #expect(result.recommendedSize.name == "0. S")
        #expect(SizeTokenNormalizer.displayName(for: result.recommendedSize.name) == "S")
    }

    private func loadActualSizeFixtures() throws -> [String: [ParsedProductSize]] {
        let bundle = Bundle(for: ThreeProductFixtureBundleToken.self)
        let url = try #require(bundle.url(
            forResource: "ThreeProductActualSizeFixtures",
            withExtension: "json"
        ))
        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        return try Dictionary(uniqueKeysWithValues: root.map { entry in
            let id = try #require(entry["productID"] as? String)
            let data = try JSONSerialization.data(withJSONObject: ["data": try #require(entry["data"])])
            let parsed = try MusinsaActualSizeAPIParser().parseActualSize(from: data)
            return (id, parsed.sizes)
        })
    }

    private func officialBottomRecords(
        measurements: GarmentMeasurements,
        productSize: ProductSize
    ) -> [GarmentMeasurementRecord] {
        let codes: [(MeasurementKind, MeasurementCode)] = [
            (.waist, .waistWidthEdgeToEdge),
            (.hip, .hipWidthAtWidest),
            (.thigh, .thighWidthCrotchToOuter),
            (.rise, .riseCrotchToWaistFront),
            (.hem, .hemWidthEdgeToEdge),
            (.totalLength, .pantsOutseamWaistToHem)
        ]
        return codes.map { kind, code in
            GarmentMeasurementRecord(
                value: measurements.value(for: kind),
                measurementCode: code,
                displayKind: kind.displayKind,
                methodSource: "musinsa",
                methodProfile: "legacy_official",
                inputSource: .importedSizeChart,
                mappingVersion: "legacy_source_truth_v1",
                rawCode: kind.rawValue,
                rawLabel: kind.title,
                rawValueText: String(measurements.value(for: kind)),
                evidenceLevel: .officialText,
                semanticStatus: .mapped,
                productSize: productSize
            )
        }
    }

    private func makeFixtureProduct(sizes: [ParsedProductSize]) -> Product {
        let product = Product(
            name: "테스트 긴바지 팬츠",
            category: .bottom,
            sourceName: "무신사",
            sizes: ParsedProductSizeNormalizer.makeProductSizes(from: sizes)
        )
        product.categoryCode = "bottoms"
        product.garmentType = .pants
        product.sleeveType = .long
        product.canonicalEligibility = true
        return product
    }

    private func makeFixtureUserFit(product: Product, size: ProductSize) -> UserFit {
        let item = UserFit(
            sourceName: "무신사",
            brandName: "fixture",
            gender: .men,
            productName: product.name,
            category: .bottom,
            detailCategory: .longPants,
            sizeName: size.name,
            measurements: size.measurements,
            fitMemo: "fixture",
            satisfaction: 3,
            sourceProduct: product,
            sourceProductSize: size
        )
        item.genderCode = UserGender.men.taxonomyCode
        item.categoryCode = "bottoms"
        item.detailCategoryCode = "long_pants"
        item.garmentType = .pants
        item.sleeveType = .long
        item.canonicalEligibility = true
        item.replaceMeasurementRecords(with: size.measurementRecords)
        return item
    }
}

@MainActor
@Suite(.enabled(
    if: ProcessInfo.processInfo.arguments.contains("-fitmatchRunThreeProductComparison")
        || ProcessInfo.processInfo.arguments.contains("-fitmatchRunLiveTests")
        || ProcessInfo.processInfo.environment["FITMATCH_RUN_THREE_PRODUCT_COMPARISON"] == "1",
    "세 상품 실서버 전수 비교는 환경 변수로 명시 실행합니다."
))
struct LiveThreeProductComparisonTests {
    private let productIDs = ["6566713", "5020093", "3467384"]

    @Test func uniqloOxfordShirtLReferenceAutomaticallyComparesNonIronShirt() async throws {
        let referenceURL = try #require(URL(string: "https://www.uniqlo.com/kr/ko/products/E450259-000/00"))
        let targetURL = try #require(URL(string: "https://www.uniqlo.com/kr/ko/products/E475943-000"))
        let referenceInfo = try await UniqloParser().parse(from: referenceURL)
        let targetInfo = try await UniqloParser().parse(from: targetURL)
        let referenceProduct = makeProduct(referenceInfo)
        let targetProduct = makeProduct(targetInfo)
        let referenceSize = try #require(referenceProduct.sizes.first { $0.name == "L" })
        let referenceItem = makeUserFit(referenceInfo, product: referenceProduct, size: referenceSize)
        referenceItem.isRepresentative = true

        #expect(referenceInfo.category == .top)
        #expect(referenceInfo.detailCategory == .shirt)
        #expect(targetInfo.category == .top)
        #expect(targetInfo.detailCategory == .shirt)
        #expect(referenceSize.measurements.totalLength == 77)
        #expect(referenceSize.measurements.shoulder == 48)
        #expect(referenceSize.measurements.chest == 60)
        #expect(referenceSize.measurements.sleeveLength == 85.5)

        let service = RecommendationService()
        let plan = service.referenceSelectionPlan(
            product: targetProduct,
            productDetailCategory: targetInfo.detailCategory,
            userFits: [referenceItem]
        )
        let selected = try #require(plan.automaticallySelectedCandidate)
        #expect(selected.userFit.id == referenceItem.id)

        let result = try #require(service.recommend(
            product: targetProduct,
            selectedReferenceItem: referenceItem,
            productDetailCategory: targetInfo.detailCategory
        ))
        #expect(result.recommendedSize.name == "L")
        #expect(result.recommendationScore == 94)
        #expect(Set(result.comparedMeasurementUsages.map(\.kind)) == [
            .shoulder, .chest, .totalLength, .sleeveLength
        ])
        #expect(result.measurementExclusions.isEmpty)
        print(
            "UNIQLO_USER_FLOW reference=E450259/L target=E475943 "
                + "category=\(targetInfo.category.rawValue)/\(targetInfo.detailCategory.rawValue) "
                + "automatic=true recommended=\(result.recommendedSize.name) "
                + "score=\(result.recommendationScore)"
        )
    }

    @Test func comparesEverySizeAcrossAllDirectedProductPairs() async throws {
        var parsed: [(info: ParsedProductInfo, product: Product)] = []
        for id in productIDs {
            let url = try #require(URL(string: "https://www.musinsa.com/products/\(id)"))
            let info = try await MusinsaParser().parse(from: url)
            let product = makeProduct(info)
            #expect(!product.sizes.isEmpty, "\(id): 비교할 실측 사이즈가 필요합니다.")
            #expect(product.sizes.map(\.name) == ["S", "M", "L", "XL"], "\(id): 사용자 표시 사이즈가 정규화되어야 합니다.")
            parsed.append((info, product))
            print("THREE_PRODUCT \(id) | \(info.brandName) | \(info.productName) | \(info.category.rawValue)/\(info.detailCategory.rawValue) | sizes=\(product.sizes.map(\.name).joined(separator: ","))")
        }

        var attempted = 0
        var completed = 0
        for target in parsed {
            for reference in parsed where reference.info.productID != target.info.productID {
                for referenceSize in reference.product.sizes {
                    attempted += 1
                    let item = makeUserFit(reference.info, product: reference.product, size: referenceSize)
                    let compatibility = ComparisonProfileMatcher().manualComparisonCompatibility(
                        product: target.product,
                        productDetailCategory: target.info.detailCategory,
                        item: item
                    )
                    guard compatibility.level.isAllowed else {
                        print("THREE_RESULT target=\(target.info.productID) reference=\(reference.info.productID)/\(referenceSize.name) status=BLOCKED reason=\(compatibility.reason)")
                        continue
                    }
                    guard let history = RecommendationService().recommend(
                        product: target.product,
                        selectedReferenceItem: item,
                        productDetailCategory: target.info.detailCategory
                    ) else {
                        print("THREE_RESULT target=\(target.info.productID) reference=\(reference.info.productID)/\(referenceSize.name) status=INSUFFICIENT")
                        continue
                    }
                    completed += 1
                    let differences = history.comparedMeasurementUsages.map { usage in
                        let value = history.measurementDifferences.value(for: usage.kind)
                        return "\(usage.kind.rawValue)=\(String(format: "%.1f", value))"
                    }.joined(separator: ",")
                    print("THREE_RESULT target=\(target.info.productID) reference=\(reference.info.productID)/\(referenceSize.name) status=OK recommended=\(history.recommendedSize.name) score=\(history.recommendationScore) method=\(history.comparisonMethod) differences=\(differences)")
                }
            }
        }
        print("THREE_SUMMARY attempted=\(attempted) completed=\(completed)")
        #expect(attempted > 0)
        #expect(completed == attempted)
    }

    private func makeProduct(_ info: ParsedProductInfo) -> Product {
        let viewModel = ShoppingProductViewModel(initialURL: info.sourceURL.absoluteString)
        viewModel.apply(info)
        return viewModel.makeProductForClosetRegistration(brand: viewModel.makeBrand())!
    }

    private func makeUserFit(_ info: ParsedProductInfo, product: Product, size: ProductSize) -> UserFit {
        let item = UserFit(
            sourceType: product.sourceType,
            sourceName: product.sourceDisplayName,
            sourceCategoryPath: product.sourceCategoryPath,
            sourceCategoryDepth1: product.sourceCategoryDepth1,
            sourceCategoryDepth2: product.sourceCategoryDepth2,
            sourceCategoryDepth3: product.sourceCategoryDepth3,
            sourceCategoryDepth4: product.sourceCategoryDepth4,
            brandName: info.brandName,
            gender: UserGender.productTarget(from: info.productMetadata.genderCodes),
            productName: info.productName,
            category: info.category,
            detailCategory: info.detailCategory,
            sizeName: size.name,
            measurements: size.measurements,
            fitMemo: "live-three-product-comparison",
            satisfaction: 3,
            sourceProduct: product,
            sourceProductSize: size
        )
        item.genderCode = UserGender.productTarget(from: info.productMetadata.genderCodes).taxonomyCode
        if let classification = ParsedClosetClassification.resolve(product: product, detailCategory: info.detailCategory) {
            item.categoryCode = classification.categoryCode
            item.detailCategoryCode = classification.detailCode
            item.normalizedProductTypeCode = classification.normalizedProductTypeCode
            item.garmentType = classification.garmentFamily
            item.sleeveType = classification.lengthType
            item.constructionType = classification.constructionType
        }
        item.replaceMeasurementRecords(with: size.measurementRecords)
        CanonicalComparisonProfileResolver().apply(product.canonicalProfileSnapshot, to: item)
        _ = ComparisonProfileMatcher().profile(for: item)
        return item
    }
}
