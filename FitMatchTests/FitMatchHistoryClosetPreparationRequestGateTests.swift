import Foundation
import Testing
@testable import FitMatch

@MainActor
struct FitMatchHistoryClosetPreparationRequestGateTests {
    @Test func anotherHistoryCannotStartWhileRegistrationIsPreparing() throws {
        let gate = FitMatchHistoryClosetPreparationRequestGate()
        let first = try #require(gate.begin(historyID: UUID()))
        #expect(gate.begin(historyID: UUID()) == nil)
        #expect(gate.finish(requestID: first))
        #expect(gate.begin(historyID: UUID()) != nil)
    }

    @Test func invalidatedCompletionCannotPresentOrUnlockNewRequestForSameHistory() throws {
        let gate = FitMatchHistoryClosetPreparationRequestGate()
        let historyID = UUID()
        let old = try #require(gate.begin(historyID: historyID))
        gate.invalidate()
        let current = try #require(gate.begin(historyID: historyID))
        #expect(!gate.finish(requestID: old))
        #expect(gate.begin(historyID: UUID()) == nil)
        #expect(gate.finish(requestID: current))
    }

    @Test func dismissedOrSignedOutRequestCannotPresent() throws {
        let gate = FitMatchHistoryClosetPreparationRequestGate()
        let request = try #require(gate.begin(historyID: UUID()))
        gate.invalidate()
        #expect(!gate.finish(requestID: request))
    }
}
