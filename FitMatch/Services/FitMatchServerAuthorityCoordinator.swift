import Foundation
import Supabase

/// User-facing failure copy is intentionally split by whether a retry can
/// reasonably change the result. Contract, identity, endpoint, and server
/// policy failures are not presented as temporary network failures.
nonisolated enum FitMatchFailureCopy {
    static let transientNetwork =
        "일시적인 연결 문제예요. 네트워크를 확인한 뒤 다시 시도해 주세요."
    static let serviceInspection =
        "서비스에 문제가 있어요. 지금은 진행할 수 없어요. 문제가 계속되면 문의해 주세요."
    static let productServiceInspection =
        "상품 정보를 서비스에서 확인하지 못했어요. 문제가 계속되면 문의해 주세요."
    static let comparisonServiceInspection =
        "비교 서비스에 문제가 있어요. 지금은 비교할 수 없어요. 문제가 계속되면 문의해 주세요."
    static let authorizationInspection =
        "이 작업을 진행할 권한이 없어요. 문제가 계속되면 문의해 주세요."
    static let authenticationServiceInspection =
        "로그인 서비스에 문제가 있어요. 문제가 계속되면 문의해 주세요."
    static let refreshAndRetry =
        "최신 정보를 확인하지 못했어요. 새로고침한 뒤 다시 시도해 주세요."
    static let loginRequired =
        "로그인이 필요한 기능입니다. 다시 로그인한 뒤 시도해 주세요."
    static let appUpdateRequired =
        "현재 앱과 서버가 맞지 않아 안전하게 처리할 수 없어요. 앱을 업데이트한 뒤 다시 확인해 주세요."
}

protocol FitMatchServerAuthorityRemoteServicing: Sendable {
    func resolve(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductResolutionResponse
    func resolveWithRuntime(_ request: FitMatchProductResolutionRequest) async throws
        -> (resolution: FitMatchProductResolutionResponse, runtime: FitMatchProductRuntimeResponse?)
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
    func findReferenceCandidates(targetProductID: UUID, targetVariantID: UUID,
                                 requestedComparisonGroupCode: String?) async throws
        -> FitMatchReferenceCandidatesResponse
    func eligibleCandidateSizes(
        referenceClosetItemID: UUID,
        targetProductID: UUID,
        targetVariantID: UUID,
        manualExplicit: Bool
    ) async throws -> VNextEligibleCandidateSizesDTO
    func eligibleCandidateSizes(referenceClosetItemID: UUID, targetProductID: UUID,
                                targetVariantID: UUID, manualExplicit: Bool,
                                requestedComparisonGroupCode: String?) async throws
        -> VNextEligibleCandidateSizesDTO
    func beginComparison(_ request: FitMatchBeginComparisonRequest) async throws
        -> FitMatchBeginComparisonResponse
    func completeVNextComparison(
        comparisonID: UUID,
        payload: VNextComparisonCompletionPayload
    ) async throws -> VNextCompleteComparisonDTO
}

extension FitMatchSupabaseDomainClient: FitMatchServerAuthorityRemoteServicing {}

extension FitMatchServerAuthorityRemoteServicing {
    func resolveWithRuntime(_ request: FitMatchProductResolutionRequest) async throws
        -> (resolution: FitMatchProductResolutionResponse, runtime: FitMatchProductRuntimeResponse?) {
        (try await resolve(request), nil)
    }

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

    func findReferenceCandidates(targetProductID: UUID, targetVariantID: UUID,
                                 requestedComparisonGroupCode: String?) async throws
        -> FitMatchReferenceCandidatesResponse {
        guard requestedComparisonGroupCode == nil else {
            throw FitMatchServerAuthorityError.comparisonBeginUnavailable
        }
        return try await findReferenceCandidates(
            targetProductID: targetProductID,
            targetVariantID: targetVariantID
        )
    }

    func eligibleCandidateSizes(
        referenceClosetItemID: UUID,
        targetProductID: UUID,
        targetVariantID: UUID,
        manualExplicit: Bool
    ) async throws -> VNextEligibleCandidateSizesDTO {
        throw FitMatchServerAuthorityError.comparisonBeginUnavailable
    }

