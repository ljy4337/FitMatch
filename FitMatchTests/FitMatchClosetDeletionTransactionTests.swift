import Foundation
import Testing
@testable import FitMatch

@MainActor
struct FitMatchClosetDeletionTransactionTests {
    private enum TestFailure: Error { case network, localSave, history }

    @Test func busySyncFinishesBeforeDeletionStarts() async throws {
        var busy = true
        var events: [String] = []
        try await FitMatchClosetDeletionTransaction.waitForSynchronization(
            isCurrent: { true }, isBusy: { busy },
            pause: { events.append("sync finished"); busy = false }
        )
        try await FitMatchClosetDeletionTransaction.run(
            isCurrent: { true }, prepare: { events.append("history") },
            resolve: { nil }, recordIntent: {},
            delete: { _ in throw TestFailure.network },
            commit: { events.append("local") }
        )
        #expect(events == ["sync finished", "history", "local"])
    }

    @Test func idleDeletionDoesNotWait() async throws {
        try await FitMatchClosetDeletionTransaction.waitForSynchronization(
            isCurrent: { true }, isBusy: { false },
            pause: { Issue.record("Idle deletion must start immediately") }
        )
    }

    @Test func accountChangeWhileWaitingStopsEvenWhenSyncFinishes() async {
        var current = true, busy = true
        await #expect(throws: FitMatchClosetDeletionTransaction.Failure.sessionChanged) {
            try await FitMatchClosetDeletionTransaction.waitForSynchronization(
                isCurrent: { current }, isBusy: { busy },
                pause: { current = false; busy = false }
            )
        }
    }

    @Test func stalledSyncHasBoundedWait() async {
        var waits = 0
        await #expect(throws: FitMatchClosetDeletionTransaction.Failure.synchronizationInProgress) {
            try await FitMatchClosetDeletionTransaction.waitForSynchronization(
                isCurrent: { true }, isBusy: { true }, maximumWaits: 3,
                pause: { waits += 1 }
            )
        }
        #expect(waits == 3)
    }

    @Test func cancelledWaitCannotContinueDeletion() async {
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            try await FitMatchClosetDeletionTransaction.waitForSynchronization(
                isCurrent: { true }, isBusy: { false },
                pause: { Issue.record("Cancelled request must not wait") }
            )
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func deletionOrderRequiresReceiptBeforeLocalCommit() async throws {
        let id = UUID()
        var events: [String] = []
        try await FitMatchClosetDeletionTransaction.run(
            isCurrent: { true }, prepare: { events.append("history") },
            resolve: { events.append("list"); return id },
            recordIntent: { events.append("journal") },
            delete: { requested in
                #expect(requested == id)
                events.append("server")
                return (id, "2026-09-16T00:00:00.123+00:00")
            }, commit: { events.append("local") }
        )
        #expect(events == ["history", "list", "journal", "server", "local"])
    }

    @Test func ambiguousNetworkFailureKeepsIntentAndLocalItemThenRetryConfirmsAbsence() async throws {
        var intent = false, committed = false
        await #expect(throws: TestFailure.self) {
            try await FitMatchClosetDeletionTransaction.run(
                isCurrent: { true }, prepare: {}, resolve: { UUID() },
                recordIntent: { intent = true }, delete: { _ in throw TestFailure.network },
                commit: { committed = true }
            )
        }
        #expect(intent && !committed)
        try await FitMatchClosetDeletionTransaction.run(
            isCurrent: { true }, prepare: {}, resolve: { nil }, recordIntent: {},
            delete: { _ in Issue.record("Already absent must not delete again"); throw TestFailure.network },
            commit: { committed = true }
        )
        #expect(committed)
    }

    @Test func historyFailureCannotStartDeletion() async {
        var touched = false
        await #expect(throws: TestFailure.self) {
            try await FitMatchClosetDeletionTransaction.run(
                isCurrent: { true }, prepare: { throw TestFailure.history },
                resolve: { touched = true; return nil }, recordIntent: { touched = true },
                delete: { _ in throw TestFailure.network }, commit: { touched = true }
            )
        }
        #expect(!touched)
    }

    @Test func failedListCannotBeMistakenForAlreadyDeleted() async {
        var touched = false
        await #expect(throws: TestFailure.self) {
            try await FitMatchClosetDeletionTransaction.run(
                isCurrent: { true }, prepare: {}, resolve: { throw TestFailure.network },
                recordIntent: { touched = true }, delete: { _ in throw TestFailure.network },
                commit: { touched = true }
            )
        }
        #expect(!touched)
    }

    @Test(arguments: [true, false]) func wrongReceiptNeverCommits(wrongID: Bool) async {
        let id = UUID()
        var committed = false
        await #expect(throws: FitMatchClosetDeletionTransaction.Failure.invalidReceipt) {
            try await FitMatchClosetDeletionTransaction.run(
                isCurrent: { true }, prepare: {}, resolve: { id }, recordIntent: {},
                delete: { _ in (wrongID ? UUID() : id, wrongID ? "2026-09-16T00:00:00Z" : "") },
                commit: { committed = true }
            )
        }
        #expect(!committed)
    }

    @Test(arguments: ["history", "list", "server"]) func accountChangeCannotCommit(stage: String) async {
        var current = true, committed = false
        let id = UUID()
        await #expect(throws: FitMatchClosetDeletionTransaction.Failure.sessionChanged) {
            try await FitMatchClosetDeletionTransaction.run(
                isCurrent: { current }, prepare: { if stage == "history" { current = false } },
                resolve: { if stage == "list" { current = false }; return id }, recordIntent: {},
                delete: { _ in current = false; return (id, "2026-09-16T00:00:00Z") },
                commit: { committed = true }
            )
        }
        #expect(!committed)
    }

    @Test func localSaveFailureRemainsFailureAfterServerSuccess() async {
        var serverDone = false
        let id = UUID()
        await #expect(throws: TestFailure.self) {
            try await FitMatchClosetDeletionTransaction.run(
                isCurrent: { true }, prepare: {}, resolve: { id }, recordIntent: {},
                delete: { _ in serverDone = true; return (id, "2026-09-16T00:00:00Z") },
                commit: { throw TestFailure.localSave }
            )
        }
        #expect(serverDone)
    }
}
