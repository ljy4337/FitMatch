import Foundation

protocol FitMatchServerAuthorityRemoteServicing: Sendable {
    func resolve(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductResolutionResponse
    func submitProductObservation(_ request: FitMatchProductObservationRequest) async throws
        -> FitMatchProductObservationResponse
    func fetchProductRuntime(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductRuntimeResponse
    func classificationRecoveryOptions(productID: UUID) async throws
        -> VNextClassificationRecoveryContractDTO
    func setUserProductClassification(
        _ request: FitMatchSetUserProductClassificationRequest
    ) async throws -> VNextUserClassificationMutationDTO
    func clearUserProductClassification(
        _ request: FitMatchClearUserProductClassificationRequest
    ) async throws -> VNextUserClassificationMutationDTO
    func listClosetItems() async throws -> FitMatchClosetItemsResponse
    func findReferenceCandidates(targetProductID: UUID) async throws
        -> FitMatchReferenceCandidatesResponse
    func findReferenceCandidates(targetProductID: UUID, targetVariantID: UUID) async throws
        -> FitMatchReferenceCandidatesResponse
    func eligibleCandidateSizes(
        referenceClosetItemID: UUID,
        targetProductID: UUID,
        targetVariantID: UUID,
        manualExplicit: Bool
    ) async throws -> VNextEligibleCandidateSizesDTO
    func beginComparison(_ request: FitMatchBeginComparisonRequest) async throws
        -> FitMatchBeginComparisonResponse
    func completeVNextComparison(
        comparisonID: UUID,
        payload: VNextComparisonCompletionPayload
    ) async throws -> VNextCompleteComparisonDTO
}

extension FitMatchSupabaseDomainClient: FitMatchServerAuthorityRemoteServicing {}

extension FitMatchServerAuthorityRemoteServicing {
    func classificationRecoveryOptions(productID: UUID) async throws
        -> VNextClassificationRecoveryContractDTO {
        throw FitMatchServerAuthorityError.classificationRecoveryUnavailable
    }

    func setUserProductClassification(
        _ request: FitMatchSetUserProductClassificationRequest
    ) async throws -> VNextUserClassificationMutationDTO {
        throw FitMatchServerAuthorityError.classificationRecoveryUnavailable
    }

    func clearUserProductClassification(
        _ request: FitMatchClearUserProductClassificationRequest
    ) async throws -> VNextUserClassificationMutationDTO {
        throw FitMatchServerAuthorityError.classificationRecoveryUnavailable
    }

    func findReferenceCandidates(targetProductID: UUID, targetVariantID: UUID) async throws
        -> FitMatchReferenceCandidatesResponse {
        try await findReferenceCandidates(targetProductID: targetProductID)
    }

    func eligibleCandidateSizes(
        referenceClosetItemID: UUID,
        targetProductID: UUID,
        targetVariantID: UUID,
        manualExplicit: Bool
    ) async throws -> VNextEligibleCandidateSizesDTO {
        throw FitMatchServerAuthorityError.comparisonBeginUnavailable
    }

    func beginComparison(_ request: FitMatchBeginComparisonRequest) async throws
        -> FitMatchBeginComparisonResponse {
        throw FitMatchServerAuthorityError.comparisonBeginUnavailable
    }

    func completeVNextComparison(
        comparisonID: UUID,
        payload: VNextComparisonCompletionPayload
    ) async throws -> VNextCompleteComparisonDTO {
        throw FitMatchServerAuthorityError.comparisonCompletionUnavailable
    }
}

nonisolated enum FitMatchServerProductAuthorityStatus: String, Equatable, Sendable {
    case confirmed
    case reviewRequired = "review_required"
    case notComparable = "not_comparable"
}

nonisolated struct FitMatchServerProductAuthority: Equatable, Sendable {
    let status: FitMatchServerProductAuthorityStatus
    let productID: UUID
    let classification: FitMatchDatabaseClassification
    let runtime: FitMatchProductRuntimeResponse

    var comparisonReady: Bool {
        status == .confirmed && runtime.comparisonReady
    }

    /// Runtime readiness is independent from classification confirmation. The
    /// server owns both values, so callers must not infer readiness from local
    /// size or measurement counts.
    var comparisonReadiness: FitMatchServerComparisonReadiness {
        FitMatchServerComparisonReadiness(
            runtimeState: runtime.runtimeState,
            comparisonReady: comparisonReady
        )
    }
}

nonisolated enum FitMatchServerComparisonReadiness: Equatable, Sendable {
    case ready
    case sizesRequired
    case measurementsRequired
    case unavailable(String)

    init(runtimeState: String, comparisonReady: Bool) {
        if comparisonReady && runtimeState == "ready" {
            self = .ready
            return
        }
        switch runtimeState {
        case "sizes_required": self = .sizesRequired
        case "measurements_required": self = .measurementsRequired
        default: self = .unavailable(runtimeState)
        }
    }

    var isReady: Bool {
        self == .ready
    }

    var userMessage: String {
        switch self {
        case .ready:
            return ""
        case .sizesRequired:
            return "상품 사이즈표를 보완한 뒤 비교해 주세요."
        case .measurementsRequired:
            return "상품 실측 정보를 보완한 뒤 비교해 주세요."
        case .unavailable:
            return "서버에서 이 상품의 비교 준비 상태를 확인하지 못했습니다."
        }
    }
}

nonisolated enum FitMatchServerReferenceAuthority: String, Equatable, Sendable {
    case serverConfirmed = "server_confirmed"
    case userExplicit = "user_explicit"
}

nonisolated enum FitMatchServerReferenceDecision: String, Equatable, Sendable {
    case automatic
    case manualSelection = "manual_selection"
    case measurementsRequired = "measurements_required"
    case blocked
}

/// `fitmatch_vnext_find_reference_candidates` is the source of truth for
/// reference selection. These values deliberately represent the server's
/// typed status/decision fields rather than local Closet preferences.
nonisolated enum FitMatchServerReferenceSelectionStatus: Equatable, Sendable {
    case ready
    case noReferenceCandidate
    case automatic
    case manualSelection
    case measurementsRequired
}

nonisolated struct FitMatchServerReferenceSelectionCandidate: Equatable, Sendable {
    let clientItemID: UUID
    let closetItemID: UUID
    let decision: FitMatchServerReferenceDecision
    let allowed: Bool
    let reasonCode: String?
    let reason: String?
    let commonMeasurementCount: Int?

    var isSelectable: Bool {
        allowed && (decision == .automatic || decision == .manualSelection)
    }
}

nonisolated struct FitMatchServerReferenceSelectionPlan: Equatable, Sendable {
    let target: FitMatchServerProductAuthority
    let status: FitMatchServerReferenceSelectionStatus
    /// Preserves the order returned by the vNext candidate RPC.
    let candidates: [FitMatchServerReferenceSelectionCandidate]
    let blockedCandidates: [FitMatchServerReferenceSelectionCandidate]

    var automaticCandidates: [FitMatchServerReferenceSelectionCandidate] {
        candidates.filter { $0.allowed && $0.decision == .automatic }
    }

    var manualCandidates: [FitMatchServerReferenceSelectionCandidate] {
        candidates.filter { $0.allowed && $0.decision == .manualSelection }
    }

    var measurementRequiredCandidates: [FitMatchServerReferenceSelectionCandidate] {
        candidates.filter { $0.decision == .measurementsRequired }
    }

    var allBlockedCandidates: [FitMatchServerReferenceSelectionCandidate] {
        blockedCandidates + candidates.filter { $0.decision == .blocked }
    }
}

/// Stable server reason codes are translated here, not inferred from an
/// English/Korean explanation string.  The unknown case keeps old servers and
/// partial rollouts fail-closed without inventing local comparison authority.
nonisolated enum FitMatchComparisonBlockReason: String, Equatable, Sendable {
    case classificationRequired = "CLASSIFICATION_REQUIRED"
    case noAutomaticReference = "NO_AUTOMATIC_REFERENCE"
    case incompatibleBodyRegion = "INCOMPATIBLE_BODY_REGION"
    case noCommonMeasurements = "NO_COMMON_MEASUREMENTS"
    case structurallyNotComparable = "STRUCTURALLY_NOT_COMPARABLE"
    case invalidAuthority = "INVALID_AUTHORITY"
    case staleReference = "STALE_REFERENCE"
    case noEligibleTargetSize = "NO_ELIGIBLE_TARGET_SIZE"
    case serverUnavailable = "SERVER_UNAVAILABLE"
    case incompatibleAudience = "INCOMPATIBLE_AUDIENCE"
    case designAxisDifference = "DESIGN_AXIS_DIFFERENCE"
    case userSelectedReference = "USER_SELECTED_REFERENCE"
    case automaticMatch = "AUTOMATIC_MATCH"
    case unknown

    init(code: String?) {
        guard let code else {
            self = .unknown
            return
        }
        self = Self(rawValue: code) ?? .unknown
    }

    var userMessage: String {
        switch self {
        case .classificationRequired:
            return "상품 분류를 다시 확인한 뒤 비교해 주세요."
        case .noAutomaticReference:
            return "자동으로 선택할 기준 옷이 없어 직접 선택해 주세요."
        case .incompatibleBodyRegion:
            return "이 두 옷은 측정하는 신체 부위가 달라 비교하기 어려워요."
        case .noCommonMeasurements:
            return "이 두 옷은 함께 비교할 수 있는 실측 항목이 없어요."
        case .structurallyNotComparable:
            return "여러 종류의 옷이 함께 구성된 상품은 비교할 수 없어요."
        case .invalidAuthority:
            return "기준 옷 또는 상품 정보를 다시 확인해 주세요."
        case .staleReference:
            return "기준 옷 정보가 바뀌었어요. 최신 정보로 다시 확인해 주세요."
        case .noEligibleTargetSize:
            return "비교에 사용할 상품 사이즈 실측이 없어요."
        case .serverUnavailable:
            return "서버 비교 가능 여부를 확인하지 못했습니다. 다시 시도해 주세요."
        case .incompatibleAudience:
            return "대상 사용자 범위가 달라 비교하기 어려워요."
        case .designAxisDifference:
            return "디자인 축이 달라 이 조합은 비교할 수 없어요."
        case .userSelectedReference, .automaticMatch, .unknown:
            return "서버 비교 정책상 선택한 옷과 비교할 수 없습니다."
        }
    }
}

nonisolated struct FitMatchServerReferenceAuthorization: Equatable, Sendable {
    let decision: FitMatchServerReferenceDecision
    let reasonCode: String?
    let reason: String?
    let target: FitMatchServerProductAuthority
    let reference: FitMatchClosetItemRecord?
    let referenceAuthority: FitMatchServerReferenceAuthority?
    let candidate: FitMatchReferenceCandidate?
    let candidateState: String?
    let targetVariantID: UUID?
    let authorizedCandidateSizeIDs: [UUID]

    init(
        decision: FitMatchServerReferenceDecision,
        reasonCode: String? = nil,
        reason: String?,
        target: FitMatchServerProductAuthority,
        reference: FitMatchClosetItemRecord?,
        referenceAuthority: FitMatchServerReferenceAuthority?,
        candidate: FitMatchReferenceCandidate?,
        candidateState: String?,
        targetVariantID: UUID? = nil,
        authorizedCandidateSizeIDs: [UUID] = []
    ) {
        self.decision = decision
        self.reasonCode = reasonCode
        self.reason = reason
        self.target = target
        self.reference = reference
        self.referenceAuthority = referenceAuthority
        self.candidate = candidate
        self.candidateState = candidateState
        self.targetVariantID = targetVariantID
        self.authorizedCandidateSizeIDs = authorizedCandidateSizeIDs
    }

    nonisolated var isAllowed: Bool {
        decision == .automatic || decision == .manualSelection
    }

    nonisolated var allowsExtendedComparison: Bool {
        decision == .manualSelection
    }

    nonisolated var blockReason: FitMatchComparisonBlockReason {
        FitMatchComparisonBlockReason(code: reasonCode)
    }
}

/// A server-created comparison run is the final precondition for invoking the
/// local measurement engine. The history ID is allocated before scoring so the
/// existing post-save sync can idempotently reopen and complete this exact run.
nonisolated struct FitMatchServerComparisonPermit: Equatable, Sendable {
    let referenceAuthorization: FitMatchServerReferenceAuthorization
    let clientHistoryID: UUID
    let runID: UUID
    let compatibility: FitMatchDatabaseCompatibility
    let vnextBegin: VNextBeginComparisonDTO?

    nonisolated var isAllowed: Bool {
        referenceAuthorization.isAllowed && compatibility.allowed
    }
}

/// The exact local Closet state that will be handed to the measurement engine.
/// Server candidate authorization is rejected when this snapshot differs from
/// the freshly fetched remote Closet row, preventing a stale/local edit from
/// being scored against an older server-approved tuple or measurement payload.
nonisolated struct FitMatchLocalReferenceSnapshot: Equatable, Sendable {
    let productName: String
    let sizeName: String?
    let categoryCode: String
    let detailCode: String
    let familyCode: String?
    let lengthCode: String?
    let bodyLengthCode: String?
    let measurements: [String: Double]
}

nonisolated enum FitMatchServerAuthorityError: LocalizedError, Equatable, Sendable {
    case unsupportedCatalogState(String)
    case missingObservationForPromotion
    case observationIdentityMismatch
    case promotionRejected(String)
    case promotionResponseMalformed
    case promotedProductMismatch
    case runtimeResponseMalformed(String)
    case unknownClassificationStatus(String)
    case inconsistentRuntimeState(state: String, status: String)
    case classificationRecoveryUnavailable
    case invalidClassificationRecoveryContract(String)
    case classificationRecoveryRejected(String)
    case closetRuntimeUnavailable(String)
    case referenceItemNotFound
    case localReferenceProjectionMissing(UUID)
    case targetClassificationRequired
    case comparisonNotReady(String)
    case unknownCandidateState(String)
    case inconsistentCandidateState(state: String, reason: String)
    case comparisonBeginUnavailable
    case comparisonNotAuthorized
    case comparisonAuthorizationRejected(FitMatchComparisonBlockReason)
    case comparisonBeginRejected(String)
    case comparisonBeginMalformed(String)
    case comparisonCompletionUnavailable
    case comparisonCompletionRejected(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedCatalogState(let state):
            return "지원하지 않는 서버 상품 상태입니다: \(state)"
        case .missingObservationForPromotion:
            return "서버 분류 승격에 필요한 상품 관측 정보가 없습니다."
        case .observationIdentityMismatch:
            return "상품 관측 정보가 분류 요청과 일치하지 않습니다."
        case .promotionRejected(let status):
            return "서버 분류 승격이 완료되지 않았습니다: \(status)"
        case .promotionResponseMalformed:
            return "서버 분류 승격 응답이 올바르지 않습니다."
        case .promotedProductMismatch:
            return "승격된 서버 상품 식별자가 요청과 일치하지 않습니다."
        case .runtimeResponseMalformed(let reason):
            return "서버 상품 런타임 응답이 올바르지 않습니다: \(reason)"
        case .unknownClassificationStatus(let status):
            return "알 수 없는 서버 분류 상태입니다: \(status)"
        case .inconsistentRuntimeState(let state, let status):
            return "서버 런타임과 분류 상태가 일치하지 않습니다: \(state)/\(status)"
        case .classificationRecoveryUnavailable:
            return "서버 상품 분류 확인 기능을 사용할 수 없습니다."
        case .invalidClassificationRecoveryContract(let reason):
            return "서버 상품 분류 선택지가 올바르지 않습니다: \(reason)"
        case .classificationRecoveryRejected(let reason):
            return "상품 분류 선택을 저장하지 못했습니다: \(reason)"
        case .closetRuntimeUnavailable(let state):
            return "서버 옷장 상태를 사용할 수 없습니다: \(state)"
        case .referenceItemNotFound:
            return "서버 옷장에서 기준 의류를 찾지 못했습니다."
        case .localReferenceProjectionMissing:
            return "서버 기준 옷과 기기 옷장 정보가 동기화되지 않았습니다. 동기화한 뒤 다시 시도해 주세요."
        case .targetClassificationRequired:
            return "대상 상품의 서버 분류 승격이 필요합니다."
        case .comparisonNotReady(let state):
            return FitMatchServerComparisonReadiness(
                runtimeState: state,
                comparisonReady: false
            ).userMessage
        case .unknownCandidateState(let state):
            return "알 수 없는 서버 비교 후보 상태입니다: \(state)"
        case .inconsistentCandidateState(let state, let reason):
            return "서버 비교 후보 응답이 일관되지 않습니다: \(state)/\(reason)"
        case .comparisonBeginUnavailable:
            return "서버 비교 시작 API를 사용할 수 없습니다."
        case .comparisonNotAuthorized:
            return "서버에서 승인되지 않은 비교입니다."
        case .comparisonAuthorizationRejected(let reason):
            return reason.userMessage
        case .comparisonBeginRejected(let reason):
            return "서버 비교 시작이 차단되었습니다: \(reason)"
        case .comparisonBeginMalformed(let reason):
            return "서버 비교 시작 응답이 올바르지 않습니다: \(reason)"
        case .comparisonCompletionUnavailable:
            return "서버 비교 완료 API를 사용할 수 없습니다."
        case .comparisonCompletionRejected(let reason):
            return "서버가 비교 결과를 승인하지 않았습니다: \(reason)"
        }
    }
}

actor FitMatchServerAuthorityCoordinator {
    private let remote: any FitMatchServerAuthorityRemoteServicing

    @MainActor
    init() {
        remote = FitMatchSupabaseDomainClient.shared
    }

    init(remote: any FitMatchServerAuthorityRemoteServicing) {
        self.remote = remote
    }

    func classificationRecoveryOptions(
        productID: UUID
    ) async throws -> VNextClassificationRecoveryContractDTO {
        let contract = try await remote.classificationRecoveryOptions(
            productID: productID
        )
        guard contract.productID == productID,
              contract.globalStatus == "REVIEW_REQUIRED" else {
            throw FitMatchServerAuthorityError.invalidClassificationRecoveryContract(
                "product_or_global_status_mismatch"
            )
        }
        if contract.recoverability == .recoverable {
            guard contract.isSafelyRecoverable,
                  Set(contract.candidates.map(\.candidateFingerprint)).count
                    == contract.candidates.count,
                  Set(contract.candidates.map(\.candidateID)).count
                    == contract.candidates.count,
                  contract.candidates.allSatisfy({ candidate in
                      !candidate.candidateFingerprint.isEmpty
                          && candidate.candidateID
                             == candidate.candidateFingerprint
                          && !candidate.categoryCode.isEmpty
                          && !candidate.garmentTypeCode.isEmpty
                          && !candidate.comparisonPolicyCode.isEmpty
                  }) else {
                throw FitMatchServerAuthorityError.invalidClassificationRecoveryContract(
                    "unbounded_or_incomplete_candidate_set"
                )
            }
        } else if !contract.candidates.isEmpty {
            throw FitMatchServerAuthorityError.invalidClassificationRecoveryContract(
                "unrecoverable_contract_contains_candidates"
            )
        }
        return contract
    }

    func setUserProductClassification(
        contract: VNextClassificationRecoveryContractDTO,
        candidate: VNextClassificationRecoveryCandidateDTO,
        expectedRevision: Int,
        mutationID: UUID = UUID()
    ) async throws -> VNextUserClassificationMutationDTO {
        guard contract.isSafelyRecoverable,
              let candidateSetHash = contract.candidateSetHash,
              contract.candidates.contains(candidate) else {
            throw FitMatchServerAuthorityError.invalidClassificationRecoveryContract(
                "candidate_not_in_server_contract"
            )
        }
        let result = try await remote.setUserProductClassification(
            FitMatchSetUserProductClassificationRequest(
                productID: contract.productID,
                selectedCandidateFingerprint: candidate.candidateFingerprint,
                expectedCandidateSetHash: candidateSetHash,
                expectedProductInputFingerprint: contract.productInputFingerprint,
                expectedProductEvidenceFingerprint:
                    contract.productEvidenceFingerprint,
                mutationID: mutationID,
                expectedRevision: expectedRevision
            )
        )
        guard result.saved == true,
              result.effectiveClassification.productID == contract.productID,
              result.effectiveClassification.isPersonalComparisonAuthority,
              result.effectiveClassification.garmentTypeCode
                == candidate.garmentTypeCode,
              result.effectiveClassification.categoryCode
                == candidate.categoryCode,
              result.effectiveClassification.comparisonPolicyCode
                == candidate.comparisonPolicyCode,
              result.effectiveClassification.sleeveLengthCode
                == candidate.sleeveLengthCode,
              result.effectiveClassification.lowerLengthCode
                == candidate.lowerLengthCode,
              result.effectiveClassification.bodyLengthCode
                == candidate.bodyLengthCode else {
            throw FitMatchServerAuthorityError.classificationRecoveryRejected(
                "effective_authority_not_personal_confirmed"
            )
        }
        return result
    }

    func clearUserProductClassification(
        productID: UUID,
        expectedRevision: Int,
        mutationID: UUID = UUID()
    ) async throws -> VNextUserClassificationMutationDTO {
        let result = try await remote.clearUserProductClassification(
            FitMatchClearUserProductClassificationRequest(
                productID: productID,
                mutationID: mutationID,
                expectedRevision: expectedRevision
            )
        )
        guard result.cleared == true,
              result.effectiveClassification.productID == productID,
              !result.effectiveClassification.isPersonalComparisonAuthority else {
            throw FitMatchServerAuthorityError.classificationRecoveryRejected(
                "clear_did_not_remove_personal_authority"
            )
        }
        return result
    }

    func resolveProductAuthority(
        request: FitMatchProductResolutionRequest,
        observation: FitMatchProductObservationRequest?
    ) async throws -> FitMatchServerProductAuthority {
        let resolution = try await remote.resolve(request)
        _ = try classificationStatus(resolution.classification.status)

        let expectedProductID: UUID?
        var didPromote = false
        switch resolution.catalogState {
        case "current":
            guard let productID = resolution.productID else {
                throw FitMatchServerAuthorityError.runtimeResponseMalformed(
                    "current_catalog_missing_product_id"
                )
            }
            expectedProductID = productID
            if resolution.authorityPersisted != true {
                _ = try await promote(
                    request: request,
                    observation: observation,
                    expectedProductID: productID
                )
                didPromote = true
            }
        case "new", "changed":
            if resolution.catalogState == "changed", resolution.productID == nil {
                throw FitMatchServerAuthorityError.runtimeResponseMalformed(
                    "changed_catalog_missing_product_id"
                )
            }
            expectedProductID = try await promote(
                request: request,
                observation: observation,
                expectedProductID: resolution.productID
            )
            didPromote = true
        default:
            throw FitMatchServerAuthorityError.unsupportedCatalogState(
                resolution.catalogState
            )
        }

        var runtime = try await remote.fetchProductRuntime(request)
        if runtime.runtimeState == "classification_promotion_required" {
            guard !didPromote else {
                throw FitMatchServerAuthorityError.inconsistentRuntimeState(
                    state: runtime.runtimeState,
                    status: runtime.classification?.status ?? "missing"
                )
            }
            _ = try await promote(
                request: request,
                observation: observation,
                expectedProductID: expectedProductID
            )
            runtime = try await remote.fetchProductRuntime(request)
        }

        if !didPromote,
           observationCanImproveRuntime(
            observation,
            runtimeState: runtime.runtimeState
           ) {
            _ = try await promote(
                request: request,
                observation: observation,
                expectedProductID: expectedProductID
            )
            didPromote = true
            runtime = try await remote.fetchProductRuntime(request)
        }

        return try validatedAuthority(
            runtime,
            request: request,
            expectedProductID: expectedProductID
        )
    }

    func authorizeReferenceCandidate(
        referenceClientItemID: UUID,
        localReferenceSnapshot: FitMatchLocalReferenceSnapshot,
        targetRequest: FitMatchProductResolutionRequest,
        targetObservation: FitMatchProductObservationRequest?,
        referenceRequest: FitMatchProductResolutionRequest? = nil,
        referenceObservation: FitMatchProductObservationRequest? = nil
    ) async throws -> FitMatchServerReferenceAuthorization {
        var target = try await resolveProductAuthority(
            request: targetRequest,
            observation: targetObservation
        )

        if target.status == .confirmed,
           !target.comparisonReadiness.isReady {
            throw FitMatchServerAuthorityError.comparisonNotReady(
                target.runtime.runtimeState
            )
        }

        let resolvedReference: FitMatchServerProductAuthority?
        if let referenceRequest {
            resolvedReference = try await resolveProductAuthority(
                request: referenceRequest,
                observation: referenceObservation
            )
        } else {
            resolvedReference = nil
        }

        let closet = try await remote.listClosetItems()
        guard closet.state == "ready" else {
            throw FitMatchServerAuthorityError.closetRuntimeUnavailable(closet.state)
        }
        guard let reference = closet.items.first(where: {
            $0.clientItemID == referenceClientItemID
        }) else {
            throw FitMatchServerAuthorityError.referenceItemNotFound
        }

        guard target.status == .confirmed else {
            return blockedAuthorization(
                reason: target.status == .notComparable
                    ? "target_not_comparable"
                    : "target_review_required",
                reasonCode: target.status == .notComparable
                    ? FitMatchComparisonBlockReason.structurallyNotComparable.rawValue
                    : FitMatchComparisonBlockReason.classificationRequired.rawValue,
                target: target,
                reference: reference
            )
        }

        guard let referenceAuthority = referenceAuthority(
            for: reference,
            request: referenceRequest,
            resolvedAuthority: resolvedReference
        ) else {
            return blockedAuthorization(
                reason: reference.classificationStatus == "confirmed"
                    ? "reference_authority_unverified"
                    : "reference_classification_not_confirmed",
                reasonCode: FitMatchComparisonBlockReason.invalidAuthority.rawValue,
                target: target,
                reference: reference
            )
        }

        guard referenceMatchesLocalSnapshot(
            reference,
            snapshot: localReferenceSnapshot
        ) else {
            return blockedAuthorization(
                reason: "local_reference_snapshot_mismatch",
                reasonCode: FitMatchComparisonBlockReason.staleReference.rawValue,
                target: target,
                reference: reference,
                referenceAuthority: referenceAuthority
            )
        }

        let targetVariantID = target.runtime.vnext.flatMap { runtime -> UUID? in
            let observationVariant = targetObservation?.payload.variants.first?
                .externalVariantID
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let observationVariant, !observationVariant.isEmpty {
                return runtime.variants.first(where: {
                    $0.sourceVariantKey == observationVariant
                })?.id
            }
            return runtime.variants.count == 1 ? runtime.variants[0].id : nil
        }
        var candidates: FitMatchReferenceCandidatesResponse
        if let targetVariantID {
            candidates = try await remote.findReferenceCandidates(
                targetProductID: target.productID,
                targetVariantID: targetVariantID
            )
        } else {
            candidates = try await remote.findReferenceCandidates(
                targetProductID: target.productID
            )
        }
        if candidates.state == "target_classification_required" {
            target = try await resolveProductAuthority(
                request: targetRequest,
                observation: targetObservation
            )
            guard target.status == .confirmed else {
                return blockedAuthorization(
                    reason: "target_classification_not_confirmed_after_retry",
                    reasonCode: FitMatchComparisonBlockReason.classificationRequired.rawValue,
                    target: target,
                    reference: reference,
                    referenceAuthority: referenceAuthority,
                    candidateState: candidates.state
                )
            }
            if let targetVariantID {
                candidates = try await remote.findReferenceCandidates(
                    targetProductID: target.productID,
                    targetVariantID: targetVariantID
                )
            } else {
                candidates = try await remote.findReferenceCandidates(
                    targetProductID: target.productID
                )
            }
            if candidates.state == "target_classification_required" {
                throw FitMatchServerAuthorityError.targetClassificationRequired
            }
        }

        let knownStates: Set<String> = candidates.vnext == nil ? [
            "automatic",
            "manual_selection",
            "measurements_required",
            "no_compatible_garment"
        ] : [
            "automatic",
            "manual_selection",
            "measurements_required",
            "no_compatible_garment",
            "READY",
            "NO_REFERENCE_CANDIDATE"
        ]
        guard knownStates.contains(candidates.state) else {
            throw FitMatchServerAuthorityError.unknownCandidateState(candidates.state)
        }
        if candidates.vnext == nil {
            try validateCandidateResponse(candidates)
        }

        let vnextCandidate = candidates.vnext?.candidates.first(where: {
            $0.closetItemID == reference.closetItemID
        })
        let vnextBlockedCandidate = candidates.vnext?.blocked.first(where: {
            $0.closetItemID == reference.closetItemID
        })
        guard let candidate = candidates.candidates.first(where: {
            $0.closetItemID == reference.closetItemID
        }) else {
            if let vnextBlockedCandidate {
                return blockedAuthorization(
                    reason: vnextBlockedCandidate.reason
                        ?? "comparison_blocked",
                    reasonCode: vnextBlockedCandidate.reasonCode,
                    target: target,
                    reference: reference,
                    referenceAuthority: referenceAuthority,
                    candidateState: candidates.state
                )
            }
            return blockedAuthorization(
                reason: "reference_not_authorized_by_server_evaluator",
                reasonCode: FitMatchComparisonBlockReason.invalidAuthority.rawValue,
                target: target,
                reference: reference,
                referenceAuthority: referenceAuthority,
                candidateState: candidates.state
            )
        }

        if let vnextCandidate {
            switch vnextCandidate.decision {
            case "AUTOMATIC" where vnextCandidate.allowed:
                return FitMatchServerReferenceAuthorization(
                    decision: .automatic,
                    reasonCode: vnextCandidate.reasonCode,
                    reason: vnextCandidate.reason,
                    target: target,
                    reference: reference,
                    referenceAuthority: referenceAuthority,
                    candidate: candidate,
                    candidateState: candidates.state,
                    targetVariantID: targetVariantID,
                    authorizedCandidateSizeIDs: vnextCandidate.eligibleProductSizeIDs
                )
            case "MANUAL_EXTENDED" where vnextCandidate.allowed:
                return FitMatchServerReferenceAuthorization(
                    decision: .manualSelection,
                    reasonCode: vnextCandidate.reasonCode,
                    reason: vnextCandidate.reason,
                    target: target,
                    reference: reference,
                    referenceAuthority: referenceAuthority,
                    candidate: candidate,
                    candidateState: candidates.state,
                    targetVariantID: targetVariantID,
                    authorizedCandidateSizeIDs: vnextCandidate.eligibleProductSizeIDs
                )
            case "MEASUREMENTS_REQUIRED":
                return FitMatchServerReferenceAuthorization(
                    decision: .measurementsRequired,
                    reasonCode: vnextCandidate.reasonCode,
                    reason: vnextCandidate.reason,
                    target: target,
                    reference: reference,
                    referenceAuthority: referenceAuthority,
                    candidate: candidate,
                    candidateState: candidates.state,
                    targetVariantID: targetVariantID,
                    authorizedCandidateSizeIDs: []
                )
            default:
                return blockedAuthorization(
                    reason: vnextCandidate.reason ?? "comparison_blocked",
                    reasonCode: vnextCandidate.reasonCode,
                    target: target,
                    reference: reference,
                    referenceAuthority: referenceAuthority,
                    candidate: candidate,
                    candidateState: candidates.state
                )
            }
        }

        if candidate.automaticReady && candidate.automaticCompatibility.allowed {
            return FitMatchServerReferenceAuthorization(
                decision: .automatic,
                reason: nil,
                target: target,
                reference: reference,
                referenceAuthority: referenceAuthority,
                candidate: candidate,
                candidateState: candidates.state,
                targetVariantID: targetVariantID,
                authorizedCandidateSizeIDs: candidates.vnext?.candidates
                    .first(where: { $0.closetItemID == reference.closetItemID })?
                    .eligibleProductSizeIDs ?? []
            )
        }
        if candidate.manualReady && candidate.manualCompatibility.allowed {
            return FitMatchServerReferenceAuthorization(
                decision: .manualSelection,
                reason: nil,
                target: target,
                reference: reference,
                referenceAuthority: referenceAuthority,
                candidate: candidate,
                candidateState: candidates.state,
                targetVariantID: targetVariantID,
                authorizedCandidateSizeIDs: candidates.vnext?.candidates
                    .first(where: { $0.closetItemID == reference.closetItemID })?
                    .eligibleProductSizeIDs ?? []
            )
        }
        if candidate.automaticCompatibility.allowed
            || candidate.manualCompatibility.allowed {
            return FitMatchServerReferenceAuthorization(
                decision: .measurementsRequired,
                reason: "insufficient_common_measurements",
                target: target,
                reference: reference,
                referenceAuthority: referenceAuthority,
                candidate: candidate,
                candidateState: candidates.state,
                targetVariantID: targetVariantID,
                authorizedCandidateSizeIDs: []
            )
        }
        return blockedAuthorization(
            reason: candidate.manualCompatibility.reason
                ?? candidate.automaticCompatibility.reason
                ?? "comparison_blocked",
            target: target,
            reference: reference,
            referenceAuthority: referenceAuthority,
            candidate: candidate,
            candidateState: candidates.state
        )
    }

    /// Loads the complete server-issued reference decision. `localClientItemIDs`
    /// is an optional projection check: if a selectable server candidate is not
    /// present in the active local Closet cache, the flow fails closed instead
    /// of falling back to a different local representative item.
    func referenceSelectionPlan(
        targetRequest: FitMatchProductResolutionRequest,
        targetObservation: FitMatchProductObservationRequest?,
        localClientItemIDs: Set<UUID>? = nil
    ) async throws -> FitMatchServerReferenceSelectionPlan {
        let target = try await resolveProductAuthority(
            request: targetRequest,
            observation: targetObservation
        )
        guard target.status == .confirmed else {
            throw FitMatchServerAuthorityError.targetClassificationRequired
        }
        guard target.comparisonReadiness.isReady else {
            throw FitMatchServerAuthorityError.comparisonNotReady(
                target.runtime.runtimeState
            )
        }

        let closet = try await remote.listClosetItems()
        guard closet.state == "ready" else {
            throw FitMatchServerAuthorityError.closetRuntimeUnavailable(closet.state)
        }
        let clientIDByClosetID = Dictionary(
            uniqueKeysWithValues: closet.items.map {
                ($0.closetItemID, $0.clientItemID)
            }
        )
        let targetVariantID = targetVariantID(
            for: target,
            observation: targetObservation
        )
        let response = try await findReferenceCandidates(
            targetProductID: target.productID,
            targetVariantID: targetVariantID
        )
        guard response.state != "target_classification_required" else {
            throw FitMatchServerAuthorityError.targetClassificationRequired
        }

        let plan: FitMatchServerReferenceSelectionPlan
        if let vnext = response.vnext {
            let candidates = try vnext.candidates.map {
                try makeReferenceSelectionCandidate(
                    from: $0,
                    clientIDByClosetID: clientIDByClosetID
                )
            }
            let blocked = try vnext.blocked.map {
                try makeReferenceSelectionCandidate(
                    from: $0,
                    clientIDByClosetID: clientIDByClosetID
                )
            }
            plan = FitMatchServerReferenceSelectionPlan(
                target: target,
                status: try referenceSelectionStatus(vnext.status),
                candidates: candidates,
                blockedCandidates: blocked
            )
        } else {
            try validateCandidateResponse(response)
            let candidates = try response.candidates.map {
                try makeLegacyReferenceSelectionCandidate(
                    from: $0,
                    clientIDByClosetID: clientIDByClosetID
                )
            }
            plan = FitMatchServerReferenceSelectionPlan(
                target: target,
                status: try referenceSelectionStatus(response.state),
                candidates: candidates,
                blockedCandidates: []
            )
        }

        if let localClientItemIDs,
           let missing = (plan.automaticCandidates + plan.manualCandidates)
            .first(where: { !localClientItemIDs.contains($0.clientItemID) }) {
            throw FitMatchServerAuthorityError.localReferenceProjectionMissing(
                missing.clientItemID
            )
        }
        return plan
    }

    /// Returns only the server-ordered automatic references. The full plan is
    /// the canonical path; this compatibility API intentionally reuses it.
    func automaticReferenceClientItemIDs(
        targetRequest: FitMatchProductResolutionRequest,
        targetObservation: FitMatchProductObservationRequest?
    ) async throws -> [UUID] {
        let plan = try await referenceSelectionPlan(
            targetRequest: targetRequest,
            targetObservation: targetObservation
        )
        return plan.automaticCandidates.map(\.clientItemID)
    }

    private func targetVariantID(
        for target: FitMatchServerProductAuthority,
        observation: FitMatchProductObservationRequest?
    ) -> UUID? {
        target.runtime.vnext.flatMap { runtime -> UUID? in
            let observationVariant = observation?.payload.variants.first?
                .externalVariantID
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let observationVariant, !observationVariant.isEmpty {
                return runtime.variants.first(where: {
                    $0.sourceVariantKey == observationVariant
                })?.id
            }
            return runtime.variants.count == 1 ? runtime.variants[0].id : nil
        }
    }

    private func findReferenceCandidates(
        targetProductID: UUID,
        targetVariantID: UUID?
    ) async throws -> FitMatchReferenceCandidatesResponse {
        if let targetVariantID {
            return try await remote.findReferenceCandidates(
                targetProductID: targetProductID,
                targetVariantID: targetVariantID
            )
        }
        return try await remote.findReferenceCandidates(
            targetProductID: targetProductID
        )
    }

    private func referenceSelectionStatus(
        _ status: String
    ) throws -> FitMatchServerReferenceSelectionStatus {
        switch status {
        case "READY": return .ready
        case "NO_REFERENCE_CANDIDATE", "BLOCKED", "no_compatible_garment":
            return .noReferenceCandidate
        case "automatic": return .automatic
        case "manual_selection": return .manualSelection
        case "measurements_required": return .measurementsRequired
        default:
            throw FitMatchServerAuthorityError.unknownCandidateState(status)
        }
    }

    private func referenceDecision(
        _ decision: String
    ) throws -> FitMatchServerReferenceDecision {
        switch decision {
        case "AUTOMATIC": return .automatic
        case "MANUAL_EXTENDED": return .manualSelection
        case "MEASUREMENTS_REQUIRED": return .measurementsRequired
        case "BLOCKED": return .blocked
        default:
            throw FitMatchServerAuthorityError.unknownCandidateState(decision)
        }
    }

    private func makeReferenceSelectionCandidate(
        from candidate: VNextReferenceCandidateDTO,
        clientIDByClosetID: [UUID: UUID]
    ) throws -> FitMatchServerReferenceSelectionCandidate {
        guard let clientItemID = clientIDByClosetID[candidate.closetItemID] else {
            throw FitMatchServerAuthorityError.referenceItemNotFound
        }
        return FitMatchServerReferenceSelectionCandidate(
            clientItemID: clientItemID,
            closetItemID: candidate.closetItemID,
            decision: try referenceDecision(candidate.decision),
            allowed: candidate.allowed,
            reasonCode: candidate.reasonCode,
            reason: candidate.reason,
            commonMeasurementCount: candidate.commonMeasurementCount
        )
    }

    private func makeLegacyReferenceSelectionCandidate(
        from candidate: FitMatchReferenceCandidate,
        clientIDByClosetID: [UUID: UUID]
    ) throws -> FitMatchServerReferenceSelectionCandidate {
        guard let clientItemID = clientIDByClosetID[candidate.closetItemID] else {
            throw FitMatchServerAuthorityError.referenceItemNotFound
        }
        let decision: FitMatchServerReferenceDecision
        let allowed: Bool
        let reason: String?
        if candidate.automaticReady && candidate.automaticCompatibility.allowed {
            decision = .automatic
            allowed = true
            reason = candidate.automaticCompatibility.reason
        } else if candidate.manualReady && candidate.manualCompatibility.allowed {
            decision = .manualSelection
            allowed = true
            reason = candidate.manualCompatibility.reason
        } else if candidate.automaticCompatibility.allowed
            || candidate.manualCompatibility.allowed {
            decision = .measurementsRequired
            allowed = false
            reason = candidate.manualCompatibility.reason
                ?? candidate.automaticCompatibility.reason
        } else {
            decision = .blocked
            allowed = false
            reason = candidate.manualCompatibility.reason
                ?? candidate.automaticCompatibility.reason
        }
        return FitMatchServerReferenceSelectionCandidate(
            clientItemID: clientItemID,
            closetItemID: candidate.closetItemID,
            decision: decision,
            allowed: allowed,
            reasonCode: nil,
            reason: reason,
            commonMeasurementCount: candidate.measurementOverlapCount
        )
    }

    func beginAuthorizedComparison(
        _ authorization: FitMatchServerReferenceAuthorization,
        clientHistoryID: UUID = UUID()
    ) async throws -> FitMatchServerComparisonPermit {
        guard authorization.isAllowed,
              let reference = authorization.reference else {
            throw FitMatchServerAuthorityError.comparisonNotAuthorized
        }
        guard authorization.target.comparisonReadiness.isReady else {
            throw FitMatchServerAuthorityError.comparisonNotReady(
                authorization.target.runtime.runtimeState
            )
        }
        let allowExtended = authorization.decision == .manualSelection
        let exactCandidates: VNextEligibleCandidateSizesDTO?
        if let targetVariantID = authorization.targetVariantID {
            let value = try await remote.eligibleCandidateSizes(
                referenceClosetItemID: reference.closetItemID,
                targetProductID: authorization.target.productID,
                targetVariantID: targetVariantID,
                manualExplicit: allowExtended
            )
            guard value.allowed,
                  !value.authorizedCandidateProductSizeIDs.isEmpty else {
                if !value.allowed, let reasonCode = value.reasonCode {
                    throw FitMatchServerAuthorityError.comparisonAuthorizationRejected(
                        FitMatchComparisonBlockReason(code: reasonCode)
                    )
                }
                throw FitMatchServerAuthorityError.comparisonNotAuthorized
            }
            if !authorization.authorizedCandidateSizeIDs.isEmpty,
               Set(value.authorizedCandidateProductSizeIDs)
                    != Set(authorization.authorizedCandidateSizeIDs) {
                throw FitMatchServerAuthorityError.comparisonBeginMalformed(
                    "candidate_authority_changed"
                )
            }
            exactCandidates = value
        } else {
            exactCandidates = nil
        }
        let response = try await remote.beginComparison(
            FitMatchBeginComparisonRequest(
                referenceItemID: reference.closetItemID,
                targetProductID: authorization.target.productID,
                allowExtended: allowExtended,
                clientHistoryID: clientHistoryID,
                targetVariantID: authorization.targetVariantID,
                authorizationProductSizeID: exactCandidates?
                    .authorizedCandidateProductSizeIDs.first,
                candidateProductSizeIDs: exactCandidates?
                    .authorizedCandidateProductSizeIDs,
                effectiveAuthorityFingerprint: exactCandidates?
                    .effectiveAuthorityFingerprint,
                personalOverrideRevision: exactCandidates?
                    .personalOverrideRevision
            )
        )
        guard response.status == "pending" || response.status == "completed" else {
            if response.status == "blocked" {
                throw FitMatchServerAuthorityError.comparisonBeginRejected(
                    response.compatibility.reason ?? "comparison_blocked"
                )
            }
            throw FitMatchServerAuthorityError.comparisonBeginMalformed(
                "unknown_status_\(response.status)"
            )
        }
        guard response.compatibility.allowed else {
            throw FitMatchServerAuthorityError.comparisonBeginMalformed(
                "allowed_status_with_denied_compatibility"
            )
        }
        if authorization.decision == .automatic,
           response.compatibility.level != "direct" {
            throw FitMatchServerAuthorityError.comparisonBeginMalformed(
                "automatic_requires_direct_compatibility"
            )
        }
        if authorization.targetVariantID != nil {
            guard let exact = response.vnext,
                  Set(exact.authorizedCandidateProductSizeIDs) == Set(
                    exactCandidates?.authorizedCandidateProductSizeIDs ?? []
                  ),
                  exact.snapshot.target.variantID == authorization.targetVariantID,
                  exact.snapshot.snapshotSchemaVersion >= 3 else {
                throw FitMatchServerAuthorityError.comparisonBeginMalformed(
                    "vnext_snapshot_or_candidate_set_missing"
                )
            }
            if exactCandidates?.effectiveSource == "USER_EXPLICIT" {
                guard exact.snapshot.snapshotSchemaVersion >= 4,
                      exact.effectiveAuthorityFingerprint
                        == exactCandidates?.effectiveAuthorityFingerprint else {
                    throw FitMatchServerAuthorityError.comparisonBeginMalformed(
                        "personal_authority_snapshot_missing"
                    )
                }
            }
        }
        return FitMatchServerComparisonPermit(
            referenceAuthorization: authorization,
            clientHistoryID: clientHistoryID,
            runID: response.runID,
            compatibility: response.compatibility,
            vnextBegin: response.vnext
        )
    }

    func completeAuthorizedComparison(
        permit: FitMatchServerComparisonPermit,
        analysis: VNextComparisonBatchAnalysis
    ) async throws -> VNextCompleteComparisonDTO {
        guard permit.isAllowed,
              let begin = permit.vnextBegin,
              begin.comparisonID == permit.runID,
              analysis.comparisonID == permit.runID,
              analysis.completionPayload.recommendedProductSizeID
                == analysis.recommended.productSizeID else {
            throw FitMatchServerAuthorityError.comparisonCompletionRejected(
                "permit_or_snapshot_mismatch"
            )
        }
        let result = try await remote.completeVNextComparison(
            comparisonID: permit.runID,
            payload: analysis.completionPayload
        )
        guard result.completed,
              result.comparisonID == permit.runID,
              result.recommendedProductSizeID == analysis.recommended.productSizeID else {
            throw FitMatchServerAuthorityError.comparisonCompletionRejected(
                "server_completion_mismatch"
            )
        }
        return result
    }

    /// Recomputes the aggregate state using the exact predicates in
    /// `fitmatch_find_reference_candidates`. A malformed response must never
    /// authorize the measurement engine merely because one candidate carries
    /// a permissive flag.
    private func validateCandidateResponse(
        _ response: FitMatchReferenceCandidatesResponse
    ) throws {
        guard response.policyVersion == "classification-comparison-v4" else {
            throw FitMatchServerAuthorityError.inconsistentCandidateState(
                state: response.state,
                reason: "policy_version_mismatch"
            )
        }
        guard response.automaticCount >= 0,
              response.manualCount >= 0,
              response.structuralCount >= 0 else {
            throw FitMatchServerAuthorityError.inconsistentCandidateState(
                state: response.state,
                reason: "negative_aggregate_count"
            )
        }

        var candidateIDs = Set<UUID>()
        for candidate in response.candidates {
            guard candidateIDs.insert(candidate.closetItemID).inserted else {
                throw FitMatchServerAuthorityError.inconsistentCandidateState(
                    state: response.state,
                    reason: "duplicate_candidate"
                )
            }
            guard candidate.measurementOverlapCount >= 0 else {
                throw FitMatchServerAuthorityError.inconsistentCandidateState(
                    state: response.state,
                    reason: "negative_measurement_overlap"
                )
            }

            let automaticMinimum = candidate.automaticCompatibility
                .minimumCommonMeasurements ?? 2
            let manualMinimum = candidate.manualCompatibility
                .minimumCommonMeasurements ?? 2
            guard automaticMinimum >= 0, manualMinimum >= 0 else {
                throw FitMatchServerAuthorityError.inconsistentCandidateState(
                    state: response.state,
                    reason: "negative_measurement_minimum"
                )
            }

            let expectedAutomaticReady = candidate.automaticCompatibility.allowed
                && candidate.automaticCompatibility.level == "direct"
                && candidate.measurementOverlapCount >= automaticMinimum
            guard candidate.automaticReady == expectedAutomaticReady else {
                throw FitMatchServerAuthorityError.inconsistentCandidateState(
                    state: response.state,
                    reason: "automatic_readiness_mismatch"
                )
            }

            let expectedManualReady = candidate.manualCompatibility.allowed
                && candidate.measurementOverlapCount >= manualMinimum
            guard candidate.manualReady == expectedManualReady else {
                throw FitMatchServerAuthorityError.inconsistentCandidateState(
                    state: response.state,
                    reason: "manual_readiness_mismatch"
                )
            }
        }

        let automaticCount = response.candidates.filter(\.automaticReady).count
        let manualCount = response.candidates.filter(\.manualReady).count
        let structuralCount = response.candidates.filter {
            $0.manualCompatibility.allowed
        }.count
        guard response.automaticCount == automaticCount,
              response.manualCount == manualCount,
              response.structuralCount == structuralCount else {
            throw FitMatchServerAuthorityError.inconsistentCandidateState(
                state: response.state,
                reason: "aggregate_count_mismatch"
            )
        }

        let expectedState: String
        if automaticCount > 0 {
            expectedState = "automatic"
        } else if manualCount > 0 {
            expectedState = "manual_selection"
        } else if structuralCount > 0 {
            expectedState = "measurements_required"
        } else {
            expectedState = "no_compatible_garment"
        }
        guard response.state == expectedState else {
            throw FitMatchServerAuthorityError.inconsistentCandidateState(
                state: response.state,
                reason: "expected_\(expectedState)"
            )
        }
    }

    private func promote(
        request: FitMatchProductResolutionRequest,
        observation: FitMatchProductObservationRequest?,
        expectedProductID: UUID?
    ) async throws -> UUID {
        guard let observation else {
            throw FitMatchServerAuthorityError.missingObservationForPromotion
        }
        guard observation.payload.source
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == request.source
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
              observation.payload.externalProductID
                .trimmingCharacters(in: .whitespacesAndNewlines)
                == request.externalProductID
                    .trimmingCharacters(in: .whitespacesAndNewlines),
              observation.payload.productName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                == request.productName
                    .trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw FitMatchServerAuthorityError.observationIdentityMismatch
        }

        let response = try await remote.submitProductObservation(observation)
        guard response.observation.observationID == response.processing.observationID else {
            throw FitMatchServerAuthorityError.promotionResponseMalformed
        }
        guard response.processing.status == "promoted" else {
            throw FitMatchServerAuthorityError.promotionRejected(
                response.processing.status
            )
        }
        guard let productID = response.processing.productID else {
            throw FitMatchServerAuthorityError.promotionResponseMalformed
        }
        if let expectedProductID, expectedProductID != productID {
            throw FitMatchServerAuthorityError.promotedProductMismatch
        }
        return productID
    }