    func eligibleCandidateSizes(referenceClosetItemID: UUID, targetProductID: UUID,
                                targetVariantID: UUID, manualExplicit: Bool,
                                requestedComparisonGroupCode: String?) async throws
        -> VNextEligibleCandidateSizesDTO {
        guard requestedComparisonGroupCode == nil else {
            throw FitMatchServerAuthorityError.comparisonBeginUnavailable
        }
        return try await eligibleCandidateSizes(
            referenceClosetItemID: referenceClosetItemID,
            targetProductID: targetProductID,
            targetVariantID: targetVariantID,
            manualExplicit: manualExplicit
        )
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
    /// Present only when this authority was built from the exact retailer
    /// observation submitted for the current load.
    let sourceObservationID: UUID?

    init(
        status: FitMatchServerProductAuthorityStatus,
        productID: UUID,
        classification: FitMatchDatabaseClassification,
        runtime: FitMatchProductRuntimeResponse,
        sourceObservationID: UUID? = nil
    ) {
        self.status = status
        self.productID = productID
        self.classification = classification
        self.runtime = runtime
        self.sourceObservationID = sourceObservationID
    }

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
            return FitMatchFailureCopy.productServiceInspection
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
    /// The current Closet receipt's server-issued group. This is compared to
    /// the target context before a selectable candidate reaches the UI.
    let comparisonGroupCode: String?
    let decision: FitMatchServerReferenceDecision
    let allowed: Bool
    let reasonCode: String?
    let reason: String?
    let commonMeasurementCount: Int?

    var isSelectable: Bool {
        allowed && (decision == .automatic || decision == .manualSelection)
    }

    /// Keeps the server explanation in `reason` for diagnostics while exposing
    /// a stable Korean sentence at the presentation boundary.
    var selectionUserMessage: String {
        if let commonMeasurementCount, commonMeasurementCount > 0 {
            return "공통 실측 항목 \(commonMeasurementCount)개로 비교할 수 있습니다."
        }
        switch FitMatchComparisonBlockReason(code: reasonCode) {
        case .userSelectedReference:
            return "직접 선택해 비교할 수 있는 내 옷입니다."
        case .automaticMatch:
            return "자동 비교가 가능한 내 옷입니다."
        default:
            return "서버가 비교 가능한 내 옷으로 승인했습니다."
        }
    }
}

nonisolated struct FitMatchServerReferenceSelectionPlan: Equatable, Sendable {
    let target: FitMatchServerProductAuthority
    let status: FitMatchServerReferenceSelectionStatus
    /// Preserves the order returned by the vNext candidate RPC.
    let candidates: [FitMatchServerReferenceSelectionCandidate]
    let blockedCandidates: [FitMatchServerReferenceSelectionCandidate]
    /// The DB-issued mapped group, or a session-only requested group accepted
    /// by the candidate RPC. It never changes product classification.
    let targetComparisonGroupCode: String?
    let targetComparisonGroup: VNextComparisonGroupDTO?
    /// Nil means this plan was not accompanied by a verified Closet receipt.
    let serverClosetItemCount: Int?

    init(
        target: FitMatchServerProductAuthority,
        status: FitMatchServerReferenceSelectionStatus,
        candidates: [FitMatchServerReferenceSelectionCandidate],
        blockedCandidates: [FitMatchServerReferenceSelectionCandidate],
        targetComparisonGroupCode: String? = nil,
        targetComparisonGroup: VNextComparisonGroupDTO? = nil,
        serverClosetItemCount: Int? = nil
    ) {
        self.target = target
        self.status = status
        self.candidates = candidates
        self.blockedCandidates = blockedCandidates
        self.targetComparisonGroup = targetComparisonGroup
        self.serverClosetItemCount = serverClosetItemCount
        self.targetComparisonGroupCode = targetComparisonGroupCode
            ?? targetComparisonGroup?.groupCode
            ?? target.runtime.vnext?.comparisonGroup?.groupCode
    }

    var automaticCandidates: [FitMatchServerReferenceSelectionCandidate] {
        candidates.filter { $0.allowed && $0.decision == .automatic }
    }

    var manualCandidates: [FitMatchServerReferenceSelectionCandidate] {
        candidates.filter { $0.allowed && $0.decision == .manualSelection }
    }

    var measurementRequiredCandidates: [FitMatchServerReferenceSelectionCandidate] {
        (candidates + blockedCandidates).filter {
            $0.decision == .measurementsRequired
        }
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
    case comparisonGroupRequired = "COMPARISON_GROUP_REQUIRED"
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
            return "자동으로 비교할 옷을 고르지 못해 직접 선택이 필요합니다."
        case .incompatibleBodyRegion:
            return "이 두 옷은 측정하는 신체 부위가 달라 비교하기 어려워요."
        case .noCommonMeasurements:
            return "이 두 옷은 함께 비교할 수 있는 실측 항목이 없어요."
        case .structurallyNotComparable:
            return "여러 종류의 옷이 함께 구성된 상품은 비교할 수 없어요."
        case .invalidAuthority:
            return "선택한 내 옷 또는 상품 정보를 다시 확인해 주세요."
        case .staleReference:
            return "선택한 내 옷 정보가 바뀌었어요. 최신 정보로 다시 확인해 주세요."
        case .noEligibleTargetSize:
            return "비교에 사용할 상품 사이즈 실측이 없어요."
        case .serverUnavailable:
            return FitMatchFailureCopy.comparisonServiceInspection
        case .incompatibleAudience:
            return "대상 사용자 범위가 달라 비교하기 어려워요."
        case .designAxisDifference:
            return "디자인 축이 달라 이 조합은 비교할 수 없어요."
        case .comparisonGroupRequired:
            return "같은 비교 그룹의 내 옷만 선택할 수 있어요."
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
    let requestedComparisonGroupCode: String?
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
        requestedComparisonGroupCode: String? = nil,
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
        self.requestedComparisonGroupCode = requestedComparisonGroupCode
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
    case comparisonAlreadyCompleted
    case comparisonBeginMalformed(String)
    case comparisonContractViolation(FitMatchVNextContractError)
    case comparisonCompletionUnavailable
    case comparisonCompletionRejected(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedCatalogState:
            return FitMatchFailureCopy.productServiceInspection
        case .missingObservationForPromotion:
            return FitMatchFailureCopy.productServiceInspection
        case .observationIdentityMismatch:
            return FitMatchFailureCopy.productServiceInspection
        case .promotionRejected:
            return FitMatchFailureCopy.productServiceInspection
        case .promotionResponseMalformed:
            return FitMatchFailureCopy.productServiceInspection
        case .promotedProductMismatch:
            return FitMatchFailureCopy.productServiceInspection
        case .runtimeResponseMalformed, .unknownClassificationStatus,
             .inconsistentRuntimeState:
            return FitMatchFailureCopy.productServiceInspection
        case .classificationRecoveryUnavailable:
            return FitMatchFailureCopy.productServiceInspection
        case .invalidClassificationRecoveryContract:
            return FitMatchFailureCopy.productServiceInspection
        case .classificationRecoveryRejected:
            return "상품 분류 선택을 저장하지 못했어요. 최신 상품 상태를 다시 확인해 주세요."
        case .closetRuntimeUnavailable:
            return "내 옷장 정보를 서비스에서 확인하지 못했어요. 문제가 계속되면 문의해 주세요."
        case .referenceItemNotFound:
            return "서버에서 비교 후보를 확인하지 못했어요. 문제가 계속되면 문의해 주세요."
        case .localReferenceProjectionMissing:
            return "내 옷장 정보를 새로고침한 뒤 다시 비교해 주세요."
        case .targetClassificationRequired:
            return "상품 분류를 확인한 뒤 비교해 주세요."
        case .comparisonNotReady(let state):
            return FitMatchServerComparisonReadiness(
                runtimeState: state,
                comparisonReady: false
            ).userMessage
        case .unknownCandidateState, .inconsistentCandidateState:
            return FitMatchFailureCopy.comparisonServiceInspection
        case .comparisonBeginUnavailable:
            return FitMatchFailureCopy.comparisonServiceInspection
        case .comparisonNotAuthorized:
            return "이 비교는 현재 진행할 수 없어요. 상품과 내 옷 정보를 다시 확인한 뒤 비교해 주세요."
        case .comparisonAuthorizationRejected(let reason):
            return reason.userMessage
        case .comparisonBeginRejected:
            return "비교를 시작할 수 없는 상태예요. 상품과 내 옷 정보를 다시 확인해 주세요."
        case .comparisonAlreadyCompleted:
            return "이미 완료된 비교입니다. 비교 기록에서 확인해 주세요."
        case .comparisonBeginMalformed:
            return FitMatchFailureCopy.comparisonServiceInspection
        case .comparisonContractViolation(let error):
            return error.errorDescription
        case .comparisonCompletionUnavailable:
            return FitMatchFailureCopy.comparisonServiceInspection
        case .comparisonCompletionRejected:
            return FitMatchFailureCopy.comparisonServiceInspection
        }
    }
}

actor FitMatchServerAuthorityCoordinator {
    private struct PromotedObservation: Sendable {
        let productID: UUID
        let observationID: UUID
    }

    private let remote: any FitMatchServerAuthorityRemoteServicing
    private var submittedObservationKeys = Set<String>()

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
        try Task.checkCancellation()
        let contract = try await remote.classificationRecoveryOptions(
            productID: productID
        )
        try Task.checkCancellation()
        guard contract.productID == productID,
              contract.globalStatus == "REVIEW_REQUIRED" else {
            throw FitMatchServerAuthorityError.invalidClassificationRecoveryContract(
                "product_or_global_status_mismatch"
            )
        }
        if contract.recoverability == .recoverable {
            guard contract.supportedContractVersion != nil else {
                throw FitMatchServerAuthorityError
                    .invalidClassificationRecoveryContract(
                        "unsupported_candidate_contract_version"
                    )
            }
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
        try Task.checkCancellation()
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
        try Task.checkCancellation()
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
        try Task.checkCancellation()
        let result = try await remote.clearUserProductClassification(
            FitMatchClearUserProductClassificationRequest(
                productID: productID,
                mutationID: mutationID,
                expectedRevision: expectedRevision
            )
        )
        try Task.checkCancellation()
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
        try Task.checkCancellation()
        let resolved = try await remote.resolveWithRuntime(request)
        let resolution = resolved.resolution
        try Task.checkCancellation()
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
            ).productID
            didPromote = true
        default:
            throw FitMatchServerAuthorityError.unsupportedCatalogState(
                resolution.catalogState
            )
        }

