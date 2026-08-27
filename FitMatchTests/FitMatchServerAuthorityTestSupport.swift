import Foundation
@testable import FitMatch

/// Offline server-v4 echo used by parser/state tests whose subject is not the
/// classification contract itself. It keeps those tests deterministic while
/// preserving the production requirement that a successful sourced load must
/// obtain a confirmed server authority before it can compare.
actor FitMatchEchoServerAuthorityRemote: FitMatchServerAuthorityRemoteServicing {
    private let categoryCode: String
    private let detailCode: String
    private let familyCode: String
    private let lengthCode: String?
    private let classificationID = UUID(
        uuidString: "90000000-0000-4000-8000-000000000004"
    )!
    private var productIDs: [String: UUID] = [:]

    init(
        categoryCode: String = "tops",
        detailCode: String = "short_sleeve",
        familyCode: String = "tshirt",
        lengthCode: String? = "short_sleeve"
    ) {
        self.categoryCode = categoryCode
        self.detailCode = detailCode
        self.familyCode = familyCode
        self.lengthCode = lengthCode
    }

    func resolve(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductResolutionResponse {
        let productID = productID(for: request.externalProductID)
        return FitMatchProductResolutionResponse(
            productID: productID,
            intakeRequestID: nil,
            catalogState: "current",
            categoryEvidenceMatches: true,
            authorityPersisted: true,
            classification: classification(),
            comparisonReady: true
        )
    }

    func fetchProductRuntime(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductRuntimeResponse {
        FitMatchProductRuntimeResponse(
            runtimeState: "ready",
            comparisonReady: true,
            product: FitMatchRuntimeProduct(
                productID: productID(for: request.externalProductID),
                source: request.source,
                externalProductID: request.externalProductID,
                productName: request.productName,
                canonicalURL: nil,
                audience: request.audience,
                sourceCategoryPath: request.sourceCategoryPath,
                sourceCategoryCodes: request.sourceCategoryCodes ?? [],
                imageURL: nil,
                lifecycleStatus: "active",
                inputFingerprint: "offline-test"
            ),
            classification: classification(),
            variants: []
        )
    }

    func submitProductObservation(_ request: FitMatchProductObservationRequest) async throws
        -> FitMatchProductObservationResponse {
        throw StubError.unexpectedObservation
    }

    func listClosetItems() async throws -> FitMatchClosetItemsResponse {
        .init(state: "ready", items: [])
    }

    func findReferenceCandidates(targetProductID: UUID) async throws
        -> FitMatchReferenceCandidatesResponse {
        throw StubError.unexpectedCandidateLookup
    }

    private func productID(for externalProductID: String) -> UUID {
        if let existing = productIDs[externalProductID] { return existing }
        let created = UUID()
        productIDs[externalProductID] = created
        return created
    }

    private func classification() -> FitMatchDatabaseClassification {
        FitMatchDatabaseClassification(
            classificationID: classificationID,
            categoryCode: categoryCode,
            detailCode: detailCode,
            garmentTypeCode: familyCode,
            familyCode: familyCode,
            lengthCode: lengthCode,
            bodyLengthCode: nil,
            status: "confirmed",
            method: "offline_server_v4_fixture",
            authorityStatus: "verified",
            confidence: 1,
            requiresUserConfirmation: false,
            taxonomyPolicyVersion: "db-classifier-2026-08-26-final",
            decisionVersion: "offline-server-authority-test"
        )
    }

    enum StubError: Error {
        case unexpectedObservation
        case unexpectedCandidateLookup
    }
}
