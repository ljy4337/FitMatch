import Foundation
@testable import FitMatch

/// Pure ownership checks shared by the live cleanup entry point and offline
/// tests. No method in this type can authenticate, request data, or mutate rows.
@MainActor
enum ReleaseAuthLedgerSafety {
    typealias Ledger = ReleaseAuthenticatedRun.Ledger
    typealias Item = ReleaseAuthenticatedRun.Item
    typealias Comparison = ReleaseAuthenticatedRun.Comparison

    struct ItemProof {
        let clientID: UUID
        let serverID: UUID
        let marker: String
        let productID: UUID?
        let variantID: UUID?
        init(clientID: UUID, serverID: UUID, marker: String, productID: UUID?, variantID: UUID?) {
            self.clientID = clientID; self.serverID = serverID; self.marker = marker
            self.productID = productID; self.variantID = variantID
        }
        init(row: FitMatchClosetItemRecord) {
            self.init(clientID: row.clientItemID, serverID: row.closetItemID, marker: row.fitMemo,
                      productID: row.productID, variantID: row.variantID)
        }
    }
    struct ComparisonProof {
        let clientID: UUID
        let serverID: UUID
        let referenceClientID: UUID?
        let targetID: UUID
        let variantID: UUID
        init(clientID: UUID, serverID: UUID, referenceClientID: UUID?, targetID: UUID, variantID: UUID) {
            self.clientID = clientID; self.serverID = serverID; self.referenceClientID = referenceClientID
            self.targetID = targetID; self.variantID = variantID
        }
        init(row: VNextComparisonHistoryDTO) {
            self.init(clientID: row.clientComparisonID, serverID: row.id,
                referenceClientID: row.referenceClientItemID, targetID: row.targetProductID,
                variantID: row.targetVariantID)
        }
    }
    private static func require(_ value: Bool, _ reason: String) throws {
        guard value else { throw ReleaseAuthFailure.blocked(reason) }
    }
    static func decode(_ data: Data, runID: UUID, ownerID: UUID, observerID: UUID) throws -> Ledger {
        guard let ledger = try? JSONDecoder().decode(Ledger.self, from: data) else {
            throw ReleaseAuthFailure.blocked("malformed_cleanup_ledger")
        }
        try require(ledger.version == 1 && ledger.project == ReleaseAuthConfiguration.project,
                    "cleanup_ledger_project_or_version_mismatch")
        try require(ledger.runID == runID && ledger.ownerID == ownerID && ledger.observerID == observerID
                    && ownerID != observerID, "cleanup_ledger_run_or_account_pair_mismatch")
        try require(!ledger.items.isEmpty || !ledger.comparisons.isEmpty, "cleanup_ledger_has_no_owned_entries")
        let clients = ledger.items.map(\.clientID)
        let servers = ledger.items.compactMap(\.serverID)
        let comparisonClients = ledger.comparisons.map(\.clientID)
        let comparisonServers = ledger.comparisons.compactMap(\.serverID)
        try require(Set(clients).count == clients.count && Set(servers).count == servers.count
                    && Set(comparisonClients).count == comparisonClients.count
                    && Set(comparisonServers).count == comparisonServers.count,
                    "cleanup_ledger_duplicate_identity")
        for item in ledger.items {
            let marker = "fitmatch-release-qa:" + runID.uuidString.lowercased() + ":" + item.clientID.uuidString.lowercased()
            try require(item.marker == marker && item.attempted
                        && ((item.productID == nil) == (item.variantID == nil))
                        && (!item.deleted || item.serverID != nil), "cleanup_ledger_item_identity_invalid")
        }
        for comparison in ledger.comparisons {
            try require(clients.contains(comparison.referenceClientID)
                        && (!comparison.completed || comparison.serverID != nil)
                        && (!comparison.hidden || comparison.completed), "cleanup_ledger_comparison_identity_invalid")
        }
        return ledger
    }

    /// Returns the exact server ID to reconcile; nil is accepted only for an
    /// already-recorded deletion with a known server ID and no active proof.
    static func validateItem(_ item: Item, proofs: [ItemProof]) throws -> UUID? {
        if item.deleted {
            try require(item.serverID != nil && proofs.isEmpty, "cleanup_deleted_item_conflict")
            return nil
        }
        try require(proofs.count == 1, "cleanup_item_missing_or_ambiguous")
        let proof = proofs[0]
        try require(proof.clientID == item.clientID && proof.marker == item.marker
                    && proof.productID == item.productID && proof.variantID == item.variantID
                    && (item.serverID == nil || item.serverID == proof.serverID),
                    "cleanup_item_ownership_mismatch")
        return proof.serverID
    }