    private func observationCanImproveRuntime(
        _ observation: FitMatchProductObservationRequest?,
        runtimeState: String
    ) -> Bool {
        guard let observation else { return false }
        switch runtimeState {
        case "classification_required":
            // A previously observed product can remain REVIEW_REQUIRED only
            // because its older receipt did not contain the provider size
            // table/measurement-contract facts now available to the parser.
            // Re-submit only a provider-backed coherent contract with actual
            // measurements. The ingestion boundary owns duplicate/stale
            // handling and the server remains the classification authority.
            let contract = observation.payload.structuredFacts[
                "comparison_measurement_contract"
            ]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard contract == "single_coherent" else { return false }
            return observation.payload.variants.contains { variant in
                variant.sizes.contains { !$0.measurements.isEmpty }
            }
        case "sizes_required":
            return observation.payload.variants.contains { !$0.sizes.isEmpty }
        case "measurements_required":
            return observation.payload.variants.contains { variant in
                variant.sizes.contains { !$0.measurements.isEmpty }
            }
        default:
            return false
        }
    }

    private func validatedAuthority(
        _ runtime: FitMatchProductRuntimeResponse,
        request: FitMatchProductResolutionRequest,
        expectedProductID: UUID?
    ) throws -> FitMatchServerProductAuthority {
        if let expectedProductID, runtime.product.productID != expectedProductID {
            throw FitMatchServerAuthorityError.promotedProductMismatch
        }
        guard runtime.product.source.lowercased() == request.source.lowercased(),
              runtime.product.externalProductID == request.externalProductID else {
            throw FitMatchServerAuthorityError.runtimeResponseMalformed(
                "product_identity_mismatch"
            )
        }
        guard let classification = runtime.classification else {
            throw FitMatchServerAuthorityError.runtimeResponseMalformed(
                "classification_missing"
            )
        }
        guard classification.classificationID != nil else {
            throw FitMatchServerAuthorityError.runtimeResponseMalformed(
                "classification_not_persisted"
            )
        }
        let status = try classificationStatus(classification.status)

        switch status {
        case .confirmed:
            guard !classification.requiresUserConfirmation,
                  hasText(classification.categoryCode),
                  hasText(classification.detailCode),
                  hasText(classification.garmentTypeCode),
                  hasText(classification.familyCode) else {
                throw FitMatchServerAuthorityError.runtimeResponseMalformed(
                    "confirmed_tuple_incomplete"
                )
            }
            guard ["ready", "sizes_required", "measurements_required"]
                .contains(runtime.runtimeState) else {
                throw FitMatchServerAuthorityError.inconsistentRuntimeState(
                    state: runtime.runtimeState,
                    status: status.rawValue
                )
            }
            if runtime.comparisonReady != (runtime.runtimeState == "ready") {
                throw FitMatchServerAuthorityError.runtimeResponseMalformed(
                    "comparison_readiness_mismatch"
                )
            }
        case .reviewRequired:
            guard runtime.runtimeState == "classification_required",
                  !runtime.comparisonReady else {
                throw FitMatchServerAuthorityError.inconsistentRuntimeState(
                    state: runtime.runtimeState,
                    status: status.rawValue
                )
            }
        case .notComparable:
            guard runtime.runtimeState == "not_comparable",
                  !runtime.comparisonReady else {
                throw FitMatchServerAuthorityError.inconsistentRuntimeState(
                    state: runtime.runtimeState,
                    status: status.rawValue
                )
            }
        }

        return FitMatchServerProductAuthority(
            status: status,
            productID: runtime.product.productID,
            classification: classification,
            runtime: runtime
        )
    }

