import Combine
import Foundation
import SwiftData
import SwiftUI

nonisolated protocol FitMatchClosetRemoteServicing: FitMatchServerAuthorityRemoteServicing {
    func upsertClosetItem(_ request: FitMatchUpsertClosetItemRequest) async throws
        -> FitMatchUpsertClosetItemResponse
    func deleteClosetItem(closetItemID: UUID) async throws
        -> FitMatchDeleteClosetItemResponse
    func updateClosetItem(
        _ request: FitMatchUpsertClosetItemRequest,
        closetItemID: UUID
    ) async throws -> FitMatchUpsertClosetItemResponse
    func setClosetReference(closetItemID: UUID, isReference: Bool) async throws
        -> FitMatchSetClosetReferenceResponse
    func setClosetClassificationOverride(
        closetItemID: UUID,
        override: FitMatchClosetClassificationOverride
    ) async throws
    func clearClosetClassificationOverride(closetItemID: UUID) async throws
}

extension FitMatchClosetRemoteServicing {
    func updateClosetItem(
        _ request: FitMatchUpsertClosetItemRequest,
        closetItemID: UUID
    ) async throws -> FitMatchUpsertClosetItemResponse {
        throw FitMatchSupabaseProductResolverError.vnextIdentityRequired
    }

    func setClosetReference(
        closetItemID: UUID,
        isReference: Bool
    ) async throws -> FitMatchSetClosetReferenceResponse {
        throw FitMatchSupabaseProductResolverError.vnextIdentityRequired
    }

    func setClosetClassificationOverride(
        closetItemID: UUID,
        override: FitMatchClosetClassificationOverride
    ) async throws {
        throw FitMatchSupabaseProductResolverError.vnextIdentityRequired
    }

    func clearClosetClassificationOverride(closetItemID: UUID) async throws {
        throw FitMatchSupabaseProductResolverError.vnextIdentityRequired
    }
}

extension FitMatchSupabaseDomainClient: FitMatchClosetRemoteServicing {}

enum FitMatchClosetSyncState: Equatable {
    case idle
    case syncing
    case synced
    case pendingRetry
}

/// The cache must be claimed by the authenticated user before any user-owned
/// SwiftData row is allowed to reach presentation.  This is deliberately a
/// synchronous, production-used boundary: a network sync is too late to
/// prevent a newly signed-in user from briefly seeing the preceding account's
/// Closet or History cache.
enum FitMatchLocalCachePreparationOutcome: Equatable {
    case alreadyOwned
    case claimedEmptyOrUnownedCache
    case purgedForeignOwnerCache
}

enum FitMatchClosetAuthorityError: LocalizedError {
    case classificationReviewRequired
    case notComparable
    case unavailableClassification

    var errorDescription: String? {
        switch self {
        case .classificationReviewRequired:
            return "서버에서 상품 분류 검토가 필요합니다."
        case .notComparable:
            return "이 상품은 비교 대상이 아닙니다."
        case .unavailableClassification:
            return "서버 상품 분류를 확인하지 못했습니다."
        }
    }
}

private enum FitMatchClosetSyncInterruption: Error {
    case superseded
}

@MainActor
final class FitMatchClosetSyncCoordinator: ObservableObject {
    @Published private(set) var state: FitMatchClosetSyncState = .idle
    @Published private(set) var lastErrorMessage: String?

    private let remote: any FitMatchClosetRemoteServicing
    private let authorityCoordinator: FitMatchServerAuthorityCoordinator
    private let defaults: UserDefaults
    private var activeUserID: UUID?
    private var isSynchronizing = false
    private var needsAnotherPass = false
    private var pendingSyncUserID: UUID?
    private var remoteItemsByClientID: [UUID: FitMatchClosetItemRecord] = [:]

    private static let cacheOwnerKey = "FitMatch.closetCacheOwnerUserID"
    private static let pendingDeletePrefix = "FitMatch.closetPendingDelete."

    init(
        remote: (any FitMatchClosetRemoteServicing)? = nil,
        defaults: UserDefaults = .standard
    ) {
        let remote = remote ?? FitMatchSupabaseDomainClient.shared
        self.remote = remote
        authorityCoordinator = FitMatchServerAuthorityCoordinator(remote: remote)
        self.defaults = defaults
    }

    /// Establishes the authenticated session boundary before any cached
    /// Closet rows are allowed to present.  In-flight work for a prior
    /// account becomes ineligible to apply as soon as the session changes;
    /// `prepareLocalCache` then owns the durable SwiftData boundary.
    func prepareForAuthenticatedUser(_ userID: UUID?) {
        guard activeUserID != userID else { return }
        activeUserID = userID
        remoteItemsByClientID.removeAll()
        pendingSyncUserID = nil
        needsAnotherPass = false
        if userID == nil {
            state = .idle
            lastErrorMessage = nil
        }
    }

    func synchronize(userID: UUID, modelContext: ModelContext) async {
        // ContentView cancels its old account-scoped task on session changes.
        // Do not let a cancellation that has already arrived reclaim cache
        // ownership for the outgoing account.
        guard !Task.isCancelled else { return }
        prepareForAuthenticatedUser(userID)
        if isSynchronizing {
            needsAnotherPass = true
            pendingSyncUserID = userID
            return
        }

        isSynchronizing = true
        defer { isSynchronizing = false }

        var passUserID = userID
        while true {
            needsAnotherPass = false
            pendingSyncUserID = nil
            await synchronizeOnce(userID: passUserID, modelContext: modelContext)

            // A later authenticated session always owns the follow-up pass.
            // Replaying the outgoing user here could rewrite the new user's
            // cache-owner marker or hydrate stale account rows after the root
            // has already made the new account presentable.
            if let pendingSyncUserID {
                passUserID = pendingSyncUserID
                continue
            }
            if let activeUserID, activeUserID != passUserID {
                passUserID = activeUserID
                continue
            }
            if needsAnotherPass {
                continue
            }
            break
        }
    }

