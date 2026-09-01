import Foundation
import SwiftData
import Testing
@testable import FitMatch

@MainActor
struct FitMatchP0RemediationRegressionTests {
    @Test func completedVNextHistoryPreservesExactServerIdentityAcrossReload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FitMatch-vNext-History-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("history.store")
        let schema = Schema(FitMatchSchemaV1.models)
        let serverProductID = UUID()
        let serverRecommendedSizeID = UUID()
        let serverAlternateSizeID = UUID()
        let authorizedSizeIDs = Set([serverRecommendedSizeID, serverAlternateSizeID])
        let historyID = UUID()

        do {
            let configuration = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let legacySize = makeSize(id: UUID(), name: "M", chest: 50)
            let legacyProduct = makeProduct(
                id: UUID(),
                sizes: [legacySize]
            )
            let reference = makeReference(name: "기존 기준 옷")
            context.insert(legacyProduct)
            context.insert(reference)
            try context.save()

            let recommended = makeSize(id: serverRecommendedSizeID, name: "M", chest: 51)
            let alternate = makeSize(id: serverAlternateSizeID, name: "L", chest: 54)
            let serverProduct = makeProduct(
                id: serverProductID,
                sizes: [recommended, alternate]
            )
            let history = makeCompletedHistory(
                id: historyID,
                product: serverProduct,
                size: recommended,
                reference: reference
            )

            try saveCompletedVNextUnderTest(
                history,
                existing: [],
                modelContext: context
            )
        }

        let reloadConfiguration = ModelConfiguration(schema: schema, url: storeURL)
        let reloadedContainer = try ModelContainer(
            for: schema,
            configurations: [reloadConfiguration]
        )
        let reloadedContext = ModelContext(reloadedContainer)
        let histories = try reloadedContext.fetch(FetchDescriptor<RecommendationHistory>())
        let history = try #require(histories.first { $0.id == historyID })