    private func classificationStatus(
        _ rawValue: String
    ) throws -> FitMatchServerProductAuthorityStatus {
        guard let status = FitMatchServerProductAuthorityStatus(rawValue: rawValue) else {
            throw FitMatchServerAuthorityError.unknownClassificationStatus(rawValue)
        }
        return status
    }

    private func referenceAuthority(
        for reference: FitMatchClosetItemRecord,
        request: FitMatchProductResolutionRequest?,
        resolvedAuthority: FitMatchServerProductAuthority?
    ) -> FitMatchServerReferenceAuthority? {
        guard reference.classificationStatus == "confirmed",
              hasText(reference.categoryCode),
              hasText(reference.detailCode),
              hasText(reference.familyCode) else {
            return nil
        }
        switch reference.classificationSource {
        case "product_metadata":
            guard let productID = reference.productID,
                  let externalProductID = reference.externalProductID,
                  let request,
                  let authority = resolvedAuthority,
                  request.source.caseInsensitiveCompare(reference.source) == .orderedSame,
                  request.externalProductID == externalProductID,
                  request.productName == reference.productName else {
                return nil
            }
            guard authority.status == .confirmed,
                  authority.productID == productID,
                  referenceTupleMatches(
                    reference,
                    classification: authority.classification
                  ) else {
                return nil
            }
            return .serverConfirmed
        case "manual_override":
            return .userExplicit
        default:
            return nil
        }
    }

