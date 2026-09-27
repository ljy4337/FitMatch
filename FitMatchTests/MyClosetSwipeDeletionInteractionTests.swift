import Foundation
import Testing
import SwiftData
@testable import FitMatch

struct MyClosetSwipeDeletionInteractionTests {
    @Test func shortSwipeRequiresConfirmationWhileFullSwipeDeletesImmediately() throws {
        let source = try myClosetViewSource()

        #expect(source.contains("MyClosetSwipeDeleteRow"))
        #expect(source.contains("onDeleteButtonTap: { pendingDeleteItem = item }"))
        #expect(source.contains("onFullSwipeDelete: { deleteItem(item) }"))
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
        try source(named: "MyClosetView.swift")
    }

    private func closetItemDetailViewSource() throws -> String {
        try source(named: "ClosetItemDetailView.swift")
    }

    private func source(named fileName: String) throws -> String {
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