        // The server IDs stay in the immutable completed snapshot.  The local
        // cache deliberately owns a per-comparison projection so a later
        // comparison of this same retailer product cannot mutate this row.
        #expect(history.product.id == VNextHistoryProjectionIdentity.productID(
            comparisonID: historyID
        ))
        #expect(history.product.id != serverProductID)
        #expect(history.product.canonicalSourceIdentity?.contains(
            "target=\(serverProductID.uuidString.lowercased())"
        ) == true)
        #expect(history.product.canonicalSourceIdentity?.contains(
            "comparison=\(historyID.uuidString.lowercased())"
        ) == true)
        #expect(history.recommendedSize.id == VNextHistoryProjectionIdentity.productSizeID(
            comparisonID: historyID,
            productSizeID: serverRecommendedSizeID
        ))
        let projectedSizeIDs = Set(history.product.sizes.map(\.id))
        #expect(projectedSizeIDs == Set(authorizedSizeIDs.map {
            VNextHistoryProjectionIdentity.productSizeID(
                comparisonID: historyID,
                productSizeID: $0
            )
        }))
    }

    @Test func completedVNextHistoriesRemainDistinctForDifferentReferences() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let productID = UUID()
        let sizeID = UUID()
        let firstHistoryID = UUID()
        let secondHistoryID = UUID()
        let size = makeSize(id: sizeID, name: "M", chest: 51)
        let product = makeProduct(id: productID, sizes: [size])
        let firstReference = makeReference(name: "기준 옷 A")
        let secondReference = makeReference(name: "기준 옷 B")
        context.insert(firstReference)
        context.insert(secondReference)
        try context.save()

        let first = makeCompletedHistory(
            id: firstHistoryID,
            product: product,
            size: size,
            reference: firstReference
        )
        try saveCompletedVNextUnderTest(first, existing: [], modelContext: context)

        // A second completed comparison of the same remote Product comes in
        // with the same server identity, but it must receive a different
        // local immutable projection.
        let secondProduct = makeProduct(
            id: productID,
            sizes: [makeSize(id: sizeID, name: "M", chest: 51)]
        )
        let second = makeCompletedHistory(
            id: secondHistoryID,
            product: secondProduct,
            size: try #require(secondProduct.sizes.first),
            reference: secondReference
        )
        let existing = try context.fetch(FetchDescriptor<RecommendationHistory>())
        try saveCompletedVNextUnderTest(second, existing: existing, modelContext: context)

        let duplicateIDReplay = makeCompletedHistory(
            id: secondHistoryID,
            product: secondProduct,
            size: try #require(secondProduct.sizes.first),
            reference: firstReference
        )
        try saveCompletedVNextUnderTest(
            duplicateIDReplay,
            existing: try context.fetch(FetchDescriptor<RecommendationHistory>()),
            modelContext: context
        )

        let saved = try context.fetch(FetchDescriptor<RecommendationHistory>())
        #expect(Set(saved.map(\.id)) == Set([firstHistoryID, secondHistoryID]))
        #expect(Set(saved.map(\.userFit.id)) == Set([
            VNextHistoryProjectionIdentity.referenceID(
                comparisonID: firstHistoryID,
                clientItemID: firstReference.id
            ),
            VNextHistoryProjectionIdentity.referenceID(
                comparisonID: secondHistoryID,
                clientItemID: secondReference.id
            )
        ]))
        #expect(Set(saved.map(\.product.id)) == Set([
            VNextHistoryProjectionIdentity.productID(comparisonID: firstHistoryID),
            VNextHistoryProjectionIdentity.productID(comparisonID: secondHistoryID)
        ]))
        #expect(saved.allSatisfy {
            $0.product.canonicalSourceIdentity?.contains(
                "target=\(productID.uuidString.lowercased())"
            ) == true
        })
        #expect(Set(saved.map(\.recommendedSize.id)) == Set([
            VNextHistoryProjectionIdentity.productSizeID(
                comparisonID: firstHistoryID,
                productSizeID: sizeID
            ),
            VNextHistoryProjectionIdentity.productSizeID(
                comparisonID: secondHistoryID,
                productSizeID: sizeID
            )
        ]))
        #expect(saved[0].product !== saved[1].product)
    }

    @Test func exactHistoryAndDeletedReferenceLifecycleRemainIndependent() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let productID = UUID()
        let recommendedSizeID = UUID()
        let alternateSizeID = UUID()
        let referenceA = makeReference(name: "삭제된 기준 옷 A")
        let referenceB = makeReference(name: "활성 기준 옷 B")
        referenceB.isRepresentative = true
        context.insert(referenceA)
        context.insert(referenceB)
        try context.save()

        let recommended = makeSize(id: recommendedSizeID, name: "M", chest: 51)
        let alternate = makeSize(id: alternateSizeID, name: "L", chest: 54)
        let product = makeProduct(
            id: productID,
            sizes: [recommended, alternate]
        )
        let firstHistoryID = UUID()
        let first = makeCompletedHistory(
            id: firstHistoryID,
            product: product,
            size: recommended,
            reference: referenceA
        )
        try saveCompletedVNextUnderTest(first, existing: [], modelContext: context)

        let secondProduct = makeProduct(
            id: productID,
            sizes: [
                makeSize(id: recommendedSizeID, name: "M", chest: 51),
                makeSize(id: alternateSizeID, name: "L", chest: 54)
            ]
        )
        let secondHistoryID = UUID()
        let second = makeCompletedHistory(
            id: secondHistoryID,
            product: secondProduct,
            size: try #require(secondProduct.sizes.first),
            reference: referenceB
        )
        try saveCompletedVNextUnderTest(
            second,
            existing: try context.fetch(FetchDescriptor<RecommendationHistory>()),
            modelContext: context
        )

        referenceA.markAsHistoryOnlyReferenceSnapshot()
        try context.save()

        let histories = try context.fetch(FetchDescriptor<RecommendationHistory>())
        let activeCloset = try context.fetch(FetchDescriptor<UserFit>())
            .filter(\.isActiveClosetItem)
        #expect(Set(histories.map(\.id)) == Set([firstHistoryID, secondHistoryID]))
        #expect(histories.first { $0.id == firstHistoryID }?.userFit.id ==
            VNextHistoryProjectionIdentity.referenceID(
                comparisonID: firstHistoryID,
                clientItemID: referenceA.id
            ))
        #expect(histories.first { $0.id == secondHistoryID }?.userFit.id ==
            VNextHistoryProjectionIdentity.referenceID(
                comparisonID: secondHistoryID,
                clientItemID: referenceB.id
            ))
        #expect(histories.allSatisfy { $0.userFit.isHistoryOnlyReferenceSnapshot })
        #expect(activeCloset.map(\.id) == [referenceB.id])
        #expect(referenceA.fitMatchServerReferenceSnapshot() == nil)
        #expect(histories.allSatisfy {
            Set($0.product.sizes.map(\.id)) == Set([
                VNextHistoryProjectionIdentity.productSizeID(
                    comparisonID: $0.id,
                    productSizeID: recommendedSizeID
                ),
                VNextHistoryProjectionIdentity.productSizeID(
                    comparisonID: $0.id,
                    productSizeID: alternateSizeID
                )
            ])
        })
    }

    @Test func historyOnlySnapshotsAreExcludedFromActiveClosetAndPickerSurfaces() throws {
        let globalSearchPresentation = try sourceFile(
            "FitMatch/Services/FitMatchHistoryPresentation.swift"
        )
        let globalSearchFiltersActiveCloset = globalSearchPresentation
            .contains("cachedUserFits.filter(\\.isActiveClosetItem)")
        for relativePath in [
            "FitMatch/Views/MyClosetView.swift",
            "FitMatch/Views/HomeView.swift",
            "FitMatch/Views/GlobalSearchView.swift",
            "FitMatch/Views/ClosetItemDetailView.swift",
            "FitMatch/Views/AddComparedProductToClosetSheet.swift",
            "FitMatch/Views/CompareFlowSheet.swift",
            "FitMatch/Views/ShoppingProductFormView.swift",
            "FitMatch/Views/RecommendationResultView.swift"
        ] {
            let source = try sourceFile(relativePath)
            let usesGlobalSearchPresentation = relativePath
                == "FitMatch/Views/GlobalSearchView.swift"
                && source.contains("FitMatchGlobalSearchPresentation")
                && globalSearchFiltersActiveCloset
            #expect(
                source.contains("filter(\\.isActiveClosetItem)")
                    || source.contains("FitMatchClosetPresentation.activeItems")
                    || usesGlobalSearchPresentation
            )
        }
    }

    @Test func homeRecentHistoryKeepsDistinctCompletedComparisonsForTheSameProduct() {
        let product = makeProduct(
            id: UUID(),
            sizes: [makeSize(id: UUID(), name: "M", chest: 51)]
        )
        let reference = makeReference(name: "같은 기준 옷")
        let first = makeCompletedHistory(
            id: UUID(),
            product: product,
            size: product.sizes[0],
            reference: reference,
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let second = makeCompletedHistory(
            id: UUID(),
            product: product,
            size: product.sizes[0],
            reference: reference,
            createdAt: Date(timeIntervalSince1970: 20)
        )

        // HI-012: Home is a recent-comparison surface.  Equal URL/name must
        // not merge distinct immutable comparison IDs.
        let recents = FitMatchHistoryPresentation.recentHistories(
            from: [first, second]
        )
        #expect(recents.map(\.id) == [second.id, first.id])
    }

    @Test func historySearchFilterSortAndFavoriteUseTheSamePresentationPathAsTheHistoryScreen() {
        let favoriteURL = "https://www.musinsa.com/products/710002"
        let matchingProduct = makeProduct(
            id: UUID(),
            sizes: [makeSize(id: UUID(), name: "M", chest: 51)]
        )
        matchingProduct.name = "에어리즘 크루넥 티셔츠"
        matchingProduct.sourceName = "유니클로 공식몰"
        matchingProduct.sourceURLString = "https://www.uniqlo.com/kr/ko/products/E500900"

        let favoriteProduct = makeProduct(
            id: UUID(),
            sizes: [makeSize(id: UUID(), name: "L", chest: 54)]
        )
        favoriteProduct.name = "울 블렌드 니트"
        favoriteProduct.sourceName = "무신사"
        favoriteProduct.sourceURLString = favoriteURL
        favoriteProduct.category = .outer

        let reference = makeReference(name: "검색 기준 옷")
        let matching = makeCompletedHistory(
            id: UUID(),
            product: matchingProduct,
            size: matchingProduct.sizes[0],
            reference: reference,
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let favorite = makeCompletedHistory(
            id: UUID(),
            product: favoriteProduct,
            size: favoriteProduct.sizes[0],
            reference: reference,
            createdAt: Date(timeIntervalSince1970: 20)
        )
        favorite.recommendationScore = 80

        // HI-011: the actual History presentation action supplies search,
        // favorite scope, category filtering, and sort order.  It only reads
        // immutable completed History rows; it makes no authority decision.
        let searched = FitMatchHistoryPresentation.displayedHistories(
            from: [matching, favorite],
            searchText: "에어리즘",
            scope: .all,
            category: nil,
            favoriteURLs: [],
            sort: .latest
        )
        #expect(searched.map(\.id) == [matching.id])

        let favoritesOnly = FitMatchHistoryPresentation.displayedHistories(
            from: [matching, favorite],
            searchText: "",
            scope: .favorite,
            category: nil,
            favoriteURLs: [favoriteURL],
            sort: .latest
        )
        #expect(favoritesOnly.map(\.id) == [favorite.id])

        let categoryFiltered = FitMatchHistoryPresentation.displayedHistories(
            from: [matching, favorite],
            searchText: "",
            scope: .all,
            category: .outer,
            favoriteURLs: [],
            sort: .oldest
        )
        #expect(categoryFiltered.map(\.id) == [favorite.id])

        let oldestFirst = FitMatchHistoryPresentation.displayedHistories(
            from: [matching, favorite],
            searchText: "",
            scope: .all,
            category: nil,
            favoriteURLs: [],
            sort: .oldest
        )
        #expect(oldestFirst.map(\.id) == [matching.id, favorite.id])
    }

    private func saveCompletedVNextUnderTest(
        _ history: RecommendationHistory,
        existing: [RecommendationHistory],
        modelContext: ModelContext
    ) throws {
        try RecommendationHistoryStore.saveCompletedVNext(
            history,
            existing: existing,
            modelContext: modelContext
        )
    }

    private func inMemoryContainer() throws -> ModelContainer {
        let schema = Schema(FitMatchSchemaV1.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func makeSize(id: UUID, name: String, chest: Double) -> ProductSize {
        ProductSize(
            id: id,
            name: name,
            measurements: GarmentMeasurements(
                shoulder: 48,
                chest: chest,
                totalLength: 70,
                sleeveLength: 23
            )
        )
    }

    private func makeProduct(id: UUID, sizes: [ProductSize]) -> Product {
        let product = Product(
            id: id,
            name: "동일 서버 상품",
            category: .top,
            productCode: "E500900",
            sourceURLString: "https://www.uniqlo.com/kr/ko/products/E500900-000/01",
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            source: .catalog,
            sizes: sizes
        )
        product.garmentTypeRawValue = "tshirt"
        product.sleeveTypeRawValue = "short_sleeve"
        product.markClassificationAuthority(
            .serverConfirmed,
            sourceIdentity: "fitmatch_vnext_test"
        )
        return product
    }

    private func makeReference(name: String) -> UserFit {
        let item = UserFit(
            sourceType: .manual,
            sourceName: "직접 입력",
            brandName: "테스트",
            productName: name,
            category: .top,
            detailCategory: .shortSleeve,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 48,
                chest: 50,
                totalLength: 70,
                sleeveLength: 23
            ),
            fitMemo: "",
            satisfaction: 4,
            isRepresentative: true
        )
        item.garmentTypeRawValue = "tshirt"
        item.sleeveTypeRawValue = "short_sleeve"
        item.markClassificationAuthority(.userExplicit, sourceIdentity: "user_test")
        return item
    }

    private func makeCompletedHistory(
        id: UUID,
        product: Product,
        size: ProductSize,
        reference: UserFit,
        createdAt: Date = Date()
    ) -> RecommendationHistory {
        let comparedItem = MeasurementComparisonItem(
            kind: .chest,
            measurementCode: .chestWidthPitToPit,
            productValue: size.chest,
            referenceValue: reference.chest,
            signedDifference: size.chest - reference.chest,
            absoluteDifference: abs(size.chest - reference.chest),
            score: 95,
            weight: 1
        )
        let result = MeasurementComparisonResult(
            status: .confirmed,
            score: 95,
            comparedItems: [comparedItem],
            exclusions: [],
            averageDifference: comparedItem.absoluteDifference,
            minimumComparableCount: 1,
            requiredKinds: [.chest],
            minimumRequiredKindCount: 1,
            requiredAllKinds: [],
            expectedWeightSum: 1,
            usedWeightSum: 1
        )
        return RecommendationHistory(
            id: id,
            product: product,
            recommendedSize: size,
            userFit: reference,
            totalDifference: result.averageDifference,
            measurementDifferences: result.signedDifferences,
            recommendationScore: result.score,
            comparisonMethod: "서버 승인 직접 비교",
            productDetailCategory: .shortSleeve,
            comparisonResult: result,
            reason: "vNext completion test",
            createdAt: createdAt
        )
    }
}
