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

        #expect(history.product.id == serverProductID)
        #expect(history.recommendedSize.id == serverRecommendedSizeID)
        #expect(Set(history.product.sizes.map(\.id)).intersection(authorizedSizeIDs) == authorizedSizeIDs)
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

        let storedProduct = try #require(
            try context.fetch(FetchDescriptor<Product>()).first { $0.id == productID }
        )
        let storedSize = try #require(storedProduct.sizes.first { $0.id == sizeID })
        let second = makeCompletedHistory(
            id: secondHistoryID,
            product: storedProduct,
            size: storedSize,
            reference: secondReference
        )
        let existing = try context.fetch(FetchDescriptor<RecommendationHistory>())
        try saveCompletedVNextUnderTest(second, existing: existing, modelContext: context)

        let duplicateIDReplay = makeCompletedHistory(
            id: secondHistoryID,
            product: storedProduct,
            size: storedSize,
            reference: firstReference
        )
        try saveCompletedVNextUnderTest(
            duplicateIDReplay,
            existing: try context.fetch(FetchDescriptor<RecommendationHistory>()),
            modelContext: context
        )

        let saved = try context.fetch(FetchDescriptor<RecommendationHistory>())
        #expect(Set(saved.map(\.id)) == Set([firstHistoryID, secondHistoryID]))
        #expect(Set(saved.map { $0.userFit.id }) == Set([firstReference.id, secondReference.id]))
        #expect(saved.allSatisfy { $0.product.id == productID })
        #expect(saved.allSatisfy { $0.recommendedSize.id == sizeID })
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

        let storedProduct = try #require(
            try context.fetch(FetchDescriptor<Product>()).first { $0.id == productID }
        )
        let storedSize = try #require(
            storedProduct.sizes.first { $0.id == recommendedSizeID }
        )
        let secondHistoryID = UUID()
        let second = makeCompletedHistory(
            id: secondHistoryID,
            product: storedProduct,
            size: storedSize,
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
        #expect(histories.first { $0.id == firstHistoryID }?.userFit.id == referenceA.id)
        #expect(histories.first { $0.id == secondHistoryID }?.userFit.id == referenceB.id)
        #expect(activeCloset.map(\.id) == [referenceB.id])
        #expect(referenceA.fitMatchServerReferenceSnapshot() == nil)
        #expect(Set(storedProduct.sizes.map(\.id)) == Set([
            recommendedSizeID,
            alternateSizeID
        ]))
    }

    @Test func historyOnlySnapshotsAreExcludedFromActiveClosetAndPickerSurfaces() throws {
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
            #expect(source.contains("filter(\\.isActiveClosetItem)"))
        }
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
        reference: UserFit
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
            reason: "vNext completion test"
        )
    }
}
