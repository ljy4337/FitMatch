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
    /// A user-triggered linked edit has already reached the update RPC.  Keep
    /// its exact request in memory until the list receipt is projected so a
    /// local read-back failure cannot turn into a second update with guessed
    /// or newly selected identity.
    private var acceptedLinkedEditReceipts: [UUID: LinkedEditAcceptedReceipt] = [:]

    private static let cacheOwnerKey = "FitMatch.closetCacheOwnerUserID"
    private static let pendingDeletePrefix = "FitMatch.closetPendingDelete."

    private struct LinkedEditAcceptedReceipt {
        let userID: UUID
        let closetItemID: UUID
        let request: FitMatchUpsertClosetItemRequest
        let wantsReference: Bool
        let possibleReplacedReferenceClientIDs: Set<UUID>
        var shouldRetryReferenceMutation: Bool
    }

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
        acceptedLinkedEditReceipts.removeAll()
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
            FitMatchLinkedSizeEditIntentStore.purge(userID: userID, defaults: defaults)
        }
        defaults.removeObject(forKey: Self.cacheOwnerKey)
        FavoriteProductStore(defaults: defaults).removeAll()
        SourceCategoryHistoryMatcher.clearStoredMappings(defaults: defaults)
        activeUserID = nil
        remoteItemsByClientID.removeAll()
        acceptedLinkedEditReceipts.removeAll()
        needsAnotherPass = false
        pendingSyncUserID = nil
        state = .idle
        lastErrorMessage = nil
    }

    enum AuthoritativeRegistrationProjectionError: LocalizedError {
        case receiptMismatch
        case duplicateLocalClientItemID

        var errorDescription: String? {
            switch self {
            case .receiptMismatch:
                return "서버 등록 결과를 안전하게 확인하지 못했습니다. 등록 결과를 다시 확인해 주세요."
            case .duplicateLocalClientItemID:
                return "동일한 옷장 항목이 기기에 중복되어 등록 결과를 안전하게 반영하지 못했습니다."
            }
        }
    }

    /// Projects the *read-back* Closet receipt into SwiftData. This is shared
    /// production mapping, not a second registration-specific mapper: the
    /// same `makeLocalItem` / `apply` routines also hydrate normal account
    /// sync, including unknown future measurement-code retention.
    func projectAuthoritativeRegistration(
        _ record: FitMatchClosetItemRecord,
        expected request: FitMatchUpsertClosetItemRequest,
        acceptedClosetItemID: UUID,
        modelContext: ModelContext,
        persist: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> UserFit {
        guard record.clientItemID == request.clientItemID,
              record.closetItemID == acceptedClosetItemID,
              record.productID == request.productID,
              record.variantID == request.productVariantID,
              record.productSizeID == request.productSizeID else {
            throw AuthoritativeRegistrationProjectionError.receiptMismatch
        }

        let expectedClientItemID = request.clientItemID
        let matches = try modelContext.fetch(
            FetchDescriptor<UserFit>(predicate: #Predicate { $0.id == expectedClientItemID })
        )
        guard matches.count <= 1 else {
            throw AuthoritativeRegistrationProjectionError.duplicateLocalClientItemID
        }

        let item: UserFit
        let inserted: Bool
        if let existing = matches.first {
            item = existing
            inserted = false
            try apply(record, to: item, modelContext: modelContext)
        } else {
            item = try makeLocalItem(from: record, modelContext: modelContext)
            inserted = true
            modelContext.insert(item)
        }

        // The registration receipt stores the database garment/axis tuple,
        // not the UI's exact detail picker code. For the initiating device we
        // still have the accepted request, so retain exactly what the user
        // selected instead of immediately replacing it with a lossy reverse
        // projection such as `tshirt -> 기타`.
        if let override = request.override {
            item.gender = UserGender.fromTaxonomyCode(
                Self.appTaxonomyAudienceCode(override.audienceCode)
            )
            item.genderCode = Self.appTaxonomyAudienceCode(override.audienceCode)
            item.category = ClothingCategory.fromTaxonomyCode(override.categoryCode)
            item.categoryCode = override.categoryCode
            item.detailCategory = ClosetDetailCategory.fromTaxonomyCode(override.detailCode)
            item.detailCategoryCode = override.detailCode
            item.normalizedProductTypeCode = override.detailCode
            if let classification = ParsedClosetClassification.resolve(
                category: item.category,
                detailCategory: item.detailCategory,
                sourceDepths: [],
                sourcePath: nil,
                productName: ""
            ) {
                item.garmentTypeRawValue = classification.garmentFamily.rawValue
                item.sleeveTypeRawValue = classification.lengthType == .unknown
                    ? nil : classification.lengthType.rawValue
                item.constructionTypeRawValue = classification.constructionType.rawValue
            }
            item.markClassificationAuthority(.userExplicit)
        }

        do {
            try persist(modelContext)
        } catch {
            // Do not use ModelContext.rollback(): this shared context can own
            // unsaved edits from another screen. Remove only the object this
            // operation newly inserted; updates remain unsaved and will be
            // reconciled from the same server receipt on retry.
            if inserted {
                modelContext.delete(item)
            }
            throw error
        }
        return item
    }

    private static func appTaxonomyAudienceCode(_ audienceCode: String?) -> String {
        switch FitMatchCanonicalAudience.code(from: audienceCode) {
        case FitMatchCanonicalAudience.men.rawValue: return "male"
        case FitMatchCanonicalAudience.women.rawValue: return "female"
        case FitMatchCanonicalAudience.unisex.rawValue: return "unisex"
        case FitMatchCanonicalAudience.kids.rawValue,
             FitMatchCanonicalAudience.baby.rawValue: return "kids_unisex"
        default: return "unknown"
        }
    }

    /// Prepares a server-linked Closet size edit from two authoritative
    /// receipts: the current owned Closet row and a freshly resolved runtime.
    /// This deliberately has no display-label, colour-name, or `first`-item
    /// fallback.  A missing current UUID is a blocked edit, not a guess.
    func prepareLinkedClosetSizeEdit(
        item: UserFit,
        userID: UUID
    ) async throws -> FitMatchLinkedClosetSizeEditPreparation {
        guard isCurrentSyncUser(userID) else {
            throw FitMatchLinkedClosetSizeEditPreparationError.authenticationChanged
        }
        guard let historicalProduct = item.sourceProduct else {
            throw FitMatchLinkedClosetSizeEditPreparationError.missingRetailerFacts
        }

        let response = try await remote.listClosetItems()
        guard isCurrentSyncUser(userID) else {
            throw FitMatchLinkedClosetSizeEditPreparationError.authenticationChanged
        }
        guard response.state == "ready" else {
            throw FitMatchLinkedClosetSizeEditPreparationError.currentClosetRowUnavailable
        }
        let matchingRows = response.items.filter { $0.clientItemID == item.id }
        guard matchingRows.count == 1,
              let row = matchingRows.first,
              let productID = row.productID,
              let variantID = row.variantID,
              let productSizeID = row.productSizeID else {
            throw FitMatchLinkedClosetSizeEditPreparationError.currentClosetRowUnavailable
        }
        let currentIdentity = FitMatchClosetRegistrationServerIdentity(
            productID: productID,
            productVariantID: variantID,
            productSizeID: productSizeID
        )

        // Reuse the normal historical product resolver rather than creating
        // an edit-only database/variant lookup. Passing the exact current
        // product_size_id lets a multi-variant runtime pick the one variant
        // that actually owns this Closet row.
        let viewModel = ShoppingProductViewModel(
            serverAuthorityCoordinator: authorityCoordinator
        )
        _ = await viewModel.loadProductInfoFromHistoricalProduct(
            historicalProduct,
            preferredProductSizeID: productSizeID
        )
        guard isCurrentSyncUser(userID),
              viewModel.hasLoadedProductInfo,
              let runtimeProduct = viewModel.makeProductForClosetRegistration(
                brand: historicalProduct.brand
              ) else {
            throw FitMatchLinkedClosetSizeEditPreparationError.runtimeIdentityUnavailable
        }

        let context = viewModel.closetRegistrationServerContext
        guard runtimeProduct.id == productID else {
            throw FitMatchLinkedClosetSizeEditPreparationError.runtimeIdentityUnavailable
        }
        let options = runtimeProduct.sizes.compactMap { displaySize -> FitMatchLinkedClosetSizeEditOption? in
            guard let identity = context.identity(for: displaySize.id),
                  identity.productID == productID,
                  identity.productVariantID == variantID else {
                return nil
            }
            return FitMatchLinkedClosetSizeEditOption(
                displaySizeID: displaySize.id,
                productSize: displaySize,
                identity: identity
            )
        }
        let currentOptions = options.filter {
            $0.identity.productSizeID == productSizeID
        }
        guard currentOptions.count == 1 else {
            throw FitMatchLinkedClosetSizeEditPreparationError.runtimeIdentityUnavailable
        }
        return FitMatchLinkedClosetSizeEditPreparation(
            userID: userID,
            clientItemID: item.id,
            currentServerIdentity: currentIdentity,
            options: options,
            initialDisplaySizeID: currentOptions[0].displaySizeID
        )
    }

    /// Performs the user-visible server-first mutation for an already linked
    /// Closet item.  The editor calls this only after
    /// `prepareLinkedClosetSizeEdit` has proved the selected display option's
    /// product/variant/size UUIDs.  No local size or measurements are changed
    /// until the server's list receipt confirms that exact tuple.
    func saveLinkedClosetEdit(
        _ draft: FitMatchLinkedClosetEditDraft,
        userID: UUID,
        modelContext: ModelContext,
        confirmsReferenceReplacement _: Bool
    ) async -> FitMatchLinkedClosetEditSaveOutcome {
        guard isCurrentSyncUser(userID),
              draft.preparation.userID == userID,
              draft.preparation.clientItemID == draft.item.id,
              let selectedOption = draft.selectedOption else {
            return .failed("서버의 최신 사이즈 정보를 확인하지 못했습니다. 다시 시도해 주세요.")
        }

        if let accepted = acceptedLinkedEditReceipts[draft.item.id] {
            guard accepted.userID == userID,
                  accepted.request.productID == selectedOption.identity.productID,
                  accepted.request.productVariantID == selectedOption.identity.productVariantID,
                  accepted.request.productSizeID == selectedOption.identity.productSizeID else {
                return .reconciliationRequired(
                    "서버에 저장된 변경 결과를 확인하는 중입니다. 등록 결과를 다시 확인해 주세요."
                )
            }
            return await reconcileAcceptedLinkedEdit(
                accepted,
                item: draft.item,
                modelContext: modelContext
            )
        }

        let rows: FitMatchClosetItemsResponse
        do {
            rows = try await remote.listClosetItems()
        } catch {
            return .failed(linkedEditErrorMessage(for: error))
        }
        guard isCurrentSyncUser(userID), rows.state == "ready" else {
            return .failed("서버의 현재 옷장 정보를 확인하지 못했습니다. 다시 시도해 주세요.")
        }

        let currentRows = rows.items.filter { $0.clientItemID == draft.item.id }
        guard currentRows.count == 1, let currentRow = currentRows.first,
              currentRow.productID == draft.preparation.currentServerIdentity.productID,
              currentRow.variantID == draft.preparation.currentServerIdentity.productVariantID,
              currentRow.productSizeID == draft.preparation.currentServerIdentity.productSizeID,
              selectedOption.identity.productID == currentRow.productID,
              selectedOption.identity.productVariantID == currentRow.variantID else {
            return .failed("서버의 최신 사이즈 정보를 확인하지 못했습니다. 다시 시도해 주세요.")
        }

        let request: FitMatchUpsertClosetItemRequest
        do {
            request = try linkedEditRequest(
                item: draft.item,
                selectedOption: selectedOption,
                category: draft.category,
                detailCategory: draft.detailCategory,
                categoryCode: draft.categoryCode,
                detailCode: draft.detailCode,
                didExplicitlyChangeClassification: draft.didExplicitlyChangeClassification,
                comparisonGroupCode: draft.comparisonGroupCode,
                isReference: false
            )
        } catch {
            return .failed("선택한 분류를 서버에 안전하게 저장할 수 없습니다. 다시 확인해 주세요.")
        }

        let possiblyReplacedReferenceClientIDs: Set<UUID> = []

        let updateResponse: FitMatchUpsertClosetItemResponse
        do {
            updateResponse = try await remote.updateClosetItem(
                request,
                closetItemID: currentRow.closetItemID
            )
        } catch {
            return .failed(linkedEditErrorMessage(for: error))
        }
        guard updateResponse.clientItemID == request.clientItemID,
              updateResponse.closetItemID == currentRow.closetItemID else {
            // The update could have committed despite a malformed response.
            // Lock this editor to this exact tuple and reconcile by receipt;
            // never manufacture a second mutation from a new size choice.
            let receipt = LinkedEditAcceptedReceipt(
                userID: userID,
                closetItemID: currentRow.closetItemID,
                request: request,
                wantsReference: false,
                possibleReplacedReferenceClientIDs: possiblyReplacedReferenceClientIDs,
                shouldRetryReferenceMutation: false
            )
            acceptedLinkedEditReceipts[draft.item.id] = receipt
            return .reconciliationRequired(
                "서버 수정 결과를 확인하는 중입니다. 등록 결과를 다시 확인해 주세요."
            )
        }
        guard isCurrentSyncUser(userID) else {
            return .failed("로그인 상태가 변경되어 수정 결과를 안전하게 확인할 수 없습니다.")
        }

        let receipt = LinkedEditAcceptedReceipt(
            userID: userID,
            closetItemID: currentRow.closetItemID,
            request: request,
            wantsReference: false,
            possibleReplacedReferenceClientIDs: possiblyReplacedReferenceClientIDs,
            shouldRetryReferenceMutation: false
        )
        acceptedLinkedEditReceipts[draft.item.id] = receipt
        return await reconcileAcceptedLinkedEdit(
            receipt,
            item: draft.item,
            modelContext: modelContext
        )
    }

    /// Once `update_closet_item` has acknowledged an edit, this path never
    /// sends that update again. It only completes a necessary reference
    /// mutation and projects an authoritative list receipt into SwiftData.
    private func reconcileAcceptedLinkedEdit(
        _ initialReceipt: LinkedEditAcceptedReceipt,
        item: UserFit,
        modelContext: ModelContext
    ) async -> FitMatchLinkedClosetEditSaveOutcome {
        var receipt = initialReceipt
        guard isCurrentSyncUser(receipt.userID) else {
            return .failed("로그인 상태가 변경되어 수정 결과를 안전하게 확인할 수 없습니다.")
        }

        if receipt.wantsReference, receipt.shouldRetryReferenceMutation {
            do {
                _ = try await remote.setClosetReference(
                    closetItemID: receipt.closetItemID,
                    isReference: true
                )
                receipt.shouldRetryReferenceMutation = false
                acceptedLinkedEditReceipts[item.id] = receipt
            } catch {
                // A lost response is ambiguous. The following list receipt is
                // the authority; only retry set-reference if it says false.
            }
            guard isCurrentSyncUser(receipt.userID) else {
                return .failed("로그인 상태가 변경되어 수정 결과를 안전하게 확인할 수 없습니다.")
            }
        }

        let rows: FitMatchClosetItemsResponse
        do {
            rows = try await remote.listClosetItems()
        } catch {
            return .reconciliationRequired(
                "서버 수정 결과를 확인하는 중입니다. 등록 결과를 다시 확인해 주세요."
            )
        }
        guard isCurrentSyncUser(receipt.userID), rows.state == "ready" else {
            return .reconciliationRequired(
                "서버 수정 결과를 확인하는 중입니다. 등록 결과를 다시 확인해 주세요."
            )
        }

        let matches = rows.items.filter { $0.clientItemID == receipt.request.clientItemID }
        guard matches.count == 1, let record = matches.first,
              record.closetItemID == receipt.closetItemID,
              record.productID == receipt.request.productID,
              record.variantID == receipt.request.productVariantID,
              record.productSizeID == receipt.request.productSizeID,
              receipt.request.comparisonGroupCode == nil
                || record.comparisonGroupCode == receipt.request.comparisonGroupCode else {
            return .reconciliationRequired(
                "서버 수정 결과를 확인하는 중입니다. 등록 결과를 다시 확인해 주세요."
            )
        }

        guard !receipt.wantsReference || record.isReference else {
            // Preserve the accepted update and retry only the reference
            // mutation after explicit consent; do not re-run update.
            receipt.shouldRetryReferenceMutation = true
            acceptedLinkedEditReceipts[item.id] = receipt
            return .reconciliationRequired(
                "사이즈는 수정됐지만 옷장 저장 상태를 서버에서 확인하지 못했습니다. 등록 결과를 다시 확인해 주세요."
            )
        }

        do {
            try projectAuthoritativeLinkedEdit(
                record,
                allRecords: rows.items,
                receipt: receipt,
                to: item,
                modelContext: modelContext
            )
        } catch {
            return .reconciliationRequired(
                "서버 수정 결과를 기기에 반영하지 못했습니다. 등록 결과를 다시 확인해 주세요."
            )
        }
        guard isCurrentSyncUser(receipt.userID) else {
            return .failed("로그인 상태가 변경되어 수정 결과를 안전하게 확인할 수 없습니다.")
        }
        acceptedLinkedEditReceipts.removeValue(forKey: item.id)
        return .saved
    }

    private func linkedEditRequest(
        item: UserFit,
        selectedOption: FitMatchLinkedClosetSizeEditOption,
        category: ClothingCategory,
        detailCategory: ClosetDetailCategory,
        categoryCode: String,
        detailCode: String,
        didExplicitlyChangeClassification: Bool,
        comparisonGroupCode: String,
        isReference: Bool
    ) throws -> FitMatchUpsertClosetItemRequest {
        let resultingAuthority = FitMatchClosetClassificationEditPolicy.resultingAuthority(
            current: item.classificationAuthorityProvenance,
            isSourced: FitMatchClosetClassificationEditPolicy.isSourced(item),
            isExplicitSet: FitMatchClosetClassificationEditPolicy.isExplicitSet(item),
            didExplicitlyChangeClassification: didExplicitlyChangeClassification,
            scope: .existingClosetItem
        )
        let familyCode = resolvedFamilyCode(
            for: item,
            category: category,
            detailCategory: detailCategory,
            requiresNewClassification: didExplicitlyChangeClassification
        )
        let lengthCode = resolvedLengthCode(
            for: item,
            category: category,
            detailCategory: detailCategory,
            requiresNewClassification: didExplicitlyChangeClassification
        )
        let override: FitMatchClosetClassificationOverride?
        if resultingAuthority == .userExplicit {
            guard let familyCode else {
                throw FitMatchClosetAuthorityError.unavailableClassification
            }
            override = FitMatchClosetClassificationOverride(
                audienceCode: item.resolvedGenderCode,
                categoryCode: categoryCode,
                detailCode: detailCode,
                familyCode: familyCode,
                lengthCode: lengthCode,
                bodyLengthCode: resolvedBodyLengthCode(for: item),
                reason: "user_confirmed_closet_classification",
                evidence: [
                    "classification_authority": FitMatchClassificationAuthorityProvenance
                        .userExplicit.rawValue,
                    "client_item_id": item.id.uuidString
                ]
            )
        } else {
            override = nil
        }

        let payload = FitMatchClosetItemPayload(
            productName: item.productName,
            brand: item.brandName.nilIfBlank,
            sizeName: selectedOption.productSize.name.fitMatchDisplaySizeName,
            genderCode: item.resolvedGenderCode,
            source: resolvedSourceCode(for: item),
            categoryCode: categoryCode,
            detailCode: detailCode,
            familyCode: familyCode,
            lengthCode: lengthCode,
            bodyLengthCode: resolvedBodyLengthCode(for: item),
            sourceCategoryPath: item.sourceCategoryPath ?? item.sourceProduct?.sourceCategoryPath,
            productURL: item.sourceProduct?.sourceURLString,
            imageURL: item.imageURLStringForDisplay,
            // The vNext transport omits product-linked measurements, but keep
            // this request boundary empty as well so stale M facts cannot be
            // mistaken for selected L facts by a future adapter change.
            measurements: [:],
            measurementRecords: [],
            fitMemo: item.fitMemo,
            fitPreferenceCode: item.fitPreference.databaseCode,
            satisfaction: item.satisfaction,
            isReference: isReference,
            classificationVersion: item.canonicalPolicyVersion,
            clientSnapshot: [
                "local_model": "UserFit",
                "local_schema": "1",
                "classification_authority": resultingAuthority.rawValue
            ],
            clientCreatedAt: encodeDate(item.createdAt),
            clientUpdatedAt: encodeDate(Date())
        )
        return FitMatchUpsertClosetItemRequest(
            clientItemID: item.id,
            item: payload,
            productID: selectedOption.identity.productID,
            productVariantID: selectedOption.identity.productVariantID,
            productSizeID: selectedOption.identity.productSizeID,
            override: override,
            comparisonGroupCode: comparisonGroupCode
        )
    }

    private func possibleServerReferenceConflicts(
        in records: [FitMatchClosetItemRecord],
        excluding clientItemID: UUID,
        request: FitMatchUpsertClosetItemRequest
    ) -> Set<UUID> {
        let targetAudience = FitMatchCanonicalAudience.code(
            from: request.item.genderCode
        )
        return Set(records.compactMap { record in
            guard record.clientItemID != clientItemID,
                  record.isReference,
                  FitMatchCanonicalAudience.code(from: record.genderCode)
                    == targetAudience else {
                return nil
            }
            if let groupCode = request.comparisonGroupCode {
                guard record.comparisonGroupCode == groupCode else { return nil }
            } else {
                guard record.categoryCode == request.item.categoryCode,
                      record.detailCode == request.item.detailCode else { return nil }
            }
            // This is intentionally conservative: the existing product
            // policy and the server tuple both agree that a same audience /
            // category / garment detail could replace a reference. Asking
            // first is safer than allowing update/set to clear it silently.
            return record.clientItemID
        })
    }

    /// Preserve the app's existing reference policy as an additional consent
    /// signal. The subsequent list receipt remains the authority for which
    /// rows the server actually changed; this local scan merely prevents a
    /// visibly represented reference from being released without consent.
    private func possibleLocalReferenceConflicts(
        excluding clientItemID: UUID,
        request: FitMatchUpsertClosetItemRequest,
        modelContext: ModelContext
    ) throws -> Set<UUID> {
        let targetAudience = FitMatchCanonicalAudience.code(
            from: request.item.genderCode
        )
        return Set(try modelContext.fetch(FetchDescriptor<UserFit>()).compactMap { local in
            guard local.id != clientItemID,
                  local.isActiveClosetItem,
                  local.isRepresentative,
                  FitMatchCanonicalAudience.code(from: local.resolvedGenderCode)
                    == targetAudience else {
                return nil
            }
            if let groupCode = request.comparisonGroupCode {
                guard local.comparisonGroup?.rawValue == groupCode else { return nil }
            } else {
                guard local.resolvedCategoryCode == request.item.categoryCode,
                      local.resolvedDetailCategoryCode == request.item.detailCode else { return nil }
            }
            return local.id
        })
    }

    private func projectAuthoritativeLinkedEdit(
        _ record: FitMatchClosetItemRecord,
        allRecords: [FitMatchClosetItemRecord],
        receipt: LinkedEditAcceptedReceipt,
        to item: UserFit,
        modelContext: ModelContext
    ) throws {
        guard item.id == receipt.request.clientItemID,
              record.clientItemID == receipt.request.clientItemID,
              record.closetItemID == receipt.closetItemID,
              record.productID == receipt.request.productID,
              record.variantID == receipt.request.productVariantID,
              record.productSizeID == receipt.request.productSizeID else {
            throw AuthoritativeRegistrationProjectionError.receiptMismatch
        }

        try apply(record, to: item, modelContext: modelContext)
        // set_closet_reference may have atomically released another local
        // reference. Apply only the candidate rows established in the
        // preflight, not arbitrary unrelated unsaved Closet edits.
        for clientItemID in receipt.possibleReplacedReferenceClientIDs {
            guard let remoteRecord = allRecords.first(where: {
                $0.clientItemID == clientItemID
            }) else {
                continue
            }
            let localMatches = try modelContext.fetch(
                FetchDescriptor<UserFit>(predicate: #Predicate { $0.id == clientItemID })
            )
            guard localMatches.count <= 1 else {
                throw AuthoritativeRegistrationProjectionError.duplicateLocalClientItemID
            }
            if let localReference = localMatches.first {
                try apply(remoteRecord, to: localReference, modelContext: modelContext)
            }
        }
        // No broad rollback on failure: this ModelContext can carry pending
        // edits from other screens. A failed save leaves the exact accepted
        // receipt available for a read-back-only retry.
        try modelContext.save()
    }

    private func linkedEditErrorMessage(for error: Error) -> String {
        if let payloadError = error as? FitMatchClosetPayloadContractError {
            return payloadError.errorDescription
                ?? "입력한 분류 또는 실측 정보를 서버에 저장할 수 없습니다. 입력한 내용은 유지됩니다."
        }
        let text = error.localizedDescription.lowercased()
        if text.contains("usable canonical measurement") {
            return "선택한 사이즈는 실측 정보가 없어 내 옷장에 등록할 수 없습니다."
        }
        return "서버에 수정 내용을 저장하지 못했습니다. 입력한 내용은 유지됩니다. 다시 시도해 주세요."
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
                    // A local M → L edit has an exact, user-scoped journal.
                    // Do not let the first stale list response put old M back
                    // into the local item before the update request is sent.
                    let pendingEdit = validPendingSizeEdit(
                        for: localItem,
                        userID: userID
                    )
                    let remoteIsBehindPendingSizeEdit = pendingEdit.map {
                        !$0.matchesServer(
                            productID: remoteItem.productID,
                            variantID: remoteItem.variantID,
                            productSizeID: remoteItem.productSizeID
                        )
                    } ?? false
                    if !remoteIsBehindPendingSizeEdit {
                        try apply(remoteItem, to: localItem, modelContext: modelContext)
                    }
                    if remoteItem.classificationStatus == "confirmed",
                       remoteItem.classificationSource == "manual_override",
                       !remoteIsBehindPendingSizeEdit {
                        // The normal personal-tuple preservation path may skip
                        // a redundant update. A verified M → L intent is not
                        // redundant: keep flowing into makeUpsertRequest so
                        // its exact L product_size_id reaches the server.
                        continue
                    }
                }

                do {
                    let request = try await makeUpsertRequest(for: localItem, userID: userID)
                    guard isCurrentSyncUser(userID) else { return }
                    if let existing = remoteItemsByClientID[localItem.id] {
                        _ = try await remote.updateClosetItem(
                            request,
                            closetItemID: existing.closetItemID
                        )
                        guard isCurrentSyncUser(userID) else { return }
                    } else {
                        _ = try await remote.upsertClosetItem(request)
                        guard isCurrentSyncUser(userID) else { return }
                    }
                    // vNext upsert/update carries a nested
                    // `closet_classification_override` atomically. Generic
                    // sync must never issue a second override mutation or
                    // clear a personal tuple merely because this request did
                    // not synthesize one. Dedicated explicit-edit flows keep
                    // their own server mutation call sites.
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
            let pendingSizeEditClientIDs = Set(currentLocalItems.compactMap { item in
                validPendingSizeEdit(for: item, userID: userID) == nil ? nil : item.id
            })
            var acknowledgedSizeEdits: [(clientItemID: UUID, token: UUID)] = []
            var hasUnacknowledgedSizeEdit = !pendingSizeEditClientIDs.isSubset(
                of: Set(authoritative.items.map(\.clientItemID))
            )
            for remoteItem in authoritative.items {
                guard isCurrentSyncUser(userID) else { return }
                if let localItem = currentByID[remoteItem.clientItemID] {
                    let pendingEdit = validPendingSizeEdit(
                        for: localItem,
                        userID: userID
                    )
                    if let pendingEdit,
                       !pendingEdit.matchesServer(
                        productID: remoteItem.productID,
                        variantID: remoteItem.variantID,
                        productSizeID: remoteItem.productSizeID
                       ) {
                        // The update receipt has not reached the authoritative
                        // read-back yet. Preserve the local exact choice and
                        // leave the journal for the next sync pass. Mark this
                        // pass pending so a stale list receipt is never
                        // reported as a fully reconciled M → L edit.
                        hasUnacknowledgedSizeEdit = true
                        continue
                    }
                    if failedAutomaticAuthorityValidationIDs.contains(remoteItem.clientItemID),
                       remoteItem.classificationSource != "manual_override" {
                        // The list snapshot can still point at stale v3 current
                        // history. Do not let it undo the fail-closed state set
                        // by a failed active-v4 resolve in this same pass.
                        continue
                    }
                    try apply(remoteItem, to: localItem, modelContext: modelContext)
                    if let pendingEdit {
                        acknowledgedSizeEdits.append((remoteItem.clientItemID, pendingEdit.token))
                    }
                } else {
                    let localItem = try makeLocalItem(from: remoteItem, modelContext: modelContext)
                    modelContext.insert(localItem)
                }
            }
            try modelContext.save()
            guard isCurrentSyncUser(userID) else { return }
            for acknowledgement in acknowledgedSizeEdits {
                FitMatchLinkedSizeEditIntentStore.remove(
                    userID: userID,
                    clientItemID: acknowledgement.clientItemID,
                    defaults: defaults,
                    onlyIfTokenMatches: acknowledgement.token
                )
            }

            if failedUpsert || hasUnacknowledgedSizeEdit {
                state = .pendingRetry
                lastErrorMessage = hasUnacknowledgedSizeEdit
                    ? "변경한 사이즈의 서버 확인을 기다리고 있습니다. 자동으로 다시 시도합니다."
                    : "일부 옷장 변경사항을 서버에 저장하지 못했습니다. 자동으로 다시 시도합니다."
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
            if let storedOwner {
                FitMatchLinkedSizeEditIntentStore.purge(userID: storedOwner, defaults: defaults)
            }
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
            acceptedLinkedEditReceipts.removeValue(forKey: clientItemID)
            FitMatchLinkedSizeEditIntentStore.remove(
                userID: userID,
                clientItemID: clientItemID,
                defaults: defaults
            )
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

        let existingRemoteItem = remoteItemsByClientID[item.id]
        var productID = existingRemoteItem?.productID
        var productVariantID = existingRemoteItem?.variantID
        var productSizeID = existingRemoteItem?.productSizeID

        if let edit = validPendingSizeEdit(for: item, userID: userID) {
            guard let existingRemoteItem,
                  existingRemoteItem.productID == edit.productID,
                  existingRemoteItem.variantID == edit.variantID else {
                throw FitMatchSupabaseProductResolverError.vnextIdentityRequired
            }
            productID = edit.productID
            productVariantID = edit.variantID
            productSizeID = edit.productSizeID
        }

        if let existingRemoteItem {
            // A row returned by listClosetItems owns its product/variant/size
            // relationship. Re-resolving an M or a colour label here can bind
            // this client_item_id to a different variant, so the exact remote
            // IDs are retained even while we refresh classification authority.
            if item.sourceProduct != nil, existingRemoteItem.productID == nil {
                // This is neither a manual row nor an exact product-linked
                // snapshot. Do not repair it by guessing from labels.
                throw FitMatchSupabaseProductResolverError.vnextIdentityRequired
            }
            if existingRemoteItem.productID != nil,
               (productVariantID == nil || productSizeID == nil) {
                throw FitMatchSupabaseProductResolverError.vnextIdentityRequired
            }

            if existingRemoteItem.classificationStatus == "confirmed",
               existingRemoteItem.classificationSource == "manual_override" {
                // The list adapter deliberately normalizes the production
                // USER_EXPLICIT and USER_EDITED strings to manual_override.
                // Both preserve local personal Closet authority.
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
                    // Intentionally do not replace productID/productVariantID/
                    // productSizeID with a label-derived runtime lookup.
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
            } else {
                switch existingRemoteItem.classificationStatus {
                case "review_required", "unclassified", "not_comparable":
                    try applyRemoteAuthority(existingRemoteItem, to: item)
                default:
                    // An automatic remote snapshot can point at pre-v4 current
                    // history. Without source facts it cannot prove active-
                    // runtime authority, so retain fail-closed behavior.
                    item.markClassificationAuthority(
                        .serverUnavailable,
                        sourceIdentity: existingRemoteItem.classificationSource
                    )
                    throw FitMatchClosetAuthorityError.unavailableClassification
                }
            }
        } else if let product = item.sourceProduct,
                  let request = product.fitMatchDatabaseResolutionRequest() {
            // Bounded recovery for a legacy local-only sourced row. This is the
            // sole remaining call site for label/color matching because no
            // client_item_id remote row exists from which exact IDs can be
            // recovered. New server-first link registrations never enter it.
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
                guard let identity = uniqueRuntimeSizeIdentity(
                    in: authority.runtime,
                    matching: item.sizeName,
                    colorName: product.checkedColorName
                ) else {
                    throw FitMatchSupabaseProductResolverError.vnextIdentityRequired
                }
                productVariantID = identity.variantID
                productSizeID = identity.sizeID
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

    /// Returns only a journal that still describes the current local edit.
    /// Stale intent must never override a later local selection, and the
    /// account namespace is part of the proof boundary.
    private func validPendingSizeEdit(
        for item: UserFit,
        userID: UUID
    ) -> FitMatchLinkedSizeEditIntent? {
        guard let intent = FitMatchLinkedSizeEditIntentStore.intent(
            userID: userID,
            clientItemID: item.id,
            defaults: defaults
        ) else {
            return nil
        }
        guard intent.userID == userID,
              intent.clientItemID == item.id,
              item.sourceProductSize?.id == intent.selectedDisplaySizeID,
              item.updatedAt >= intent.localUpdatedAt else {
            // A later local edit has superseded this journal. Removing only
            // this account/item key cannot affect any other user's retry.
            FitMatchLinkedSizeEditIntentStore.remove(
                userID: userID,
                clientItemID: item.id,
                defaults: defaults,
                onlyIfTokenMatches: intent.token
            )
            return nil
        }
        return intent
    }

    /// Converts the persisted local record set into the single shared
    /// upsert/update payload.  Keeping this internal lets regression tests
    /// exercise the same manual-registration serialization path without a
    /// transport mock or a second test-only mapper.
    func payload(for item: UserFit) -> FitMatchClosetItemPayload {
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
            imageURL: item.imageURLStringForDisplay,
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
        item.imageURLStringSnapshot = record.imageURL
        applyComparisonGroup(record, to: item)
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
        item.imageURLStringSnapshot = record.imageURL
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
        applyComparisonGroup(record, to: item)
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

    private func applyComparisonGroup(
        _ record: FitMatchClosetItemRecord,
        to item: UserFit
    ) {
        item.comparisonGroupCode = record.comparisonGroupCode
        item.comparisonGroupSource = record.comparisonGroupSource
        item.comparisonGroupPolicyVersion = record.comparisonGroupPolicyVersion
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
        record.measurementRecords.map { payload in
            let projection = FitMatchCanonicalMeasurementCode.projection(
                for: payload.measurementCode
            )
            let code = projection?.localCode ?? localMeasurementCode(payload.measurementCode)
            // Forward-compatible server facts are still Closet facts. Keep
            // the raw code with `.unknown` rather than discarding or guessing
            // a familiar measurement axis; generic sync and accepted
            // registration projection both use this single mapper.
            return GarmentMeasurementRecord(
                value: payload.value,
                unit: MeasurementUnit(rawValue: payload.unit) ?? .centimeter,
                unitRawValue: payload.unit,
                measurementCode: code,
                measurementCodeRawValue: payload.measurementCode,
                displayKind: projection?.displayKind
                    ?? MeasurementDisplayKind(rawValue: payload.displayKind)
                    ?? .unknown,
                methodSource: payload.methodSource,
                methodProfile: payload.methodProfile,
                inputSource: MeasurementInputSource(rawValue: payload.inputSource) ?? .importedSizeChart,
                standardVersion: payload.standardVersion,
                mappingVersion: payload.mappingVersion,
                rawCode: payload.rawCode ?? payload.measurementCode,
                rawLabel: payload.rawLabel.isEmpty
                    ? payload.measurementCode
                    : payload.rawLabel,
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
        /// Scalar legacy fields are a display convenience only.  Always select
        /// them by an explicit canonical-code priority, never by the order of
        /// records that happen to share a display axis.  Every original record
        /// is still retained independently in `measurementRecords`.
        func value(aliases: [String]) -> Double {
            for alias in aliases {
                let recordValues = record.measurementRecords
                    .filter {
                        $0.measurementCode == alias
                            && $0.value.isFinite
                            && $0.value > 0
                    }
                    .map(\.value)
                if !recordValues.isEmpty {
                    let distinct = Set(recordValues)
                    if distinct.count == 1 { return recordValues[0] }
                    // Conflicting duplicate server facts must not become an
                    // arbitrary scalar based on response array order.
                    continue
                }
                if let fallback = record.measurements[alias],
                   fallback.isFinite,
                   fallback > 0 {
                    return fallback
                }
            }
            return 0
        }
        return GarmentMeasurements(
            shoulder: value(aliases: ["shoulder_width", "shoulder_width_seam_to_seam"]),
            chest: value(aliases: ["chest_width", "chest_width_pit_to_pit"]),
            totalLength: value(aliases: [
                "total_length", "back_length", "outseam", "body_length",
                "body_length_back_neck_to_hem", "pants_outseam"
            ]),
            sleeveLength: value(aliases: ["sleeve_length", "sleeve_shoulder_seam_to_cuff"]),
            waist: value(aliases: ["waist_width", "waist_width_edge_to_edge"]),
            hip: value(aliases: ["hip_width", "hip_width_at_widest"]),
            thigh: value(aliases: ["thigh_width", "thigh_width_crotch_to_outer"]),
            rise: value(aliases: ["front_rise", "rise", "rise_crotch_to_waist_front"]),
            hem: value(aliases: ["hem_width", "hem_width_edge_to_edge"]),
            footLength: value(aliases: ["foot_length", "foot_length_heel_to_toe"]),
            underBust: value(aliases: ["under_bust_width", "under_bust_width_edge_to_edge"])
        )
    }

    private func localMeasurementCode(_ code: String) -> MeasurementCode {
        FitMatchCanonicalMeasurementCode.projection(for: code)?.localCode
            ?? MeasurementCode(rawValue: code)
            ?? .unknown
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

    private func resolvedFamilyCode(
        for item: UserFit,
        category: ClothingCategory,
        detailCategory: ClosetDetailCategory,
        requiresNewClassification: Bool
    ) -> String? {
        if !requiresNewClassification {
            return resolvedFamilyCode(for: item)
        }
        return ParsedClosetClassification.resolve(
            category: category,
            detailCategory: detailCategory,
            sourceDepths: [
                item.sourceCategoryDepth1,
                item.sourceCategoryDepth2,
                item.sourceCategoryDepth3,
                item.sourceCategoryDepth4
            ],
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

    private func resolvedLengthCode(
        for item: UserFit,
        category: ClothingCategory,
        detailCategory: ClosetDetailCategory,
        requiresNewClassification: Bool
    ) -> String? {
        if !requiresNewClassification {
            return resolvedLengthCode(for: item)
        }
        return ParsedClosetClassification.resolve(
            category: category,
            detailCategory: detailCategory,
            sourceDepths: [
                item.sourceCategoryDepth1,
                item.sourceCategoryDepth2,
                item.sourceCategoryDepth3,
                item.sourceCategoryDepth4
            ],
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