        try Task.checkCancellation()
        // Reuse only the response obtained in this call, never a cross-request cache.
        // Any promotion changes server state and requires a new authoritative read.
        var runtime: FitMatchProductRuntimeResponse
        if !didPromote, let resolvedRuntime = resolved.runtime {
            runtime = resolvedRuntime
        } else {
            runtime = try await remote.fetchProductRuntime(request)
        }
        try Task.checkCancellation()
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
            try Task.checkCancellation()
            runtime = try await remote.fetchProductRuntime(request)
            try Task.checkCancellation()
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
            try Task.checkCancellation()
            runtime = try await remote.fetchProductRuntime(request)
            try Task.checkCancellation()
        }

        return try validatedAuthority(
            runtime,
            request: request,
            expectedProductID: expectedProductID
        )
    }

    /// Persists a retailer API snapshot before reading any existing runtime.
    /// Ingestion owns idempotency and returns the exact product identity used
    /// for the subsequent authoritative runtime read.
    func resolveFreshRetailerProductAuthority(
        request: FitMatchProductResolutionRequest,
        observation: FitMatchProductObservationRequest,
        diagnosticTraceID: UUID? = nil
    ) async throws -> FitMatchServerProductAuthority {
        do {
            try Task.checkCancellation()
            let promotion = try await promote(
                request: request,
                observation: observation,
                expectedProductID: nil,
                diagnosticTraceID: diagnosticTraceID
            )
            let productID = promotion.productID
#if DEBUG
            FitMatchDebugLogger.flow(
                traceID: diagnosticTraceID,
                stage: "DB 상품 런타임 조회",
                state: "요청",
                fields: [
                    "쇼핑몰코드": request.source,
                    "상품ID": request.externalProductID,
                    "DB상품UUID": productID.uuidString
                ]
            )
#endif
            try Task.checkCancellation()
            let runtime = try await remote.fetchProductRuntime(request)
            try Task.checkCancellation()
#if DEBUG
            let runtimeSizeCount = runtime.variants.reduce(0) { $0 + $1.sizes.count }
            FitMatchDebugLogger.flow(
                traceID: diagnosticTraceID,
                stage: "DB 상품 런타임 조회",
                state: "완료",
                fields: [
                    "DB상품UUID": runtime.product.productID.uuidString,
                    "런타임상태": runtime.runtimeState,
                    "비교준비": String(runtime.comparisonReady),
                    "분류상태": runtime.classification?.status ?? "없음",
                    "비교그룹": runtime.vnext?.comparisonGroup?.groupCode ?? "미매핑",
                    "그룹출처": runtime.vnext?.comparisonGroup?.source ?? "없음",
                    "변형수": String(runtime.variants.count),
                    "사이즈수": String(runtimeSizeCount)
                ]
            )
#endif
            guard runtime.runtimeState != "classification_promotion_required" else {
                throw FitMatchServerAuthorityError.inconsistentRuntimeState(
                    state: runtime.runtimeState,
                    status: runtime.classification?.status ?? "missing"
                )
            }
            let authority = try validatedAuthority(
                runtime,
                request: request,
                expectedProductID: productID,
                sourceObservationID: promotion.observationID
            )
#if DEBUG
            FitMatchDebugLogger.flow(
                traceID: diagnosticTraceID,
                stage: "서버 상품 권한 검증",
                state: "완료",
                fields: [
                    "판정": authority.status.rawValue,
                    "비교준비": String(describing: authority.comparisonReadiness),
                    "DB상품UUID": authority.productID.uuidString
                ]
            )
#endif
            return authority
        } catch {
#if DEBUG
            FitMatchDebugLogger.failure(
                traceID: diagnosticTraceID,
                stage: "서버 상품 저장/권한 검증",
                error: error,
                nextAction: "observation 처리 상태, runtime 응답 필드, 그룹/준비상태 계약을 확인하세요.",
                fields: ["상품ID": request.externalProductID]
            )
#endif
            throw error
        }
    }

    /// Reads current runtime after a user mutation without creating or
    /// resubmitting an observation. This preserves the mutation contract's
    /// evidence fingerprint and revision.
    func refreshProductAuthority(
        request: FitMatchProductResolutionRequest,
        expectedProductID: UUID
    ) async throws -> FitMatchServerProductAuthority {
        try Task.checkCancellation()
        let runtime = try await remote.fetchProductRuntime(request)
        try Task.checkCancellation()
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
        referenceObservation: FitMatchProductObservationRequest? = nil,
        requestedComparisonGroupCode: String? = nil
    ) async throws -> FitMatchServerReferenceAuthorization {
        let authorizationStartedAt = Date()
        defer {
#if DEBUG
            FitMatchDebugLogger.duration(
                stage: "선택 옷 서버 허가 준비",
                startedAt: authorizationStartedAt,
                state: "종료"
            )
#endif
        }
        try Task.checkCancellation()
        // The current Closet receipt is independent of target/reference
        // authority resolution. Start the read now, but keep every identity
        // and policy check below exactly where it was before candidates are
        // requested.
        async let targetAuthority = resolveProductAuthority(
            request: targetRequest,
            observation: targetObservation
        )
        async let closetReceipt = remote.listClosetItems()
        async let resolvedReferenceAuthorityTask: FitMatchServerProductAuthority? = {
            guard let referenceRequest else { return nil }
            return try await resolveProductAuthority(
                request: referenceRequest,
                observation: referenceObservation
            )
        }()

        var target = try await targetAuthority
        try Task.checkCancellation()

        if target.status == .confirmed,
           requestedComparisonGroupCode == nil,
           !target.comparisonReadiness.isReady {
            throw FitMatchServerAuthorityError.comparisonNotReady(
                target.runtime.runtimeState
            )
        }

        let resolvedReference = try await resolvedReferenceAuthorityTask
        try Task.checkCancellation()

        let closet = try await closetReceipt
        try Task.checkCancellation()
        guard closet.state == "ready" else {
            throw FitMatchServerAuthorityError.closetRuntimeUnavailable(closet.state)
        }
        guard let reference = closet.items.first(where: {
            $0.clientItemID == referenceClientItemID
        }) else {
            throw FitMatchServerAuthorityError.referenceItemNotFound
        }

        guard target.status != .notComparable else {
            return blockedAuthorization(
                reason: "target_not_comparable",
                reasonCode: FitMatchComparisonBlockReason
                    .structurallyNotComparable.rawValue,
                target: target,
                reference: reference
            )
        }
        guard target.status == .confirmed || requestedComparisonGroupCode != nil else {
            return blockedAuthorization(
                reason: "target_review_required",
                reasonCode: FitMatchComparisonBlockReason
                    .classificationRequired.rawValue,
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
        try Task.checkCancellation()
        var candidates = try await findReferenceCandidates(
            targetProductID: target.productID,
            targetVariantID: targetVariantID,
            requestedComparisonGroupCode: requestedComparisonGroupCode
        )
        try Task.checkCancellation()
        if candidates.state == "target_classification_required" {
            try Task.checkCancellation()
            target = try await resolveProductAuthority(
                request: targetRequest,
                observation: targetObservation
            )
            try Task.checkCancellation()
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
            try Task.checkCancellation()
            candidates = try await findReferenceCandidates(
                targetProductID: target.productID,
                targetVariantID: targetVariantID,
                requestedComparisonGroupCode: requestedComparisonGroupCode
            )
            try Task.checkCancellation()
            if candidates.state == "target_classification_required" {
                throw FitMatchServerAuthorityError.targetClassificationRequired
            }
        }
        if let requestedComparisonGroupCode {
            guard let responseGroup = candidates.vnext?.targetComparisonGroup,
                  responseGroup.groupCode == requestedComparisonGroupCode,
                  responseGroup.source == "SESSION_USER_SELECTED",
                  responseGroup.comparisonPolicyCode?.isEmpty == false,
                  responseGroup.policyVersion?.isEmpty == false,
                  responseGroup.authorityVersion?.isEmpty == false,
                  responseGroup.authorityFingerprint?.isEmpty == false else {
                throw FitMatchServerAuthorityError.inconsistentCandidateState(
                    state: candidates.state,
                    reason: "requested_group_context_mismatch"
                )
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

        if let vnext = candidates.vnext {
            guard let targetComparisonGroupCode = vnext.targetComparisonGroup?.groupCode,
                  FitMatchComparisonGroup(rawValue: targetComparisonGroupCode) != nil else {
                throw FitMatchServerAuthorityError.inconsistentCandidateState(
                    state: vnext.status,
                    reason: "target_comparison_group_missing_or_invalid"
                )
            }
            guard reference.comparisonGroupCode == targetComparisonGroupCode else {
                return blockedAuthorization(
                    reason: "reference_comparison_group_mismatch",
                    reasonCode: FitMatchComparisonBlockReason
                        .comparisonGroupRequired.rawValue,
                    target: target,
                    reference: reference,
                    referenceAuthority: referenceAuthority,
                    candidateState: candidates.state
                )
            }
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
                    requestedComparisonGroupCode: requestedComparisonGroupCode,
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
                    requestedComparisonGroupCode: requestedComparisonGroupCode,
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
                    requestedComparisonGroupCode: requestedComparisonGroupCode,
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
        localClientItemIDs: Set<UUID>? = nil,
        requestedComparisonGroupCode: String? = nil
    ) async throws -> FitMatchServerReferenceSelectionPlan {
        let diagnosticTraceID = FitMatchRequestTrace.context?.id ?? UUID()
        let candidateStartedAt = Date()
        defer {
#if DEBUG
            FitMatchDebugLogger.duration(
                traceID: diagnosticTraceID,
                stage: "상품 진입→후보 준비",
                startedAt: candidateStartedAt,
                state: "종료"
            )
#endif
        }
#if DEBUG
        FitMatchDebugLogger.flow(
            traceID: diagnosticTraceID,
            stage: "내 옷 비교 후보 조회",
            state: "시작",
            fields: [
                "상품ID": targetRequest.externalProductID,
                "사용자선택그룹": requestedComparisonGroupCode ?? "없음"
            ]
        )
#endif
        try Task.checkCancellation()
        async let targetAuthority = resolveProductAuthority(
            request: targetRequest,
            observation: targetObservation
        )
        async let closetReceipt = remote.listClosetItems()
        let target = try await targetAuthority
        try Task.checkCancellation()
        guard target.status != .notComparable else {
            throw FitMatchServerAuthorityError.targetClassificationRequired
        }
        guard target.status == .confirmed || requestedComparisonGroupCode != nil else {
            throw FitMatchServerAuthorityError.targetClassificationRequired
        }
        guard target.comparisonReadiness.isReady || requestedComparisonGroupCode != nil else {
            throw FitMatchServerAuthorityError.comparisonNotReady(
                target.runtime.runtimeState
            )
        }

        let closet = try await closetReceipt
        try Task.checkCancellation()
#if DEBUG
        FitMatchDebugLogger.flow(
            traceID: diagnosticTraceID,
            stage: "내 옷장 데이터 조회",
            state: "완료",
            fields: ["응답상태": closet.state, "내옷수": String(closet.items.count)]
        )
#endif
        guard closet.state == "ready" else {
            throw FitMatchServerAuthorityError.closetRuntimeUnavailable(closet.state)
        }
        _ = try FitMatchVNextContractValidator.uniqueIdentityIndex(closet.items, id: { $0.clientItemID })
        let closetItemByID = try FitMatchVNextContractValidator
            .uniqueIdentityIndex(closet.items, id: { $0.closetItemID })
        let clientIDByClosetID = closetItemByID.mapValues(\.clientItemID)
        let targetVariantID = targetVariantID(
            for: target,
            observation: targetObservation
        )
        try Task.checkCancellation()
        let response = try await findReferenceCandidates(
            targetProductID: target.productID,
            targetVariantID: targetVariantID,
            requestedComparisonGroupCode: requestedComparisonGroupCode
        )
        try Task.checkCancellation()
#if DEBUG
        FitMatchDebugLogger.flow(
            traceID: diagnosticTraceID,
            stage: "내 옷 비교 후보 조회",
            state: "서버응답",
            fields: [
                "응답상태": response.vnext?.status ?? response.state,
                "서버확정그룹": response.vnext?.targetComparisonGroup?.groupCode ?? "없음",
                "그룹출처": response.vnext?.targetComparisonGroup?.source ?? "없음",
                "후보수": String(response.vnext?.candidates.count ?? response.candidates.count),
                "차단후보수": String(response.vnext?.blocked.count ?? 0)
            ]
        )
#endif
        guard response.state != "target_classification_required" else {
            throw FitMatchServerAuthorityError.targetClassificationRequired
        }

        let plan: FitMatchServerReferenceSelectionPlan
        if let vnext = response.vnext {
            let responseGroup = vnext.targetComparisonGroup
            if let requestedComparisonGroupCode {
                guard responseGroup?.groupCode == requestedComparisonGroupCode,
                      responseGroup?.source == "SESSION_USER_SELECTED",
                      responseGroup?.comparisonPolicyCode?.isEmpty == false,
                      responseGroup?.policyVersion?.isEmpty == false,
                      responseGroup?.authorityVersion?.isEmpty == false,
                      responseGroup?.authorityFingerprint?.isEmpty == false else {
                    throw FitMatchServerAuthorityError.inconsistentCandidateState(
                        state: vnext.status,
                        reason: "requested_group_context_mismatch"
                    )
                }
            }
            let candidates = try vnext.candidates.map {
                try makeReferenceSelectionCandidate(
                    from: $0,
                    closetItemByID: closetItemByID
                )
            }
            let blocked = try vnext.blocked.map {
                try makeReferenceSelectionCandidate(
                    from: $0,
                    closetItemByID: closetItemByID
                )
            }
            guard let targetComparisonGroupCode = responseGroup?.groupCode,
                  FitMatchComparisonGroup(rawValue: targetComparisonGroupCode) != nil else {
                throw FitMatchServerAuthorityError.inconsistentCandidateState(
                    state: vnext.status,
                    reason: "target_comparison_group_missing_or_invalid"
                )
            }
            guard candidates.filter(\.isSelectable).allSatisfy({
                $0.comparisonGroupCode == targetComparisonGroupCode
            }) else {
                throw FitMatchServerAuthorityError.inconsistentCandidateState(
                    state: vnext.status,
                    reason: "selectable_candidate_comparison_group_mismatch"
                )
            }
            plan = FitMatchServerReferenceSelectionPlan(
                target: target,
                status: try referenceSelectionStatus(vnext.status),
                candidates: candidates,
                blockedCandidates: blocked,
                targetComparisonGroupCode: targetComparisonGroupCode,
                targetComparisonGroup: responseGroup,
                serverClosetItemCount: closet.items.count
            )
        } else {
            guard requestedComparisonGroupCode == nil else {
                throw FitMatchServerAuthorityError.inconsistentCandidateState(
                    state: response.state,
                    reason: "requested_group_context_missing"
                )
            }
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
                blockedCandidates: [],
                targetComparisonGroupCode: requestedComparisonGroupCode,
                serverClosetItemCount: closet.items.count
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
        targetVariantID: UUID?,
        requestedComparisonGroupCode: String? = nil
    ) async throws -> FitMatchReferenceCandidatesResponse {
        if let targetVariantID {
            return try await remote.findReferenceCandidates(
                targetProductID: targetProductID,
                targetVariantID: targetVariantID,
                requestedComparisonGroupCode: requestedComparisonGroupCode
            )
        }
        guard requestedComparisonGroupCode == nil else {
            throw FitMatchServerAuthorityError.comparisonBeginUnavailable
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
        closetItemByID: [UUID: FitMatchClosetItemRecord]
    ) throws -> FitMatchServerReferenceSelectionCandidate {
        guard let closetItem = closetItemByID[candidate.closetItemID] else {
            throw FitMatchServerAuthorityError.referenceItemNotFound
        }
        return FitMatchServerReferenceSelectionCandidate(
            clientItemID: closetItem.clientItemID,
            closetItemID: candidate.closetItemID,
            comparisonGroupCode: closetItem.comparisonGroupCode,
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
            comparisonGroupCode: nil,
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
        let diagnosticTraceID = FitMatchRequestTrace.context?.id ?? clientHistoryID
        let beginStartedAt = Date()
        defer {
#if DEBUG
            FitMatchDebugLogger.duration(
                traceID: diagnosticTraceID,
                stage: "내 옷 선택→비교 시작",
                startedAt: beginStartedAt,
                state: "종료"
            )
#endif
        }
#if DEBUG
        FitMatchDebugLogger.flow(
            traceID: diagnosticTraceID,
            stage: "비교 시작",
            state: "요청",
            fields: [
                "DB상품UUID": authorization.target.productID.uuidString,
                "내옷UUID": authorization.reference?.closetItemID.uuidString ?? "없음",
                "비교그룹": authorization.requestedComparisonGroupCode ?? "자동",
                "허용후보사이즈수": String(authorization.authorizedCandidateSizeIDs.count)
            ]
        )
#endif
        try Task.checkCancellation()
        guard authorization.isAllowed,
              let reference = authorization.reference else {
            throw FitMatchServerAuthorityError.comparisonNotAuthorized
        }
        if !authorization.target.comparisonReadiness.isReady,
           authorization.requestedComparisonGroupCode == nil {
            throw FitMatchServerAuthorityError.comparisonNotReady(
                authorization.target.runtime.runtimeState
            )
        }
        let allowExtended = authorization.decision == .manualSelection
        let exactCandidates: VNextEligibleCandidateSizesDTO?
        if let targetVariantID = authorization.targetVariantID {
            try Task.checkCancellation()
            let value = try await remote.eligibleCandidateSizes(
                referenceClosetItemID: reference.closetItemID,
                targetProductID: authorization.target.productID,
                targetVariantID: targetVariantID,
                manualExplicit: allowExtended,
                requestedComparisonGroupCode: authorization.requestedComparisonGroupCode
            )
            try Task.checkCancellation()
#if DEBUG
            FitMatchDebugLogger.flow(
                traceID: diagnosticTraceID,
                stage: "비교 가능 사이즈 검증",
                state: "서버응답",
                fields: [
                    "허용": String(value.allowed),
                    "사유코드": value.reasonCode ?? "없음",
                    "비교그룹": authorization.requestedComparisonGroupCode ?? "자동",
                    "후보사이즈수": String(value.authorizedCandidateProductSizeIDs.count)
                ]
            )
#endif
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
        try Task.checkCancellation()
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
                candidateAuthorityFingerprint: exactCandidates?
                    .candidateAuthorityFingerprint,
                effectiveAuthorityFingerprint: exactCandidates?
                    .effectiveAuthorityFingerprint,
                personalOverrideRevision: exactCandidates?
                    .personalOverrideRevision,
                requestedComparisonGroupCode: authorization.requestedComparisonGroupCode
            )
        )
        try Task.checkCancellation()
#if DEBUG
        FitMatchDebugLogger.flow(
            traceID: diagnosticTraceID,
            stage: "비교 시작",
            state: "서버응답",
            fields: [
                "비교실행UUID": response.runID.uuidString,
                "응답상태": response.status,
                "허용": String(response.compatibility.allowed),
                "호환수준": response.compatibility.level,
                "차단사유": response.compatibility.reason ?? "없음",
                "비교그룹": authorization.requestedComparisonGroupCode ?? "자동"
            ]
        )
#endif
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
                  exact.comparisonID == response.runID,
                  Set(exact.authorizedCandidateProductSizeIDs) == Set(
                    exactCandidates?.authorizedCandidateProductSizeIDs ?? []
                  ),
                  exact.snapshot.target.variantID == authorization.targetVariantID else {
                throw FitMatchServerAuthorityError.comparisonBeginMalformed(
                    "vnext_snapshot_or_candidate_set_missing"
                )
            }
            do {
                try FitMatchVNextContractValidator.validateLiveBegin(exact)
            } catch let error as FitMatchVNextContractError {
                throw FitMatchServerAuthorityError.comparisonContractViolation(error)
            } catch {
                throw error
            }
            guard exact.resultStatus == "PENDING" else {
                throw FitMatchServerAuthorityError.comparisonAlreadyCompleted
            }
            if let requestedGroup = authorization.requestedComparisonGroupCode {
                let targetGroup = exact.snapshot.target.comparisonGroup
                let inputGroup = exact.snapshot.inputSnapshot.objectValue?[
                    "requested_comparison_group_code"
                ]?.stringValue
                let authorityGroup = exact.snapshot.authoritySnapshot.objectValue?[
                    "comparison_group_at_begin"
                ]?.objectValue?["group_code"]?.stringValue
                guard exact.snapshot.snapshotSchemaVersion == 4,
                      exact.snapshot.target.classificationSource
                        == "SESSION_USER_SELECTED",
                      targetGroup?.groupCode == requestedGroup,
                      targetGroup?.source == "SESSION_USER_SELECTED",
                      targetGroup?.authorityFingerprint
                        == exact.effectiveAuthorityFingerprint,
                      exact.effectiveAuthorityFingerprint
                        == exactCandidates?.effectiveAuthorityFingerprint,
                      exact.candidateAuthorityFingerprint
                        == exactCandidates?.candidateAuthorityFingerprint,
                      inputGroup == requestedGroup,
                      authorityGroup == requestedGroup else {
                    throw FitMatchServerAuthorityError.comparisonBeginMalformed(
                        "requested_group_authority_snapshot_mismatch"
                    )
                }
            }
            if exactCandidates?.effectiveSource == "USER_EXPLICIT" {
                guard exact.snapshot.snapshotSchemaVersion == 4,
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
        let diagnosticTraceID = FitMatchRequestTrace.context?.id ?? permit.runID
        let completionStartedAt = Date()
        defer {
#if DEBUG
            FitMatchDebugLogger.duration(
                traceID: diagnosticTraceID,
                stage: "비교 결과 저장",
                startedAt: completionStartedAt,
                state: "종료"
            )
#endif
        }
#if DEBUG
        FitMatchDebugLogger.flow(
            traceID: diagnosticTraceID,
            stage: "비교 결과 저장",
            state: "요청",
            fields: [
                "비교실행UUID": permit.runID.uuidString,
                "추천사이즈UUID": analysis.recommended.productSizeID.uuidString
            ]
        )
#endif
        try Task.checkCancellation()
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
        try Task.checkCancellation()
#if DEBUG
        FitMatchDebugLogger.flow(
            traceID: diagnosticTraceID,
            stage: "비교 결과 저장",
            state: "서버응답",
            fields: [
                "완료": String(result.completed),
                "비교실행UUID": result.comparisonID.uuidString,
                "추천사이즈UUID": result.recommendedProductSizeID.uuidString
            ]
        )
#endif
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
        expectedProductID: UUID?,
        diagnosticTraceID: UUID? = nil
    ) async throws -> PromotedObservation {
        try Task.checkCancellation()
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

        let response = try await submitProductObservationWithTransientRetry(
            observation,
            diagnosticTraceID: diagnosticTraceID
        )
        try Task.checkCancellation()
#if DEBUG
        FitMatchDebugLogger.flow(
            traceID: diagnosticTraceID,
            stage: "DB 상품 데이터 전송",
            state: "완료",
            fields: [
                "관측UUID": response.observation.observationID.uuidString,
                "관측상태": response.observation.status,
                "원본실측수": String(response.observation.rawMeasurementCount),
                "처리상태": response.processing.status,
                "DB상품UUID": response.processing.productID?.uuidString ?? "없음"
            ]
        )
#endif
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
        submittedObservationKeys.insert(observationKey(observation))
        return PromotedObservation(
            productID: productID,
            observationID: response.observation.observationID
        )
    }

    /// A lost Edge response can happen after the database has already accepted
    /// the observation. Retry only transient transport/server failures and
    /// reuse the exact frozen request so the ingestion fingerprint and
    /// `observed_at` remain unchanged. Contract/authentication failures are
    /// returned immediately instead of being hidden by a retry.
    private func submitProductObservationWithTransientRetry(
        _ observation: FitMatchProductObservationRequest,
        diagnosticTraceID: UUID? = nil
    ) async throws -> FitMatchProductObservationResponse {
        do {
            return try await remote.submitProductObservation(observation)
        } catch {
            guard Self.isTransientObservationSubmissionError(error) else {
                throw error
            }
#if DEBUG
            FitMatchDebugLogger.failure(
                traceID: diagnosticTraceID,
                stage: "DB 상품 데이터 전송",
                error: error,
                nextAction: "일시적 통신/서버 오류로 동일 요청을 1회 재시도합니다.",
                fields: ["재시도": "1/1"]
            )
#endif
            try Task.checkCancellation()
            await Task.yield()
            return try await remote.submitProductObservation(observation)
        }
    }

    nonisolated private static func isTransientObservationSubmissionError(
        _ error: Error
    ) -> Bool {
        if error is URLError {
            return true
        }
        if let functionsError = error as? FunctionsError {
            switch functionsError {
            case .relayError:
                return true
            case .httpError(let code, _):
                return code == 408 || code == 429 || (500...599).contains(code)
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return true
        }
        return (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)?.domain
            == NSURLErrorDomain
    }

    private func observationCanImproveRuntime(
        _ observation: FitMatchProductObservationRequest?,
        runtimeState: String
    ) -> Bool {
        guard let observation else { return false }
        if observation.payload.retailerAPIEvidence?.jsonValue != nil {
            return !submittedObservationKeys.contains(observationKey(observation))
        }
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

    private func observationKey(
        _ observation: FitMatchProductObservationRequest
    ) -> String {
        [
            observation.payload.source.lowercased(),
            observation.payload.externalProductID,
            observation.payload.observedAt
        ].joined(separator: "|")
    }

    private func validatedAuthority(
        _ runtime: FitMatchProductRuntimeResponse,
        request: FitMatchProductResolutionRequest,
        expectedProductID: UUID?,
        sourceObservationID: UUID? = nil
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
            runtime: runtime,
            sourceObservationID: sourceObservationID
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
        // `detailCode` on a Closet projection is an app-facing picker value
        // (for example `long_sleeve`), while the vNext runtime classification
        // carries garment identity and length on separate axes. Comparing that
        // projection with the runtime garment code (`tshirt`) rejects a valid
        // reference before the DB-authorized candidate can begin comparison.
        // Validate only like-for-like server authority axes here.
        return category == classification.categoryCode
            && reference.familyCode == classification.garmentTypeCode
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