    /// true means an authoritative tombstone already establishes hidden state.
    /// A visible history is mutable only when its exact reference still has a
    /// verified run marker. Missing deleted reference evidence is not inferred.
    static func validateComparison(_ entry: Comparison, proofs: [ComparisonProof],
                                   tombstoneCount: Int, verifiedActiveReference: Bool) throws -> Bool {
        try require(entry.completed && entry.serverID != nil, "cleanup_pending_comparison_unresolved")
        try require(proofs.count <= 1 && tombstoneCount <= 1 && !(proofs.count == 1 && tombstoneCount == 1),
                    "cleanup_comparison_ambiguous")
        if tombstoneCount == 1 { return true }
        try require(proofs.count == 1 && !entry.hidden && verifiedActiveReference,
                    "cleanup_comparison_missing_or_unverified_reference")
        let proof = proofs[0]
        try require(proof.clientID == entry.clientID && proof.serverID == entry.serverID
                    && proof.referenceClientID == entry.referenceClientID
                    && proof.targetID == entry.targetID && proof.variantID == entry.variantID,
                    "cleanup_comparison_ownership_mismatch")
        return false
    }
}

/// Test-harness sequencing only. The injected boundaries are normal-user reads,
/// exact hide RPC, and durable local ledger write; offline tests replace only IO.
@MainActor
enum ReleaseAuthComparisonRetirement {
    struct Evidence {
        var listedItems: [ReleaseAuthLedgerSafety.ItemProof]
        var exactItems: [ReleaseAuthLedgerSafety.ItemProof]
        var histories: [ReleaseAuthLedgerSafety.ComparisonProof]
        var tombstones: [UUID]
    }

    static func beforeNextComparison(
        ledger: ReleaseAuthenticatedRun.Ledger, targetID: UUID,
        read: (ReleaseAuthenticatedRun.Comparison) async throws -> Evidence,
        hide: (UUID) async throws -> [UUID],
        persist: (ReleaseAuthenticatedRun.Ledger) throws -> Void
    ) async throws -> ReleaseAuthenticatedRun.Ledger {
        let indices = ledger.comparisons.indices.filter { ledger.comparisons[$0].targetID == targetID }
        guard !indices.isEmpty else { return ledger }
        _ = try ReleaseAuthLedgerSafety.decode(JSONEncoder().encode(ledger), runID: ledger.runID,
            ownerID: ledger.ownerID, observerID: ledger.observerID)
        var reconciled = ledger
        var requiresHide: [Int] = []
        // Validate all prior entries before mutating any. A missing superseded
        // row is still BLOCKED; this action cannot repair historical gaps.
        for index in indices {
            let entry = ledger.comparisons[index]
            let evidence = try await read(entry)
            let active = evidence.histories.filter { $0.clientID == entry.clientID }
            let tombstones = evidence.tombstones.filter { $0 == entry.clientID }.count
            var verifiedReference = false
            if tombstones == 0 {
                guard let item = ledger.items.first(where: { $0.clientID == entry.referenceClientID }),
                      !item.deleted, let serverID = item.serverID else {
                    throw ReleaseAuthFailure.blocked("retirement_reference_missing")
                }
                let listed = try ReleaseAuthLedgerSafety.validateItem(item,
                    proofs: evidence.listedItems.filter { $0.clientID == item.clientID })
                let exact = try ReleaseAuthLedgerSafety.validateItem(item, proofs: evidence.exactItems)
                verifiedReference = listed == serverID && exact == serverID
            }
            let hidden = try ReleaseAuthLedgerSafety.validateComparison(entry, proofs: active,
                tombstoneCount: tombstones, verifiedActiveReference: verifiedReference)
            reconciled.comparisons[index].hidden = hidden
            if !hidden { requiresHide.append(index) }
        }
        for index in requiresHide {
            let entry = ledger.comparisons[index]
            let receiptIDs = try await hide(entry.clientID)
            guard receiptIDs == [entry.clientID] else {
                throw ReleaseAuthFailure.blocked("retirement_hide_receipt_mismatch")
            }
            let fresh = try await read(entry)
            let hidden = try ReleaseAuthLedgerSafety.validateComparison(entry,
                proofs: fresh.histories.filter { $0.clientID == entry.clientID },
                tombstoneCount: fresh.tombstones.filter { $0 == entry.clientID }.count,
                verifiedActiveReference: false)
            guard hidden else { throw ReleaseAuthFailure.blocked("retirement_tombstone_missing") }
            reconciled.comparisons[index].hidden = true
            try persist(reconciled)
        }
        // Also persist authoritative reconciliation after a previous hide
        // committed but its response or local journal write was lost.
        if requiresHide.isEmpty { try persist(reconciled) }
        return reconciled
    }
}
