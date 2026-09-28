import Foundation
import Testing
import SwiftData
@testable import FitMatch

struct MyClosetSwipeDeletionInteractionTests {
    @Test func closetAndHistorySwipesUseNativeActionsAndConfirmDeletion() throws {
        let source = try myClosetViewSource()
        let history = try sourceFile(named: "RecommendationHistoryView.swift")

        #expect(!source.contains("MyClosetSwipeDeleteRow"))
        #expect(source.contains(".swipeActions(edge: .trailing, allowsFullSwipe: true)"))
        #expect(source.contains("pendingDeleteItem = item"))
        #expect(source.contains("guard let item = pendingDeleteItem else { return }"))
        #expect(history.contains(".swipeActions(edge: .trailing, allowsFullSwipe: true)"))
        #expect(history.contains("pendingDeleteHistory = history"))
        #expect(history.contains("guard let history = pendingDeleteHistory else { return }"))
    }

    @Test @MainActor func editDeletionCannotRemoveGarmentWithoutServerAuthority() async throws {
        // Detail editing now exposes deletion. Its safety contract is the same
        // server-first action as swipe deletion, not absence of a UI symbol.
        let schema = Schema([UserFit.self, Product.self, ProductSize.self,
            Brand.self, RecommendationHistory.self])
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let item = UserFit(sourceType: .manual, sourceName: "직접 입력",
            brandName: "검증", gender: .men, productName: "삭제 검증",
            category: .top, detailCategory: .shortSleeve, sizeName: "M",
            measurements: GarmentMeasurements(shoulder: 45, chest: 50, totalLength: 70, sleeveLength: 20),
            fitMemo: "", satisfaction: 4, isRepresentative: false)
        context.insert(item)
        try context.save()
        let id = item.id
        let result = await FitMatchClosetDeletionAction.delete(item: item,
            histories: [], in: context, comparisonSync: nil, closetSync: nil)
        #expect(result == .serverClosetUnavailable)
        #expect(try context.fetch(FetchDescriptor<UserFit>()).map(\.id) == [id])
    }

    private func myClosetViewSource() throws -> String {
        try sourceFile(named: "MyClosetView.swift")
    }

    private func closetItemDetailViewSource() throws -> String {
        try sourceFile(named: "ClosetItemDetailView.swift")
    }

    private func sourceFile(named fileName: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("FitMatch/Views")
                .appendingPathComponent(fileName),
            encoding: .utf8
        )
    }
}