    func enqueueDeletion(clientItemID: UUID) {
        guard let activeUserID else { return }
        var pending = pendingDeleteIDs(for: activeUserID)
        pending.insert(clientItemID)
        storePendingDeleteIDs(pending, for: activeUserID)
    }

    func cancelDeletion(clientItemID: UUID) {
        guard let activeUserID else { return }
        var pending = pendingDeleteIDs(for: activeUserID)
        pending.remove(clientItemID)
        storePendingDeleteIDs(pending, for: activeUserID)
    }

    func purgeLocalAccountData(modelContext: ModelContext) throws {
        let histories = try modelContext.fetch(FetchDescriptor<RecommendationHistory>())
        histories.forEach(modelContext.delete)
        let items = try modelContext.fetch(FetchDescriptor<UserFit>())
        items.forEach(modelContext.delete)
        try modelContext.save()

        let storedOwner = defaults.string(forKey: Self.cacheOwnerKey).flatMap(UUID.init(uuidString:))
        Set([activeUserID, storedOwner].compactMap { $0 }).forEach { userID in
            defaults.removeObject(forKey: Self.pendingDeletePrefix + userID.uuidString)
        }
        defaults.removeObject(forKey: Self.cacheOwnerKey)
        FavoriteProductStore(defaults: defaults).removeAll()
        SourceCategoryHistoryMatcher.clearStoredMappings(defaults: defaults)
        activeUserID = nil
        remoteItemsByClientID.removeAll()
        needsAnotherPass = false
        pendingSyncUserID = nil
        state = .idle
        lastErrorMessage = nil
    }

