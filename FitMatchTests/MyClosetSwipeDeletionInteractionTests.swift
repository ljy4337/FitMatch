import Foundation
import Testing
@testable import FitMatch

struct MyClosetSwipeDeletionInteractionTests {
    @Test func shortSwipeRequiresConfirmationWhileFullSwipeDeletesImmediately() throws {
        let source = try myClosetViewSource()

        #expect(source.contains("MyClosetSwipeDeleteRow"))
        #expect(source.contains("onDeleteButtonTap: { pendingDeleteItem = item }"))
        #expect(source.contains("onFullSwipeDelete: { deleteItem(item) }"))
    }

    @Test func closetEditDoesNotExposeDeletionAction() throws {
        let source = try closetItemDetailViewSource()

        #expect(!source.contains("onDelete: {"))
        #expect(!source.contains("deleteItemAndDismiss"))
        #expect(!source.contains("deleteSection"))
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
