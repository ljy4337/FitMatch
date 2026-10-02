import Foundation
import Testing
@testable import FitMatch

@MainActor
struct FitMatchReleaseAuthenticatedLedgerSafetyTests {
    private func fixture() -> ReleaseAuthenticatedRun.Ledger {
        let run = UUID(), client = UUID()
        var ledger = ReleaseAuthenticatedRun.Ledger(runID: run, ownerID: UUID(), observerID: UUID())
        ledger.items = [.init(clientID: client, serverID: UUID(),
            marker: "fitmatch-release-qa:" + run.uuidString.lowercased() + ":" + client.uuidString.lowercased(),
            productID: nil, variantID: nil, attempted: true)]
        ledger.comparisons = [.init(clientID: UUID(), referenceClientID: client,
            targetID: UUID(), variantID: UUID(), serverID: UUID(), completed: true)]
        return ledger
    }
    private func decode(_ data: Data, expected: ReleaseAuthenticatedRun.Ledger) throws -> ReleaseAuthenticatedRun.Ledger {
        try ReleaseAuthLedgerSafety.decode(data, runID: expected.runID,
            ownerID: expected.ownerID, observerID: expected.observerID)
    }
    private func blocked(_ body: () throws -> Void) {
        do { try body(); Issue.record("Unsafe cleanup evidence was accepted") }
        catch let error as ReleaseAuthFailure { #expect(error.status == "BLOCKED") }
        catch { Issue.record("Cleanup guard did not return a sanitized BLOCKED failure") }
    }
    private func proof(_ item: ReleaseAuthenticatedRun.Item) -> ReleaseAuthLedgerSafety.ItemProof {
        .init(clientID: item.clientID, serverID: item.serverID!, marker: item.marker,
              productID: item.productID, variantID: item.variantID)
    }
    private func proof(_ item: ReleaseAuthenticatedRun.Comparison) -> ReleaseAuthLedgerSafety.ComparisonProof {
        .init(clientID: item.clientID, serverID: item.serverID!, referenceClientID: item.referenceClientID,
              targetID: item.targetID, variantID: item.variantID)
    }

    @Test func exactDevelopmentLedgerRoundTripsWithoutInventingScope() throws {
        let expected = fixture()
        let actual = try decode(JSONEncoder().encode(expected), expected: expected)
        #expect(actual.project == ReleaseAuthConfiguration.project)
        #expect(actual.runID == expected.runID)
        #expect(actual.items.map(\.clientID) == expected.items.map(\.clientID))
        #expect(actual.comparisons.map(\.clientID) == expected.comparisons.map(\.clientID))
    }

    @Test func foreignProjectVersionOwnersRunAndMalformedUUIDAreBlockedBeforeNetwork() throws {
        let expected = fixture()
        let encoded = try JSONEncoder().encode(expected)
        let object = try JSONSerialization.jsonObject(with: encoded)
        let base = try #require(object as? [String: Any])
        for (key, value) in [("project", "aqhrupgjpmrtnystottx" as Any), ("version", 2 as Any),
                             ("runID", UUID().uuidString as Any), ("runID", "not-a-uuid" as Any),
                             ("ownerID", UUID().uuidString as Any), ("observerID", expected.ownerID.uuidString as Any)] {
            var changed = base; changed[key] = value
            let data = try JSONSerialization.data(withJSONObject: changed)
            blocked { _ = try decode(data, expected: expected) }
        }
    }

    @Test func duplicateIDsMarkerTamperingAndBrokenIdentityTuplesAreBlocked() throws {
        let expected = fixture()
        var duplicate = expected; duplicate.items.append(expected.items[0])
        var duplicateComparison = expected; duplicateComparison.comparisons.append(expected.comparisons[0])
        var wrongMarker = expected
        let original = expected.items[0]
        wrongMarker.items[0] = .init(clientID: original.clientID, serverID: original.serverID,
            marker: "unrelated", productID: nil, variantID: nil, attempted: true)
        var brokenTuple = expected
        brokenTuple.items[0] = .init(clientID: original.clientID, serverID: original.serverID,
            marker: original.marker, productID: UUID(), variantID: nil, attempted: true)
        var unknownReference = expected
        let comparison = expected.comparisons[0]
        unknownReference.comparisons[0] = .init(clientID: comparison.clientID, referenceClientID: UUID(),
            targetID: comparison.targetID, variantID: comparison.variantID, serverID: comparison.serverID, completed: true)
        for changed in [duplicate, duplicateComparison, wrongMarker, brokenTuple, unknownReference] {
            let data = try JSONEncoder().encode(changed)
            blocked { _ = try decode(data, expected: expected) }
        }
    }

    @Test func itemDeletionRequiresOneExactLiveOwnershipProof() throws {
        let item = fixture().items[0], valid = proof(fixture().items[0])
        let exact = proof(item)
        let accepted = try ReleaseAuthLedgerSafety.validateItem(item, proofs: [exact])
        #expect(accepted == item.serverID)
        for values in [[], [exact, exact], [valid],
            [.init(clientID: item.clientID, serverID: item.serverID!, marker: "other-run", productID: nil, variantID: nil)],
            [.init(clientID: item.clientID, serverID: UUID(), marker: item.marker, productID: nil, variantID: nil)]] {
            blocked { _ = try ReleaseAuthLedgerSafety.validateItem(item, proofs: values) }
        }
        var ambiguous = item; ambiguous.serverID = nil
        blocked { _ = try ReleaseAuthLedgerSafety.validateItem(ambiguous, proofs: []) }
        let recovered = try ReleaseAuthLedgerSafety.validateItem(ambiguous, proofs: [exact])
        #expect(recovered == item.serverID)
    }

    @Test func recordedDeletionNeverPermitsAnUnexpectedActiveRow() throws {
        var item = fixture().items[0]
        let exact = proof(item)
        item.deleted = true
        let accepted = try ReleaseAuthLedgerSafety.validateItem(item, proofs: [])
        #expect(accepted == nil)
        blocked { _ = try ReleaseAuthLedgerSafety.validateItem(item, proofs: [exact]) }
        item.serverID = nil
        blocked { _ = try ReleaseAuthLedgerSafety.validateItem(item, proofs: []) }
    }

    @Test func comparisonCleanupRequiresExactHistoryOrUnambiguousTombstone() throws {
        let entry = fixture().comparisons[0], exact = proof(fixture().comparisons[0])
        let valid = proof(entry)
        let active = try ReleaseAuthLedgerSafety.validateComparison(entry, proofs: [valid],
            tombstoneCount: 0, verifiedActiveReference: true)
        #expect(!active)
        let hidden = try ReleaseAuthLedgerSafety.validateComparison(entry, proofs: [],
            tombstoneCount: 1, verifiedActiveReference: false)
        #expect(hidden)
        for (proofs, tombstones, reference) in [([valid], 0, false), ([], 0, true),
            ([exact], 0, true), ([valid, valid], 0, true), ([valid], 1, true), ([], 2, true)] {
            blocked { _ = try ReleaseAuthLedgerSafety.validateComparison(entry, proofs: proofs,
                tombstoneCount: tombstones, verifiedActiveReference: reference) }
        }
        var pending = entry; pending.completed = false
        blocked { _ = try ReleaseAuthLedgerSafety.validateComparison(pending, proofs: [valid],
            tombstoneCount: 0, verifiedActiveReference: true) }
    }

    @Test func supersededCompletedComparisonWithoutTombstoneBlocksRestoredCleanup() throws {
        var ledger = fixture()
        let older = ledger.comparisons[0]
        let current = ReleaseAuthenticatedRun.Comparison(clientID: UUID(),
            referenceClientID: older.referenceClientID, targetID: older.targetID,
            variantID: older.variantID, serverID: UUID(), completed: true)
        ledger.comparisons.append(current)
        let restored = try decode(JSONEncoder().encode(ledger), expected: ledger)

        // Model the SQL projection after another completion for the same
        // target: only the current head is listed; neither row was soft-hidden.
        let activeProofs = [proof(current)]
        let currentHidden = try ReleaseAuthLedgerSafety.validateComparison(current,
            proofs: activeProofs, tombstoneCount: 0, verifiedActiveReference: true)
        #expect(!currentHidden)
        let missingOlderProof = activeProofs.filter { $0.clientID == older.clientID }
        var inferredHidden: Bool?
        do {
            inferredHidden = try ReleaseAuthLedgerSafety.validateComparison(older,
                proofs: missingOlderProof, tombstoneCount: 0, verifiedActiveReference: true)
            Issue.record("Superseded completion without ownership evidence was accepted")
        } catch let error as ReleaseAuthFailure {
            #expect(error.status == "BLOCKED")
            #expect(error.code == "cleanup_comparison_missing_or_unverified_reference")
        } catch {
            Issue.record("Missing superseded comparison proof did not return the expected BLOCKED failure")
        }
        #expect(inferredHidden == nil)
        #expect(restored.comparisons.allSatisfy { !$0.hidden })
    }

    @Test func retireExactPriorTargetBeforeSupersessionLeavesRestorableTombstone() async throws {
        var ledger = fixture()
        let prior = ledger.comparisons[0], item = ledger.items[0]
        let unrelated = ReleaseAuthenticatedRun.Comparison(clientID: UUID(), referenceClientID: item.clientID,
            targetID: UUID(), variantID: UUID(), serverID: UUID(), completed: true)
        ledger.comparisons.append(unrelated)
        var evidence = ReleaseAuthComparisonRetirement.Evidence(listedItems: [proof(item)],
            exactItems: [proof(item)], histories: [proof(prior), proof(unrelated)], tombstones: [])
        var hiddenIDs: [UUID] = [], persisted: ReleaseAuthenticatedRun.Ledger?
        let result = try await ReleaseAuthComparisonRetirement.beforeNextComparison(
            ledger: ledger, targetID: prior.targetID,
            read: { _ in evidence },
            hide: { id in
                hiddenIDs.append(id)
                evidence.histories.removeAll { $0.clientID == id }
                evidence.tombstones.append(id)
                return [id]
            }, persist: { persisted = $0 })
        #expect(hiddenIDs == [prior.clientID])
        #expect(result.comparisons[0].hidden)
        #expect(!result.comparisons[1].hidden)
        let saved = try #require(persisted)
        let restored = try decode(JSONEncoder().encode(saved), expected: ledger)
        let hidden = try ReleaseAuthLedgerSafety.validateComparison(restored.comparisons[0], proofs: [],
            tombstoneCount: evidence.tombstones.filter { $0 == prior.clientID }.count,
            verifiedActiveReference: false)
        #expect(hidden)
        #expect(evidence.histories.map(\.clientID) == [unrelated.clientID])
    }

    @Test(arguments: ["missing_history", "wrong_reference", "wrong_exact_item", "missing_tombstone", "wrong_receipt", "lost_hide_response"])
    func retirementFailurePreventsNextComparisonAndDoesNotInventHiddenState(failure: String) async throws {
        let ledger = fixture(), prior = ledger.comparisons[0], item = ledger.items[0]
        var evidence = ReleaseAuthComparisonRetirement.Evidence(listedItems: [proof(item)],
            exactItems: [proof(item)], histories: [proof(prior)], tombstones: [])
        if failure == "missing_history" { evidence.histories = [] }
        if failure == "wrong_reference" {
            evidence.histories = [.init(clientID: prior.clientID, serverID: prior.serverID!,
                referenceClientID: UUID(), targetID: prior.targetID, variantID: prior.variantID)]
        }
        if failure == "wrong_exact_item" { evidence.exactItems = [] }
        var hideCalls = 0, saveCalls = 0, nextComparisonStarted = false
        do {
            _ = try await ReleaseAuthComparisonRetirement.beforeNextComparison(
                ledger: ledger, targetID: prior.targetID, read: { _ in evidence },
                hide: { id in
                    hideCalls += 1
                    if failure == "lost_hide_response" {
                        evidence.histories = []; evidence.tombstones = [id]
                        throw ReleaseAuthFailure.blocked("simulated_lost_hide_response")
                    }
                    return failure == "wrong_receipt" ? [UUID()] : [id]
                }, persist: { _ in saveCalls += 1 })
            nextComparisonStarted = true
            Issue.record("Unsafe retirement allowed the next comparison")
        } catch let error as ReleaseAuthFailure {
            #expect(error.status == "BLOCKED")
        }
        #expect(!nextComparisonStarted)
        #expect(saveCalls == 0)
        #expect(!ledger.comparisons[0].hidden)
        #expect(hideCalls == (["missing_history", "wrong_reference", "wrong_exact_item"].contains(failure) ? 0 : 1))
    }

    @Test func retirementRecoversLostLocalJournalOnlyFromExistingTombstone() async throws {
        let ledger = fixture(), prior = ledger.comparisons[0]
        var hideCalls = 0, saved: ReleaseAuthenticatedRun.Ledger?
        let result = try await ReleaseAuthComparisonRetirement.beforeNextComparison(
            ledger: ledger, targetID: prior.targetID,
            read: { _ in .init(listedItems: [], exactItems: [], histories: [], tombstones: [prior.clientID]) },
            hide: { _ in hideCalls += 1; return [] }, persist: { saved = $0 })
        #expect(hideCalls == 0)
        #expect(result.comparisons[0].hidden)
        #expect(saved?.comparisons[0].hidden == true)
    }

    @Test func retirementChecksEveryPriorSameProductVariantBeforeAnyHide() async throws {
        var ledger = fixture()
        let prior = ledger.comparisons[0], item = ledger.items[0]
        // Same target with another variant is also superseded by product heads.
        ledger.comparisons.append(.init(clientID: UUID(), referenceClientID: item.clientID,
            targetID: prior.targetID, variantID: UUID(), serverID: UUID(), completed: true))
        var hideCalls = 0, saveCalls = 0
        do {
            _ = try await ReleaseAuthComparisonRetirement.beforeNextComparison(
                ledger: ledger, targetID: prior.targetID,
                read: { _ in .init(listedItems: [proof(item)], exactItems: [proof(item)],
                                   histories: [proof(prior)], tombstones: []) },
                hide: { id in hideCalls += 1; return [id] }, persist: { _ in saveCalls += 1 })
            Issue.record("Missing prior variant proof allowed a partial retirement")
        } catch let error as ReleaseAuthFailure {
            #expect(error.status == "BLOCKED")
            #expect(error.code == "cleanup_comparison_missing_or_unverified_reference")
        }
        #expect(hideCalls == 0)
        #expect(saveCalls == 0)
    }
}