    private func synchronizeOnce(userID: UUID, modelContext: ModelContext) async {
        guard isCurrentSyncUser(userID) else { return }
        state = .syncing
        lastErrorMessage = nil

        do {
            try prepareLocalCache(for: userID, modelContext: modelContext)
            guard isCurrentSyncUser(userID) else { return }
            var remoteResponse = try await remote.listClosetItems()
            guard isCurrentSyncUser(userID) else { return }
            guard remoteResponse.state == "ready" else {
                throw FitMatchSupabaseProductResolverError.authenticationRequired
            }

            remoteItemsByClientID = Dictionary(
                uniqueKeysWithValues: remoteResponse.items.map { ($0.clientItemID, $0) }
            )
            try await flushPendingDeletes(userID: userID)
            guard isCurrentSyncUser(userID) else { return }
            remoteResponse = try await remote.listClosetItems()
            guard isCurrentSyncUser(userID) else { return }
            remoteItemsByClientID = Dictionary(
                uniqueKeysWithValues: remoteResponse.items.map { ($0.clientItemID, $0) }
            )

            let localItems = try modelContext.fetch(FetchDescriptor<UserFit>())
                .filter(\.isActiveClosetItem)
            var failedUpsert = false
            var failedAutomaticAuthorityValidationIDs = Set<UUID>()
            for localItem in localItems {
                guard isCurrentSyncUser(userID) else { return }
                if let remoteItem = remoteItemsByClientID[localItem.id],
                   remoteDate(remoteItem) > localItem.updatedAt.addingTimeInterval(1) {
                    try apply(remoteItem, to: localItem, modelContext: modelContext)
                    if remoteItem.classificationStatus == "confirmed",
                       remoteItem.classificationSource == "manual_override" {
                        continue
                    }
                }

                do {
                    let request = try await makeUpsertRequest(for: localItem, userID: userID)
                    guard isCurrentSyncUser(userID) else { return }
                    let closetItemID: UUID
                    if let existing = remoteItemsByClientID[localItem.id] {
                        _ = try await remote.updateClosetItem(
                            request,
                            closetItemID: existing.closetItemID
                        )
                        guard isCurrentSyncUser(userID) else { return }
                        closetItemID = existing.closetItemID
                    } else {
                        closetItemID = try await remote.upsertClosetItem(request).closetItemID
                        guard isCurrentSyncUser(userID) else { return }
                    }
                    if let override = request.override, request.productID != nil {
                        try await remote.setClosetClassificationOverride(
                            closetItemID: closetItemID,
                            override: override
                        )
                        guard isCurrentSyncUser(userID) else { return }
                    } else if remoteItemsByClientID[localItem.id]?.classificationSource
                                == "manual_override",
                              request.productID != nil {
                        try await remote.clearClosetClassificationOverride(
                            closetItemID: closetItemID
                        )
                        guard isCurrentSyncUser(userID) else { return }
                    }
                } catch {
                    guard isCurrentSyncUser(userID) else { return }
                    failedUpsert = true
                    if localItem.sourceProduct != nil,
                       localItem.classificationAuthorityProvenance == .serverUnavailable {
                        failedAutomaticAuthorityValidationIDs.insert(localItem.id)
                    }
                    #if DEBUG
                    print("[FitMatchClosetSync] upsert failed item=\(localItem.id): \(error.localizedDescription)")
                    #endif
                }
            }

            // Refresh IDs after creates/updates, then reconcile exact item
            // deltas. Server set(true) remains responsible for atomic
            // same-tuple replacement.
            let beforeReference = try await remote.listClosetItems()
            guard isCurrentSyncUser(userID) else { return }
            guard beforeReference.state == "ready" else {
                throw FitMatchSupabaseProductResolverError.authenticationRequired
            }
            remoteItemsByClientID = Dictionary(
                uniqueKeysWithValues: beforeReference.items.map { ($0.clientItemID, $0) }
            )
            try await synchronizeReferenceAuthority(localItems: localItems, userID: userID)
            guard isCurrentSyncUser(userID) else { return }

            let authoritative = try await remote.listClosetItems()
            guard isCurrentSyncUser(userID) else { return }
            guard authoritative.state == "ready" else {
                throw FitMatchSupabaseProductResolverError.authenticationRequired
            }
            remoteItemsByClientID = Dictionary(
                uniqueKeysWithValues: authoritative.items.map { ($0.clientItemID, $0) }
            )

            let currentLocalItems = try modelContext.fetch(FetchDescriptor<UserFit>())
            let currentByID = Dictionary(uniqueKeysWithValues: currentLocalItems.map { ($0.id, $0) })
            for remoteItem in authoritative.items {
                guard isCurrentSyncUser(userID) else { return }
                if let localItem = currentByID[remoteItem.clientItemID] {
                    if failedAutomaticAuthorityValidationIDs.contains(remoteItem.clientItemID),
                       remoteItem.classificationSource != "manual_override" {
                        // The list snapshot can still point at stale v3 current
                        // history. Do not let it undo the fail-closed state set
                        // by a failed active-v4 resolve in this same pass.
                        continue
                    }
                    try apply(remoteItem, to: localItem, modelContext: modelContext)
                } else {
                    let localItem = try makeLocalItem(from: remoteItem, modelContext: modelContext)
                    modelContext.insert(localItem)
                }
            }
            try modelContext.save()
            guard isCurrentSyncUser(userID) else { return }

            if failedUpsert {
                state = .pendingRetry
                lastErrorMessage = "일부 옷장 변경사항을 서버에 저장하지 못했습니다. 자동으로 다시 시도합니다."
            } else {
                state = .synced
            }
        } catch {
            guard isCurrentSyncUser(userID) else { return }
            modelContext.rollback()
            state = .pendingRetry
            lastErrorMessage = error.localizedDescription
            #if DEBUG
            print("[FitMatchClosetSync] sync failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func synchronizeReferenceAuthority(
        localItems: [UserFit],
        userID: UUID
    ) async throws {
        guard isCurrentSyncUser(userID) else { return }
        let localByClientID = Dictionary(
            uniqueKeysWithValues: localItems.map { ($0.id, $0) }
        )
        let setCandidates = localItems.filter { item in
            item.isRepresentative
                && remoteItemsByClientID[item.id]?.isReference == false
        }.sorted { $0.id.uuidString < $1.id.uuidString }

        for item in setCandidates {
            guard isCurrentSyncUser(userID) else { return }
            guard let remoteItem = remoteItemsByClientID[item.id] else { continue }
            _ = try await remote.setClosetReference(
                closetItemID: remoteItem.closetItemID,
                isReference: true
            )
            guard isCurrentSyncUser(userID) else { return }
        }

        if !setCandidates.isEmpty {
            let refreshed = try await remote.listClosetItems()
            guard isCurrentSyncUser(userID) else { return }
            guard refreshed.state == "ready" else {
                throw FitMatchSupabaseProductResolverError.authenticationRequired
            }
            remoteItemsByClientID = Dictionary(
                uniqueKeysWithValues: refreshed.items.map { ($0.clientItemID, $0) }
            )
        }

        let unsetCandidates = remoteItemsByClientID.values.filter { remoteItem in
            guard remoteItem.isReference,
                  let localItem = localByClientID[remoteItem.clientItemID] else {
                return false
            }
            return !localItem.isRepresentative
        }.sorted { $0.clientItemID.uuidString < $1.clientItemID.uuidString }

        for remoteItem in unsetCandidates {
            guard isCurrentSyncUser(userID) else { return }
            // A remote-only row is absent from localByClientID and is therefore
            // hydration input, never an implicit first-login unset intent.
            _ = try await remote.setClosetReference(
                closetItemID: remoteItem.closetItemID,
                isReference: false
            )
            guard isCurrentSyncUser(userID) else { return }
        }
    }

    @discardableResult
    func prepareLocalCache(
        for userID: UUID,
        modelContext: ModelContext
    ) throws -> FitMatchLocalCachePreparationOutcome {
        let storedOwner = defaults.string(forKey: Self.cacheOwnerKey).flatMap(UUID.init(uuidString:))
        let histories = try modelContext.fetch(FetchDescriptor<RecommendationHistory>())
        let items = try modelContext.fetch(FetchDescriptor<UserFit>())
        let containsUserScopedRows = !histories.isEmpty || !items.isEmpty

        // A missing cache-owner marker is not evidence that this newly
        // authenticated user owns persisted rows. Legacy/pre-marker rows must
        // fail closed before MainTabView can present them to another account.
        let mustPurge = storedOwner.map { $0 != userID } ?? containsUserScopedRows
        if mustPurge {
            histories.forEach(modelContext.delete)
            items.forEach(modelContext.delete)
            if containsUserScopedRows {
                try modelContext.save()
            }
            clearUserScopedPresentationState()
            remoteItemsByClientID.removeAll()
            activeUserID = userID
            defaults.set(userID.uuidString, forKey: Self.cacheOwnerKey)
            return .purgedForeignOwnerCache
        }

        activeUserID = userID
        defaults.set(userID.uuidString, forKey: Self.cacheOwnerKey)
        return storedOwner == userID ? .alreadyOwned : .claimedEmptyOrUnownedCache
    }

    private func clearUserScopedPresentationState() {
        FavoriteProductStore(defaults: defaults).removeAll()
        SourceCategoryHistoryMatcher.clearStoredMappings(defaults: defaults)
    }

    private func flushPendingDeletes(userID: UUID) async throws {
        guard isCurrentSyncUser(userID) else { return }
        var pending = pendingDeleteIDs(for: userID)
        guard !pending.isEmpty else { return }

        for clientItemID in pending {
            guard isCurrentSyncUser(userID) else { return }
            guard let remoteItem = remoteItemsByClientID[clientItemID] else {
                pending.remove(clientItemID)
                continue
            }
            _ = try await remote.deleteClosetItem(closetItemID: remoteItem.closetItemID)
            guard isCurrentSyncUser(userID) else { return }
            pending.remove(clientItemID)
            remoteItemsByClientID.removeValue(forKey: clientItemID)
        }
        guard isCurrentSyncUser(userID) else { return }
        storePendingDeleteIDs(pending, for: userID)
    }

    private func makeUpsertRequest(
        for item: UserFit,
        userID: UUID
    ) async throws -> FitMatchUpsertClosetItemRequest {
        guard isCurrentSyncUser(userID) else {
            throw FitMatchClosetSyncInterruption.superseded
        }
        // Older direct-entry rows predate explicit authority provenance. A row
        // with no linked retailer product can only have come from the manual
        // Closet form, so migrate that user choice lazily without a bulk write.
        if item.classificationAuthorityProvenance == nil,
           item.sourceProduct == nil,
           item.sourceType == .manual {
            item.markClassificationAuthority(.userExplicit)
        }

        var productID = remoteItemsByClientID[item.id]?.productID
        var productVariantID = remoteItemsByClientID[item.id]?.variantID
        var productSizeID = remoteItemsByClientID[item.id]?.productSizeID
        let existingRemoteItem = remoteItemsByClientID[item.id]

        if let existingRemoteItem,
           existingRemoteItem.classificationStatus == "confirmed",
           existingRemoteItem.classificationSource == "manual_override" {
            // A persisted user override is already explicit authority. Every
            // sourced automatic classification (including an old v3 history
            // row) must still pass through the active v4 runtime below.
            try applyRemoteAuthority(existingRemoteItem, to: item)
        } else if let product = item.sourceProduct,
                  let request = product.fitMatchDatabaseResolutionRequest() {
            do {
                let authority = try await authorityCoordinator.resolveProductAuthority(
                    request: request,
                    observation: product.fitMatchProductObservationRequest()
                )
                guard isCurrentSyncUser(userID) else {
                    throw FitMatchClosetSyncInterruption.superseded
                }
                try applyServerAuthority(authority, to: item)
                productID = authority.productID
                let identity = uniqueRuntimeSizeIdentity(
                    in: authority.runtime,
                    matching: item.sizeName,
                    colorName: product.checkedColorName
                )
                productVariantID = identity?.variantID
                productSizeID = identity?.sizeID
            } catch {
                if error is FitMatchClosetSyncInterruption {
                    throw error
                }
                if item.classificationAuthorityProvenance != .userExplicit,
                   !(error is FitMatchClosetAuthorityError) {
                    item.markClassificationAuthority(.serverUnavailable)
                }
                throw error
            }
        } else if let existingRemoteItem {
            switch existingRemoteItem.classificationStatus {
            case "review_required", "unclassified", "not_comparable":
                try applyRemoteAuthority(existingRemoteItem, to: item)
            default:
                // An automatic remote snapshot can point at pre-v4 current
                // history. Without source facts it cannot prove active-runtime
                // authority, so keep the item fail-closed until it can be
                // resolved again. Only a persisted manual_override bypasses
                // this validation path.
                item.markClassificationAuthority(
                    .serverUnavailable,
                    sourceIdentity: existingRemoteItem.classificationSource
                )
                throw FitMatchClosetAuthorityError.unavailableClassification
            }
        } else if item.classificationAuthorityProvenance != .userExplicit {
            item.markClassificationAuthority(.localHint)
            throw FitMatchClosetAuthorityError.unavailableClassification
        }

        var override: FitMatchClosetClassificationOverride?
        if productID != nil,
           item.classificationAuthorityProvenance == .userExplicit {
            guard let familyCode = resolvedFamilyCode(for: item) else {
                throw FitMatchClosetAuthorityError.unavailableClassification
            }
            override = FitMatchClosetClassificationOverride(
                audienceCode: item.resolvedGenderCode,
                categoryCode: item.resolvedCategoryCode ?? item.category.taxonomyCode,
                detailCode: item.resolvedDetailCategoryCode ?? "other",
                familyCode: familyCode,
                lengthCode: resolvedLengthCode(for: item),
                bodyLengthCode: resolvedBodyLengthCode(for: item),
                reason: "user_confirmed_closet_classification",
                evidence: [
                    "classification_authority": FitMatchClassificationAuthorityProvenance
                        .userExplicit.rawValue,
                    "client_item_id": item.id.uuidString
                ]
            )
        }

        return FitMatchUpsertClosetItemRequest(
            clientItemID: item.id,
            item: payload(for: item),
            productID: productID,
            productVariantID: productVariantID,
            productSizeID: productSizeID,
            override: override
        )
    }

    private func isCurrentSyncUser(_ userID: UUID) -> Bool {
        activeUserID == userID && !Task.isCancelled
    }

    private func payload(for item: UserFit) -> FitMatchClosetItemPayload {
        let records = item.measurementRecords.map { record in
            FitMatchClosetMeasurementRecordPayload(
                value: record.value,
                unit: record.unitRawValue,
                measurementCode: record.measurementCodeRawValue,
                displayKind: record.displayKindRawValue,
                methodSource: record.methodSource,
                methodProfile: record.methodProfile,
                inputSource: record.inputSourceRawValue,
                standardVersion: record.standardVersion,
                mappingVersion: record.mappingVersion,
                rawCode: record.rawCode,
                rawLabel: record.rawLabel,
                rawInfo: record.rawInfo,
                rawValueText: record.rawValueText,
                evidenceLevel: record.evidenceLevelRawValue,
                semanticStatus: record.semanticStatusRawValue
            )
        }
        var clientSnapshot = [
            "local_model": "UserFit",
            "local_schema": "1"
        ]
        if let authority = item.classificationAuthorityProvenance {
            clientSnapshot["classification_authority"] = authority.rawValue
        }
        if let productCode = item.sourceProduct?.productCode, !productCode.isEmpty {
            clientSnapshot["external_product_id"] = productCode
        }

        return FitMatchClosetItemPayload(
            productName: item.productName,
            brand: item.brandName,
            sizeName: item.sizeName,
            genderCode: item.resolvedGenderCode,
            source: resolvedSourceCode(for: item),
            categoryCode: item.resolvedCategoryCode ?? item.category.taxonomyCode,
            detailCode: item.resolvedDetailCategoryCode ?? "other",
            familyCode: resolvedFamilyCode(for: item),
            lengthCode: resolvedLengthCode(for: item),
            bodyLengthCode: resolvedBodyLengthCode(for: item),
            sourceCategoryPath: item.sourceCategoryPath ?? item.sourceProduct?.sourceCategoryPath,
            productURL: item.sourceProduct?.sourceURLString,
            imageURL: item.sourceProduct?.imageURLString,
            measurements: measurementValues(for: item),
            measurementRecords: records,
            fitMemo: item.fitMemo,
            fitPreferenceCode: item.fitPreference.databaseCode,
            satisfaction: item.satisfaction,
            isReference: item.isRepresentative,
            classificationVersion: item.canonicalPolicyVersion,
            clientSnapshot: clientSnapshot,
            clientCreatedAt: encodeDate(item.createdAt),
            clientUpdatedAt: encodeDate(item.updatedAt)
        )
    }

    private func uniqueRuntimeSizeIdentity(
        in runtime: FitMatchProductRuntimeResponse,
        matching sizeName: String,
        colorName: String?
    ) -> (variantID: UUID, sizeID: UUID)? {
        let normalizedSize = sizeName.fitMatchDisplaySizeName.lowercased()
        var variants = runtime.variants
        if let colorName = colorName?.nilIfBlank {
            let colorMatches = variants.filter {
                $0.colorName?.localizedCaseInsensitiveCompare(colorName) == .orderedSame
                    || $0.variantName?.localizedCaseInsensitiveCompare(colorName) == .orderedSame
            }
            if !colorMatches.isEmpty { variants = colorMatches }
        }
        let matches = variants.flatMap { variant in
            variant.sizes.compactMap { size -> (UUID, UUID)? in
                guard size.sizeLabel.fitMatchDisplaySizeName.lowercased() == normalizedSize
                        || size.normalizedSizeLabel.fitMatchDisplaySizeName.lowercased()
                            == normalizedSize else { return nil }
                return (variant.variantID, size.productSizeID)
            }
        }
        return matches.count == 1
            ? (variantID: matches[0].0, sizeID: matches[0].1)
            : nil
    }

    private func applyRemoteAuthority(
        _ record: FitMatchClosetItemRecord,
        to item: UserFit
    ) throws {
        switch record.classificationStatus {
        case "confirmed":
            if item.classificationAuthorityProvenance == .userExplicit,
               record.classificationSource != "manual_override" {
                // Preserve a newer explicit local selection long enough to send
                // it as an override. A server classification must never turn an
                // unrelated local inference into an override.
                return
            }
            applyClassification(record, to: item)
        case "review_required", "unclassified":
            guard item.classificationAuthorityProvenance != .userExplicit else { return }
            applyClassification(record, to: item)
            throw FitMatchClosetAuthorityError.classificationReviewRequired
        case "not_comparable":
            applyClassification(record, to: item)
            throw FitMatchClosetAuthorityError.notComparable
        default:
            item.markClassificationAuthority(
                .serverUnavailable,
                sourceIdentity: record.classificationSource
            )
            throw FitMatchClosetAuthorityError.unavailableClassification
        }
    }

    private func applyServerAuthority(
        _ authority: FitMatchServerProductAuthority,
        to item: UserFit
    ) throws {
        let userExplicit = item.classificationAuthorityProvenance == .userExplicit
        let shoppingPersonalAuthority = authority.classification.authorityStatus?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "user_explicit"

        // A shopping Product may be personally confirmed for the signed-in
        // user without that user ever choosing a Closet classification. Keep
        // a sourced Closet row fail-closed until its own explicit Closet
        // action creates an override; never relabel the product-scoped choice
        // as either a Global confirmation or a Closet manual override.
        if shoppingPersonalAuthority, !userExplicit {
            item.markClassificationAuthority(
                .localHint,
                sourceIdentity: "shopping_user_explicit_not_closet_authority"
            )
            return
        }

        switch authority.status {
        case .confirmed:
            if !userExplicit {
                applyDatabaseClassification(
                    authority.classification,
                    provenance: .serverConfirmed,
                    to: item
                )
            }
        case .reviewRequired:
            guard userExplicit else {
                applyDatabaseClassification(
                    authority.classification,
                    provenance: .serverReviewRequired,
                    to: item
                )
                throw FitMatchClosetAuthorityError.classificationReviewRequired
            }
        case .notComparable:
            applyDatabaseClassification(
                authority.classification,
                provenance: .serverNotComparable,
                to: item
            )
            throw FitMatchClosetAuthorityError.notComparable
        }
    }

    private func applyDatabaseClassification(
        _ classification: FitMatchDatabaseClassification,
        provenance: FitMatchClassificationAuthorityProvenance,
        to item: UserFit
    ) {
        if let categoryCode = classification.categoryCode {
            item.category = ClothingCategory.fromTaxonomyCode(categoryCode)
            item.categoryCode = categoryCode
        }
        if let detailCode = classification.detailCode {
            item.detailCategory = ClosetDetailCategory.fromTaxonomyCode(detailCode)
            item.detailCategoryCode = detailCode
            item.normalizedProductTypeCode = detailCode
        }
        item.garmentTypeRawValue = classification.garmentTypeCode
            ?? classification.familyCode
        item.sleeveTypeRawValue = classification.lengthCode
        item.canonicalPolicyVersion = classification.taxonomyPolicyVersion
            ?? classification.decisionVersion
        item.markClassificationAuthority(
            provenance,
            sourceIdentity: classification.method
        )

        guard provenance != .userExplicit, let product = item.sourceProduct else { return }
        if let categoryCode = classification.categoryCode {
            product.category = ClothingCategory.fromTaxonomyCode(categoryCode)
            product.categoryCode = categoryCode
        }
        if let detailCode = classification.detailCode {
            product.normalizedProductTypeCode = detailCode
        }
        product.garmentTypeRawValue = classification.garmentTypeCode
            ?? classification.familyCode
        product.sleeveTypeRawValue = classification.lengthCode
        product.canonicalPolicyVersion = classification.taxonomyPolicyVersion
            ?? classification.decisionVersion
        product.markClassificationAuthority(
            provenance,
            sourceIdentity: classification.method
        )
    }

    private func makeLocalItem(
        from record: FitMatchClosetItemRecord,
        modelContext: ModelContext
    ) throws -> UserFit {
        let category = ClothingCategory.fromTaxonomyCode(record.categoryCode)
        let detail = ClosetDetailCategory.fromTaxonomyCode(record.detailCode)
        let gender = UserGender.fromTaxonomyCode(record.genderCode ?? "unknown")
        let product = try restoredProduct(from: record, category: category, modelContext: modelContext)
        let size = try restoredProductSize(
            from: record,
            product: product,
            modelContext: modelContext
        )
        let item = UserFit(
            id: record.clientItemID,
            sourceType: sourceType(for: record.source),
            sourceName: sourceDisplayName(for: record.source),
            sourceCategoryPath: record.sourceCategoryPath,
            brandName: record.brand ?? "브랜드 없음",
            gender: gender,
            productName: record.productName,
            category: category,
            detailCategory: detail,
            sizeName: record.sizeName ?? "기준",
            measurements: restoredMeasurements(from: record),
            fitMemo: record.fitMemo,
            fitPreference: FitPreference.fromDatabaseCode(record.fitPreferenceCode),
            satisfaction: record.satisfaction,
            isRepresentative: record.isReference,
            sourceProduct: product,
            sourceProductSize: size,
            createdAt: decodeDate(record.clientCreatedAt ?? record.createdAt) ?? Date(),
            updatedAt: decodeDate(record.clientUpdatedAt ?? record.updatedAt) ?? Date()
        )
        applyClassification(
            record,
            to: item,
            automaticConfirmedIsActiveRuntimeValidated: false
        )
        item.replaceMeasurementRecords(with: restoredMeasurementRecords(from: record, item: item))
        item.updatedAt = decodeDate(record.clientUpdatedAt ?? record.updatedAt) ?? item.updatedAt
        return item
    }

    private func apply(
        _ record: FitMatchClosetItemRecord,
        to item: UserFit,
        modelContext: ModelContext
    ) throws {
        let category = ClothingCategory.fromTaxonomyCode(record.categoryCode)
        let detail = ClosetDetailCategory.fromTaxonomyCode(record.detailCode)
        item.sourceType = sourceType(for: record.source)
        item.sourceName = sourceDisplayName(for: record.source)
        item.sourcePlatformCode = record.source
        item.sourceCategoryPath = record.sourceCategoryPath
        item.brandName = record.brand ?? "브랜드 없음"
        item.gender = UserGender.fromTaxonomyCode(record.genderCode ?? "unknown")
        item.productName = record.productName
        item.category = category
        item.detailCategory = detail
        item.sizeName = record.sizeName ?? "기준"
        item.measurements = restoredMeasurements(from: record)
        item.fitMemo = record.fitMemo
        item.fitPreference = FitPreference.fromDatabaseCode(record.fitPreferenceCode)
        item.satisfaction = record.satisfaction
        item.isRepresentative = record.isReference
        item.measurementRecords.forEach(modelContext.delete)
        item.replaceMeasurementRecords(with: restoredMeasurementRecords(from: record, item: item))
        item.sourceProduct = try restoredProduct(from: record, category: category, modelContext: modelContext)
        item.sourceProductSize = try restoredProductSize(
            from: record,
            product: item.sourceProduct,
            modelContext: modelContext
        )
        applyClassification(record, to: item)
        item.createdAt = decodeDate(record.clientCreatedAt ?? record.createdAt) ?? item.createdAt
        item.updatedAt = decodeDate(record.clientUpdatedAt ?? record.updatedAt) ?? item.updatedAt
    }

    private func applyClassification(
        _ record: FitMatchClosetItemRecord,
        to item: UserFit,
        automaticConfirmedIsActiveRuntimeValidated: Bool = true
    ) {
        item.category = ClothingCategory.fromTaxonomyCode(record.categoryCode)
        item.detailCategory = ClosetDetailCategory.fromTaxonomyCode(record.detailCode)
        item.categoryCode = record.categoryCode
        item.detailCategoryCode = record.detailCode
        item.normalizedProductTypeCode = record.detailCode
        item.garmentTypeRawValue = record.familyCode
        item.sleeveTypeRawValue = record.lengthCode
        item.canonicalPolicyVersion = record.classificationSnapshot["decision_version"] ?? nil
        let provenance: FitMatchClassificationAuthorityProvenance
        switch record.classificationStatus {
        case "confirmed":
            if record.classificationSource == "manual_override" {
                provenance = .userExplicit
            } else {
                // A remote-only automatic row can still be backed by stale v3
                // current history. It becomes server-confirmed only after the
                // sourced item has passed the active-v4 lazy-resolution path.
                provenance = automaticConfirmedIsActiveRuntimeValidated
                    ? .serverConfirmed
                    : .serverUnavailable
            }
        case "review_required", "unclassified":
            provenance = .serverReviewRequired
        case "not_comparable":
            provenance = .serverNotComparable
        default:
            provenance = .serverUnavailable
        }
        item.markClassificationAuthority(
            provenance,
            sourceIdentity: record.classificationSource
        )

        guard provenance != .userExplicit, let product = item.sourceProduct else { return }
        let productCategoryCode = record.canonicalCategoryCode ?? record.categoryCode
        product.category = ClothingCategory.fromTaxonomyCode(productCategoryCode)
        product.categoryCode = productCategoryCode
        product.normalizedProductTypeCode = record.canonicalDetailCode ?? record.detailCode
        product.garmentTypeRawValue = record.familyCode
        product.sleeveTypeRawValue = record.lengthCode
        product.canonicalPolicyVersion = record.classificationSnapshot["decision_version"] ?? nil
        product.markClassificationAuthority(
            provenance,
            sourceIdentity: record.classificationSource
        )
    }

    private func restoredProduct(
        from record: FitMatchClosetItemRecord,
        category: ClothingCategory,
        modelContext: ModelContext
    ) throws -> Product? {
        guard let productID = record.productID else { return nil }
        let descriptor = FetchDescriptor<Product>(predicate: #Predicate { $0.id == productID })
        if let existing = try modelContext.fetch(descriptor).first { return existing }

        let codes = record.sourceCategoryCodes
        let metadata = ProductMetadata(
            sourceCategoryPath: record.sourceCategoryPath,
            categoryDepth1Code: codes.indices.contains(0) ? codes[0] : nil,
            categoryDepth2Code: codes.indices.contains(1) ? codes[1] : nil,
            categoryDepth3Code: codes.indices.contains(2) ? codes[2] : nil,
            categoryDepth4Code: codes.indices.contains(3) ? codes[3] : nil,
            genderCodes: record.productAudience.map { [$0] } ?? []
        )
        let product = Product(
            id: productID,
            name: record.productName,
            category: category,
            productCode: record.externalProductID,
            sourceURLString: record.productURL,
            imageURLString: record.imageURL,
            metadata: metadata,
            sourceType: sourceType(for: record.source),
            sourceName: sourceDisplayName(for: record.source),
            source: .catalog
        )
        modelContext.insert(product)
        return product
    }

    private func restoredProductSize(
        from record: FitMatchClosetItemRecord,
        product: Product?,
        modelContext: ModelContext
    ) throws -> ProductSize? {
        guard let productSizeID = record.productSizeID, let product else { return nil }
        let descriptor = FetchDescriptor<ProductSize>(predicate: #Predicate { $0.id == productSizeID })
        if let existing = try modelContext.fetch(descriptor).first { return existing }
        let size = ProductSize(
            id: productSizeID,
            name: record.sizeName ?? "기준",
            measurements: restoredMeasurements(from: record),
            product: product
        )
        modelContext.insert(size)
        return size
    }

    private func restoredMeasurementRecords(
        from record: FitMatchClosetItemRecord,
        item: UserFit
    ) -> [GarmentMeasurementRecord] {
        record.measurementRecords.compactMap { payload in
            let code = localMeasurementCode(payload.measurementCode)
            guard code != .unknown else { return nil }
            return GarmentMeasurementRecord(
                value: payload.value,
                unit: MeasurementUnit(rawValue: payload.unit) ?? .centimeter,
                measurementCode: code,
                displayKind: MeasurementDisplayKind(rawValue: payload.displayKind) ?? .unknown,
                methodSource: payload.methodSource,
                methodProfile: payload.methodProfile,
                inputSource: MeasurementInputSource(rawValue: payload.inputSource) ?? .importedSizeChart,
                standardVersion: payload.standardVersion,
                mappingVersion: payload.mappingVersion,
                rawCode: payload.rawCode,
                rawLabel: payload.rawLabel,
                rawInfo: payload.rawInfo,
                rawValueText: payload.rawValueText,
                evidenceLevel: MeasurementEvidenceLevel(rawValue: payload.evidenceLevel) ?? .unknown,
                semanticStatus: MeasurementSemanticStatus(rawValue: payload.semanticStatus) ?? .unknownDefinition,
                userFit: item
            )
        }
    }

    private func measurementValues(for item: UserFit) -> [String: Double] {
        var result: [String: Double] = [:]
        for record in item.measurementRecords where record.value.isFinite && record.value > 0 {
            result[record.measurementCodeRawValue] = record.value
        }
        if result.isEmpty {
            let values: [(String, Double)] = [
                ("shoulder_width", item.shoulder),
                ("chest_width", item.chest),
                ("body_length", item.totalLength),
                ("sleeve_length", item.sleeveLength),
                ("waist_width", item.waist),
                ("hip_width", item.hip),
                ("thigh_width", item.thigh),
                ("rise", item.rise),
                ("hem_width", item.hem),
                ("foot_length", item.footLength),
                ("under_bust_width", item.underBust)
            ]
            for (key, value) in values where value.isFinite && value > 0 { result[key] = value }
        }
        return result
    }

    private func restoredMeasurements(from record: FitMatchClosetItemRecord) -> GarmentMeasurements {
        var values: [MeasurementDisplayKind: Double] = [:]
        for measurement in record.measurementRecords where measurement.value > 0 {
            guard let kind = MeasurementDisplayKind(rawValue: measurement.displayKind) else { continue }
            values[kind] = measurement.value
        }
        func value(_ kind: MeasurementDisplayKind, aliases: [String]) -> Double {
            if let value = values[kind] { return value }
            for alias in aliases {
                if let value = record.measurements[alias] { return value }
            }
            return 0
        }
        return GarmentMeasurements(
            shoulder: value(.shoulder, aliases: ["shoulder_width", "shoulder_width_seam_to_seam"]),
            chest: value(.chest, aliases: ["chest_width", "chest_width_pit_to_pit"]),
            totalLength: value(.totalLength, aliases: ["body_length", "body_length_back_neck_to_hem", "pants_outseam"]),
            sleeveLength: value(.sleeveLength, aliases: ["sleeve_length", "sleeve_shoulder_seam_to_cuff"]),
            waist: value(.waist, aliases: ["waist_width", "waist_width_edge_to_edge"]),
            hip: value(.hip, aliases: ["hip_width", "hip_width_at_widest"]),
            thigh: value(.thigh, aliases: ["thigh_width", "thigh_width_crotch_to_outer"]),
            rise: value(.rise, aliases: ["rise", "front_rise", "rise_crotch_to_waist_front"]),
            hem: value(.hem, aliases: ["hem_width", "hem_width_edge_to_edge"]),
            footLength: value(.footLength, aliases: ["foot_length", "foot_length_heel_to_toe"]),
            underBust: value(.underBust, aliases: ["under_bust_width", "under_bust_width_edge_to_edge"])
        )
    }

    private func localMeasurementCode(_ code: String) -> MeasurementCode {
        if let exact = MeasurementCode(rawValue: code) { return exact }
        switch code {
        case "shoulder_width": return .shoulderWidthSeamToSeam
        case "chest_width": return .chestWidthPitToPit
        case "body_length": return .bodyLengthBackNeckToHem
        case "sleeve_length": return .sleeveShoulderSeamToCuff
        case "waist_width": return .waistWidthEdgeToEdge
        case "hip_width": return .hipWidthAtWidest
        case "thigh_width": return .thighWidthCrotchToOuter
        case "rise", "front_rise": return .riseCrotchToWaistFront
        case "hem_width": return .hemWidthEdgeToEdge
        case "foot_length": return .footLengthHeelToToe
        case "under_bust_width": return .underBustWidthEdgeToEdge
        default: return .unknown
        }
    }

    private func resolvedSourceCode(for item: UserFit) -> String {
        if let value = item.sourcePlatformCode?.lowercased(), value == "uniqlo" || value == "musinsa" || value == "zara" || value == "cos" {
            return value
        }
        let text = "\(item.sourceName) \(item.sourceProduct?.sourceName ?? "")".lowercased()
        if text.contains("유니클로") || text.contains("uniqlo") { return "uniqlo" }
        if text.contains("무신사") || text.contains("musinsa") { return "musinsa" }
        if text.contains("zara") || text.contains("자라") { return "zara" }
        if text.contains("cos") { return "cos" }
        return "manual"
    }

    private func sourceType(for source: String) -> ProductSourceType {
        switch source {
        case "uniqlo": return .officialStore
        case "musinsa": return .marketplace
        case "zara": return .officialStore
        case "cos": return .officialStore
        default: return .manual
        }
    }

    private func sourceDisplayName(for source: String) -> String {
        switch source {
        case "uniqlo": return "유니클로 공식몰"
        case "musinsa": return "무신사"
        case "zara": return "ZARA 공식몰"
        case "cos": return "COS 공식몰"
        default: return "직접 입력"
        }
    }

    private func resolvedFamilyCode(for item: UserFit) -> String? {
        if let value = item.garmentTypeRawValue?.nilIfBlank, value != "unknown" { return value }
        return ParsedClosetClassification.resolve(
            category: item.category,
            detailCategory: item.detailCategory,
            sourceDepths: [item.sourceCategoryDepth1, item.sourceCategoryDepth2, item.sourceCategoryDepth3, item.sourceCategoryDepth4],
            sourcePath: item.sourceCategoryPath,
            productName: item.productName
        )?.garmentFamily.rawValue.nilIfBlank
    }

    private func resolvedLengthCode(for item: UserFit) -> String? {
        if let value = item.sleeveTypeRawValue?.nilIfBlank, value != "unknown" { return value }
        return ParsedClosetClassification.resolve(
            category: item.category,
            detailCategory: item.detailCategory,
            sourceDepths: [item.sourceCategoryDepth1, item.sourceCategoryDepth2, item.sourceCategoryDepth3, item.sourceCategoryDepth4],
            sourcePath: item.sourceCategoryPath,
            productName: item.productName
        )?.lengthType.rawValue.nilIfBlank
    }

    private func resolvedBodyLengthCode(for item: UserFit) -> String? {
        guard let value = item.canonicalProfileSnapshot?.lengthAxes.body,
              value != "unknown", value != "not_applicable" else { return nil }
        return value
    }

    private func remoteDate(_ record: FitMatchClosetItemRecord) -> Date {
        decodeDate(record.clientUpdatedAt ?? record.updatedAt) ?? .distantPast
    }

    private func encodeDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func decodeDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func pendingDeleteIDs(for userID: UUID) -> Set<UUID> {
        let key = Self.pendingDeletePrefix + userID.uuidString
        let values = defaults.stringArray(forKey: key) ?? []
        return Set(values.compactMap(UUID.init(uuidString:)))
    }

    private func storePendingDeleteIDs(_ ids: Set<UUID>, for userID: UUID) {
        let key = Self.pendingDeletePrefix + userID.uuidString
        defaults.set(ids.map(\.uuidString).sorted(), forKey: key)
    }
}

private extension FitPreference {
    var databaseCode: String {
        switch self {
        case .slim: return "slim"
        case .regular: return "regular"
        case .semiOver: return "semi_over"
        case .over: return "over"
        case .boxy: return "boxy"
        }
    }

    static func fromDatabaseCode(_ code: String) -> FitPreference {
        switch code {
        case "slim": return .slim
        case "semi_over": return .semiOver
        case "over": return .over
        case "boxy": return .boxy
        default: return .regular
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private struct FitMatchClosetSyncCoordinatorEnvironmentKey: EnvironmentKey {
    static let defaultValue: FitMatchClosetSyncCoordinator? = nil
}

extension EnvironmentValues {
    var fitMatchClosetSyncCoordinator: FitMatchClosetSyncCoordinator? {
        get { self[FitMatchClosetSyncCoordinatorEnvironmentKey.self] }
        set { self[FitMatchClosetSyncCoordinatorEnvironmentKey.self] = newValue }
    }
}