    private func referenceTupleMatches(
        _ reference: FitMatchClosetItemRecord,
        classification: FitMatchDatabaseClassification
    ) -> Bool {
        let category = reference.canonicalCategoryCode ?? reference.categoryCode
        let detail = reference.canonicalDetailCode ?? reference.detailCode
        return category == classification.categoryCode
            && detail == classification.detailCode
            && reference.familyCode == classification.familyCode
            && reference.lengthCode == classification.lengthCode
            && reference.bodyLengthCode == classification.bodyLengthCode
    }

    private func referenceMatchesLocalSnapshot(
        _ reference: FitMatchClosetItemRecord,
        snapshot: FitMatchLocalReferenceSnapshot
    ) -> Bool {
        let category = reference.canonicalCategoryCode ?? reference.categoryCode
        let detail = reference.canonicalDetailCode ?? reference.detailCode
        guard reference.productName.trimmingCharacters(in: .whitespacesAndNewlines)
                == snapshot.productName.trimmingCharacters(in: .whitespacesAndNewlines),
              reference.sizeName?.trimmingCharacters(in: .whitespacesAndNewlines)
                == snapshot.sizeName?.trimmingCharacters(in: .whitespacesAndNewlines),
              category == snapshot.categoryCode,
              detail == snapshot.detailCode,
              reference.familyCode == snapshot.familyCode,
              reference.lengthCode == snapshot.lengthCode else {
            return false
        }
        if let bodyLengthCode = snapshot.bodyLengthCode,
           reference.bodyLengthCode != bodyLengthCode {
            return false
        }

        let localMeasurements = snapshot.measurements.filter {
            $0.value.isFinite && $0.value > 0
        }
        let remoteMeasurements = reference.measurements.filter {
            $0.value.isFinite && $0.value > 0
        }
        guard localMeasurements.keys == remoteMeasurements.keys else { return false }
        return localMeasurements.allSatisfy { key, value in
            guard let remoteValue = remoteMeasurements[key] else { return false }
            return abs(value - remoteValue) < 0.000_001
        }
    }

    private func hasText(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func blockedAuthorization(
        reason: String,
        reasonCode: String? = nil,
        target: FitMatchServerProductAuthority,
        reference: FitMatchClosetItemRecord?,
        referenceAuthority: FitMatchServerReferenceAuthority? = nil,
        candidate: FitMatchReferenceCandidate? = nil,
        candidateState: String? = nil
    ) -> FitMatchServerReferenceAuthorization {
        FitMatchServerReferenceAuthorization(
            decision: .blocked,
            reasonCode: reasonCode,
            reason: reason,
            target: target,
            reference: reference,
            referenceAuthority: referenceAuthority,
            candidate: candidate,
            candidateState: candidateState
        )
    }
}
