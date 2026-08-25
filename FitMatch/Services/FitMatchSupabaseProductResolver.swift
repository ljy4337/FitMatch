import Foundation
import Supabase

nonisolated struct FitMatchProductResolutionRequest: Codable, Equatable, Sendable {
    let source: String
    let externalProductID: String
    let productName: String
    let sourceCategoryPath: String?
    let audience: String?
    let sourceCategoryCodes: [String]?

    enum CodingKeys: String, CodingKey {
        case source
        case externalProductID = "external_product_id"
        case productName = "product_name"
        case sourceCategoryPath = "source_category_path"
        case audience
        case sourceCategoryCodes = "source_category_codes"
    }
}

nonisolated struct FitMatchDatabaseClassification: Decodable, Equatable, Sendable {
    let classificationID: UUID?
    let categoryCode: String?
    let detailCode: String?
    let familyCode: String?
    let lengthCode: String?
    let bodyLengthCode: String?
    let status: String
    let method: String?
    let confidence: Double?
    let requiresUserConfirmation: Bool
    let taxonomyPolicyVersion: String?
    let decisionVersion: String?

    enum CodingKeys: String, CodingKey {
        case classificationID = "classification_id"
        case categoryCode = "category_code"
        case detailCode = "detail_code"
        case familyCode = "family_code"
        case lengthCode = "length_code"
        case bodyLengthCode = "body_length_code"
        case status
        case method
        case confidence
        case requiresUserConfirmation = "requires_user_confirmation"
        case taxonomyPolicyVersion = "taxonomy_policy_version"
        case decisionVersion = "decision_version"
    }
}

nonisolated struct FitMatchProductResolutionResponse: Decodable, Equatable, Sendable {
    let productID: UUID?
    let intakeRequestID: UUID?
    let catalogState: String
    let categoryEvidenceMatches: Bool?
    let classification: FitMatchDatabaseClassification
    let comparisonReady: Bool

    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case intakeRequestID = "intake_request_id"
        case catalogState = "catalog_state"
        case categoryEvidenceMatches = "category_evidence_matches"
        case classification
        case comparisonReady = "comparison_ready"
    }
}

nonisolated struct FitMatchProductObservationMeasurement: Encodable, Equatable, Sendable {
    let measurementIdentity: String
    let rawCode: String?
    let rawLabel: String
    let rawValue: Double
    let rawUnit: String
    let rawRepresentation: String?
    let evidence: [String: String]

    enum CodingKeys: String, CodingKey {
        case measurementIdentity = "measurement_identity"
        case rawCode = "raw_code"
        case rawLabel = "raw_label"
        case rawValue = "raw_value"
        case rawUnit = "raw_unit"
        case rawRepresentation = "raw_representation"
        case evidence
    }
}

nonisolated struct FitMatchProductObservationSize: Encodable, Equatable, Sendable {
    let sizeIdentity: String
    let sizeLabel: String
    let normalizedSizeLabel: String
    let displayOrder: Int
    let stockStatus: String
    let measurements: [FitMatchProductObservationMeasurement]

    enum CodingKeys: String, CodingKey {
        case sizeIdentity = "size_identity"
        case sizeLabel = "size_label"
        case normalizedSizeLabel = "normalized_size_label"
        case displayOrder = "display_order"
        case stockStatus = "stock_status"
        case measurements
    }
}

nonisolated struct FitMatchProductObservationVariant: Encodable, Equatable, Sendable {
    let externalVariantID: String
    let variantName: String?
    let colorCode: String?
    let colorName: String?
    let sizes: [FitMatchProductObservationSize]

    enum CodingKeys: String, CodingKey {
        case externalVariantID = "external_variant_id"
        case variantName = "variant_name"
        case colorCode = "color_code"
        case colorName = "color_name"
        case sizes
    }
}

nonisolated struct FitMatchProductObservationPayload: Encodable, Equatable, Sendable {
    let source: String
    let externalProductID: String
    let productName: String
    let canonicalURL: String?
    let audience: String?
    let sourceCategoryPath: String?
    let sourceCategoryCodes: [String]
    let imageURL: String?
    let observedAt: String
    let rawPayload: [String: String]
    let variants: [FitMatchProductObservationVariant]

    enum CodingKeys: String, CodingKey {
        case source
        case externalProductID = "external_product_id"
        case productName = "product_name"
        case canonicalURL = "canonical_url"
        case audience
        case sourceCategoryPath = "source_category_path"
        case sourceCategoryCodes = "source_category_codes"
        case imageURL = "image_url"
        case observedAt = "observed_at"
        case rawPayload = "raw_payload"
        case variants
    }
}

nonisolated struct FitMatchProductObservationRequest: Encodable, Equatable, Sendable {
    let payload: FitMatchProductObservationPayload
}

nonisolated struct FitMatchProductObservationResponse: Decodable, Equatable, Sendable {
    struct Observation: Decodable, Equatable, Sendable {
        let observationID: UUID
        let status: String
        let rawMeasurementCount: Int

        enum CodingKeys: String, CodingKey {
            case observationID = "observation_id"
            case status
            case rawMeasurementCount = "raw_measurement_count"
        }
    }

    struct Processing: Decodable, Equatable, Sendable {
        let observationID: UUID
        let status: String
        let productID: UUID?

        enum CodingKeys: String, CodingKey {
            case observationID = "observation_id"
            case status
            case productID = "product_id"
        }
    }

    let observation: Observation
    let processing: Processing
}

nonisolated struct FitMatchClosetClassificationOverride: Encodable, Equatable, Sendable {
    let categoryCode: String
    let detailCode: String
    let familyCode: String
    let lengthCode: String?
    let reason: String?
    let evidence: [String: String]

    enum CodingKeys: String, CodingKey {
        case categoryCode = "category_code"
        case detailCode = "detail_code"
        case familyCode = "family_code"
        case lengthCode = "length_code"
        case reason
        case evidence
    }
}

nonisolated struct FitMatchRegisterClosetItemRequest: Encodable, Equatable, Sendable {
    let productID: UUID
    let productSizeID: UUID?
    let isReference: Bool
    let override: FitMatchClosetClassificationOverride?
}

nonisolated struct FitMatchClosetMeasurementRecordPayload: Codable, Equatable, Sendable {
    let value: Double
    let unit: String
    let measurementCode: String
    let displayKind: String
    let methodSource: String
    let methodProfile: String?
    let inputSource: String
    let standardVersion: String?
    let mappingVersion: String
    let rawCode: String?
    let rawLabel: String
    let rawInfo: String?
    let rawValueText: String?
    let evidenceLevel: String
    let semanticStatus: String

    enum CodingKeys: String, CodingKey {
        case value, unit
        case measurementCode = "measurement_code"
        case displayKind = "display_kind"
        case methodSource = "method_source"
        case methodProfile = "method_profile"
        case inputSource = "input_source"
        case standardVersion = "standard_version"
        case mappingVersion = "mapping_version"
        case rawCode = "raw_code"
        case rawLabel = "raw_label"
        case rawInfo = "raw_info"
        case rawValueText = "raw_value_text"
        case evidenceLevel = "evidence_level"
        case semanticStatus = "semantic_status"
    }
}

nonisolated struct FitMatchClosetItemPayload: Encodable, Equatable, Sendable {
    let productName: String
    let brand: String?
    let sizeName: String?
    let genderCode: String
    let source: String
    let categoryCode: String
    let detailCode: String
    let familyCode: String?
    let lengthCode: String?
    let bodyLengthCode: String?
    let sourceCategoryPath: String?
    let productURL: String?
    let imageURL: String?
    let measurements: [String: Double]
    let measurementRecords: [FitMatchClosetMeasurementRecordPayload]
    let fitMemo: String
    let fitPreferenceCode: String
    let satisfaction: Int
    let isReference: Bool
    let classificationVersion: String?
    let clientSnapshot: [String: String]
    let clientCreatedAt: String
    let clientUpdatedAt: String

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case brand
        case sizeName = "size_name"
        case genderCode = "gender_code"
        case source
        case categoryCode = "category_code"
        case detailCode = "detail_code"
        case familyCode = "family_code"
        case lengthCode = "length_code"
        case bodyLengthCode = "body_length_code"
        case sourceCategoryPath = "source_category_path"
        case productURL = "product_url"
        case imageURL = "image_url"
        case measurements
        case measurementRecords = "measurement_records"
        case fitMemo = "fit_memo"
        case fitPreferenceCode = "fit_preference_code"
        case satisfaction
        case isReference = "is_reference"
        case classificationVersion = "classification_version"
        case clientSnapshot = "client_snapshot"
        case clientCreatedAt = "client_created_at"
        case clientUpdatedAt = "client_updated_at"
    }
}

nonisolated struct FitMatchUpsertClosetItemRequest: Encodable, Equatable, Sendable {
    let clientItemID: UUID
    let item: FitMatchClosetItemPayload
    let productID: UUID?
    let productSizeID: UUID?
    let override: FitMatchClosetClassificationOverride?
}

nonisolated struct FitMatchUpsertClosetItemResponse: Decodable, Equatable, Sendable {
    let closetItemID: UUID
    let clientItemID: UUID
    let syncRevision: Int
    let classificationStatus: String
    let categoryCode: String
    let detailCode: String
    let familyCode: String?
    let lengthCode: String?
    let bodyLengthCode: String?
    let isReference: Bool

    enum CodingKeys: String, CodingKey {
        case closetItemID = "closet_item_id"
        case clientItemID = "client_item_id"
        case syncRevision = "sync_revision"
        case classificationStatus = "classification_status"
        case categoryCode = "category_code"
        case detailCode = "detail_code"
        case familyCode = "family_code"
        case lengthCode = "length_code"
        case bodyLengthCode = "body_length_code"
        case isReference = "is_reference"
    }
}

nonisolated struct FitMatchClosetItemRecord: Decodable, Equatable, Sendable {
    let closetItemID: UUID
    let clientItemID: UUID
    let productID: UUID?
    let externalProductID: String?
    let productAudience: String?
    let sourceCategoryCodes: [String]
    let variantID: UUID?
    let productSizeID: UUID?
    let brand: String?
    let productName: String
    let sizeName: String?
    let genderCode: String?
    let source: String
    let sourceCategoryPath: String?
    let productURL: String?
    let imageURL: String?
    let measurements: [String: Double]
    let measurementRecords: [FitMatchClosetMeasurementRecordPayload]
    let fitMemo: String
    let fitPreferenceCode: String
    let satisfaction: Int
    let isReference: Bool
    let classificationStatus: String
    let classificationSource: String?
    let categoryCode: String
    let detailCode: String
    let canonicalCategoryCode: String?
    let canonicalDetailCode: String?
    let familyCode: String?
    let lengthCode: String?
    let bodyLengthCode: String?
    let classificationSnapshot: [String: String?]
    let clientSnapshot: [String: String]
    let clientCreatedAt: String?
    let clientUpdatedAt: String?
    let syncRevision: Int
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case closetItemID = "closet_item_id"
        case clientItemID = "client_item_id"
        case productID = "product_id"
        case externalProductID = "external_product_id"
        case productAudience = "product_audience"
        case sourceCategoryCodes = "source_category_codes"
        case variantID = "variant_id"
        case productSizeID = "product_size_id"
        case brand
        case productName = "product_name"
        case sizeName = "size_name"
        case genderCode = "gender_code"
        case source
        case sourceCategoryPath = "source_category_path"
        case productURL = "product_url"
        case imageURL = "image_url"
        case measurements
        case measurementRecords = "measurement_records"
        case fitMemo = "fit_memo"
        case fitPreferenceCode = "fit_preference_code"
        case satisfaction
        case isReference = "is_reference"
        case classificationStatus = "classification_status"
        case classificationSource = "classification_source"
        case categoryCode = "category_code"
        case detailCode = "detail_code"
        case canonicalCategoryCode = "canonical_category_code"
        case canonicalDetailCode = "canonical_detail_code"
        case familyCode = "family_code"
        case lengthCode = "length_code"
        case bodyLengthCode = "body_length_code"
        case classificationSnapshot = "classification_snapshot"
        case clientSnapshot = "client_snapshot"
        case clientCreatedAt = "client_created_at"
        case clientUpdatedAt = "client_updated_at"
        case syncRevision = "sync_revision"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct FitMatchClosetItemsResponse: Decodable, Equatable, Sendable {
    let state: String
    let items: [FitMatchClosetItemRecord]
}

nonisolated struct FitMatchSetClosetReferenceResponse: Decodable, Equatable, Sendable {
    let closetItemID: UUID
    let isReference: Bool
    let syncRevision: Int

    enum CodingKeys: String, CodingKey {
        case closetItemID = "closet_item_id"
        case isReference = "is_reference"
        case syncRevision = "sync_revision"
    }
}

nonisolated struct FitMatchDeleteClosetItemResponse: Decodable, Equatable, Sendable {
    let closetItemID: UUID
    let deletedAt: String

    enum CodingKeys: String, CodingKey {
        case closetItemID = "closet_item_id"
        case deletedAt = "deleted_at"
    }
}

nonisolated struct FitMatchRuntimeProduct: Decodable, Equatable, Sendable {
    let productID: UUID
    let source: String
    let externalProductID: String
    let productName: String
    let canonicalURL: String?
    let audience: String?
    let sourceCategoryPath: String?
    let sourceCategoryCodes: [String]
    let imageURL: String?
    let lifecycleStatus: String
    let inputFingerprint: String

    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case source
        case externalProductID = "external_product_id"
        case productName = "product_name"
        case canonicalURL = "canonical_url"
        case audience
        case sourceCategoryPath = "source_category_path"
        case sourceCategoryCodes = "source_category_codes"
        case imageURL = "image_url"
        case lifecycleStatus = "lifecycle_status"
        case inputFingerprint = "input_fingerprint"
    }
}

nonisolated struct FitMatchRuntimeMeasurement: Decodable, Equatable, Sendable {
    let measurementCode: String?
    let rawLabel: String
    let rawValue: Double
    let rawUnit: String
    let normalizedValue: Double?
    let normalizedUnit: String?
    let comparisonBasis: String?
    let isComparable: Bool
    let exclusionReason: String?
    let policyVersion: String?

    enum CodingKeys: String, CodingKey {
        case measurementCode = "measurement_code"
        case rawLabel = "raw_label"
        case rawValue = "raw_value"
        case rawUnit = "raw_unit"
        case normalizedValue = "normalized_value"
        case normalizedUnit = "normalized_unit"
        case comparisonBasis = "comparison_basis"
        case isComparable = "is_comparable"
        case exclusionReason = "exclusion_reason"
        case policyVersion = "policy_version"
    }
}

nonisolated struct FitMatchRuntimeSize: Decodable, Equatable, Sendable {
    let productSizeID: UUID
    let externalSizeID: String?
    let sizeLabel: String
    let normalizedSizeLabel: String
    let displayOrder: Int
    let stockStatus: String?
    let measurements: [FitMatchRuntimeMeasurement]

    enum CodingKeys: String, CodingKey {
        case productSizeID = "product_size_id"
        case externalSizeID = "external_size_id"
        case sizeLabel = "size_label"
        case normalizedSizeLabel = "normalized_size_label"
        case displayOrder = "display_order"
        case stockStatus = "stock_status"
        case measurements
    }
}

nonisolated struct FitMatchRuntimeVariant: Decodable, Equatable, Sendable {
    let variantID: UUID
    let externalVariantID: String?
    let variantName: String?
    let colorCode: String?
    let colorName: String?
    let sizes: [FitMatchRuntimeSize]

    enum CodingKeys: String, CodingKey {
        case variantID = "variant_id"
        case externalVariantID = "external_variant_id"
        case variantName = "variant_name"
        case colorCode = "color_code"
        case colorName = "color_name"
        case sizes
    }
}

nonisolated struct FitMatchProductRuntimeResponse: Decodable, Equatable, Sendable {
    let runtimeState: String
    let comparisonReady: Bool
    let product: FitMatchRuntimeProduct
    let classification: FitMatchDatabaseClassification?
    let variants: [FitMatchRuntimeVariant]

    enum CodingKeys: String, CodingKey {
        case runtimeState = "runtime_state"
        case comparisonReady = "comparison_ready"
        case product
        case classification
        case variants
    }
}

nonisolated struct FitMatchDatabaseCompatibility: Decodable, Equatable, Sendable {
    let allowed: Bool
    let level: String
    let reason: String?
    let excludedMeasurements: [String]
    let minimumCommonMeasurements: Int?

    enum CodingKeys: String, CodingKey {
        case allowed
        case level
        case reason
        case excludedMeasurements = "excluded_measurements"
        case minimumCommonMeasurements = "minimum_common_measurements"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        allowed = try container.decodeIfPresent(Bool.self, forKey: .allowed) ?? false
        level = try container.decodeIfPresent(String.self, forKey: .level) ?? "incompatible"
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        excludedMeasurements = try container.decodeIfPresent(
            [String].self,
            forKey: .excludedMeasurements
        ) ?? []
        minimumCommonMeasurements = try container.decodeIfPresent(
            Int.self,
            forKey: .minimumCommonMeasurements
        )
    }
}

nonisolated struct FitMatchReferenceCandidate: Decodable, Equatable, Sendable {
    let closetItemID: UUID
    let productName: String
    let sizeName: String?
    let isReference: Bool
    let automaticReady: Bool
    let manualReady: Bool
    let measurementOverlapCount: Int
    let automaticCompatibility: FitMatchDatabaseCompatibility
    let manualCompatibility: FitMatchDatabaseCompatibility

    enum CodingKeys: String, CodingKey {
        case closetItemID = "closet_item_id"
        case productName = "product_name"
        case sizeName = "size_name"
        case isReference = "is_reference"
        case automaticReady = "automatic_ready"
        case manualReady = "manual_ready"
        case measurementOverlapCount = "measurement_overlap_count"
        case automaticCompatibility = "automatic_compatibility"
        case manualCompatibility = "manual_compatibility"
    }
}

nonisolated struct FitMatchReferenceCandidatesResponse: Decodable, Equatable, Sendable {
    let state: String
    let automaticCount: Int
    let manualCount: Int
    let structuralCount: Int
    let candidates: [FitMatchReferenceCandidate]
    let policyVersion: String?

    enum CodingKeys: String, CodingKey {
        case state
        case automaticCount = "automatic_count"
        case manualCount = "manual_count"
        case structuralCount = "structural_count"
        case candidates
        case policyVersion = "policy_version"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(String.self, forKey: .state)
        automaticCount = try container.decodeIfPresent(Int.self, forKey: .automaticCount) ?? 0
        manualCount = try container.decodeIfPresent(Int.self, forKey: .manualCount) ?? 0
        structuralCount = try container.decodeIfPresent(Int.self, forKey: .structuralCount) ?? 0
        candidates = try container.decodeIfPresent([FitMatchReferenceCandidate].self, forKey: .candidates) ?? []
        policyVersion = try container.decodeIfPresent(String.self, forKey: .policyVersion)
    }
}

nonisolated struct FitMatchBeginComparisonRequest: Encodable, Equatable, Sendable {
    let referenceItemID: UUID
    let targetProductID: UUID
    let allowExtended: Bool
    let clientHistoryID: UUID
}

nonisolated struct FitMatchBeginComparisonResponse: Decodable, Equatable, Sendable {
    let runID: UUID
    let status: String
    let compatibility: FitMatchDatabaseCompatibility

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case status
        case compatibility
    }
}

nonisolated struct FitMatchComparisonMeasurementSubmission: Encodable, Equatable, Sendable {
    let measurementCode: String
    let referenceValue: Double?
    let targetValue: Double?
    let signedDifference: Double?
    let absoluteDifference: Double?
    let weight: Double?
    let included: Bool
    let exclusionReason: String?
    let evidence: [String: String]

    enum CodingKeys: String, CodingKey {
        case measurementCode = "measurement_code"
        case referenceValue = "reference_value"
        case targetValue = "target_value"
        case signedDifference = "signed_difference"
        case absoluteDifference = "absolute_difference"
        case weight
        case included
        case exclusionReason = "exclusion_reason"
        case evidence
    }
}

nonisolated struct FitMatchComparisonResultSubmission: Encodable, Equatable, Sendable {
    let targetSizeID: UUID
    let similarityScore: Double?
    let rank: Int?
    let confidenceCode: String?
    let coverageRatio: Double
    let dataQualityScore: Double
    let confidenceScore: Double
    let qualityMetricsVersion: String
    let isRecommended: Bool
    let isComparable: Bool
    let exclusionReason: String?
    let snapshot: [String: String]
    let measurements: [FitMatchComparisonMeasurementSubmission]

    enum CodingKeys: String, CodingKey {
        case targetSizeID = "target_size_id"
        case similarityScore = "similarity_score"
        case rank
        case confidenceCode = "confidence_code"
        case coverageRatio = "coverage_ratio"
        case dataQualityScore = "data_quality_score"
        case confidenceScore = "confidence_score"
        case qualityMetricsVersion = "quality_metrics_version"
        case isRecommended = "is_recommended"
        case isComparable = "is_comparable"
        case exclusionReason = "exclusion_reason"
        case snapshot
        case measurements
    }
}

nonisolated struct FitMatchCompleteComparisonRequest: Encodable, Equatable, Sendable {
    let runID: UUID
    let results: [FitMatchComparisonResultSubmission]
    let summary: [String: String]
}

nonisolated struct FitMatchCompleteComparisonResponse: Decodable, Equatable, Sendable {
    let runID: UUID
    let status: String
    let resultCount: Int

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case status
        case resultCount = "result_count"
    }
}

struct FitMatchLocalClassificationSnapshot: Equatable {
    let categoryCode: String?
    let detailCode: String?
    let familyCode: String?
    let lengthCode: String?
    let requiresUserConfirmation: Bool

    init(_ classification: ParsedClosetClassification?) {
        categoryCode = classification?.categoryCode
        detailCode = classification?.detailCode
        familyCode = classification?.garmentFamily.rawValue
        lengthCode = classification?.lengthType.rawValue
        requiresUserConfirmation = classification?.isValid != true
    }

    func matches(_ database: FitMatchDatabaseClassification) -> Bool {
        categoryCode == database.categoryCode
            && detailCode == database.detailCode
            && familyCode == database.familyCode
            && lengthCode == database.lengthCode
            && requiresUserConfirmation == database.requiresUserConfirmation
    }
}

enum FitMatchDatabaseShadowState: Equatable {
    case idle
    case checking
    case skipped
    case matched(FitMatchProductResolutionResponse)
    case mismatch(FitMatchProductResolutionResponse, FitMatchLocalClassificationSnapshot)
    case reviewRequired(FitMatchProductResolutionResponse)
    case unavailable
}

protocol FitMatchProductResolving {
    func resolve(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductResolutionResponse
}

protocol FitMatchProductObservationSubmitting {
    func submitProductObservation(_ request: FitMatchProductObservationRequest) async throws
        -> FitMatchProductObservationResponse
}

protocol FitMatchDatabaseDomainServicing:
    FitMatchProductResolving,
    FitMatchProductObservationSubmitting {
    func fetchProductRuntime(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductRuntimeResponse
    func registerClosetItem(_ request: FitMatchRegisterClosetItemRequest) async throws -> UUID
    func upsertClosetItem(_ request: FitMatchUpsertClosetItemRequest) async throws
        -> FitMatchUpsertClosetItemResponse
    func listClosetItems() async throws -> FitMatchClosetItemsResponse
    func setClosetReference(closetItemID: UUID, isReference: Bool) async throws
        -> FitMatchSetClosetReferenceResponse
    func deleteClosetItem(closetItemID: UUID) async throws
        -> FitMatchDeleteClosetItemResponse
    func findReferenceCandidates(targetProductID: UUID) async throws
        -> FitMatchReferenceCandidatesResponse
    func beginComparison(_ request: FitMatchBeginComparisonRequest) async throws
        -> FitMatchBeginComparisonResponse
    func completeComparison(_ request: FitMatchCompleteComparisonRequest) async throws
        -> FitMatchCompleteComparisonResponse
}

enum FitMatchSupabaseProductResolverError: LocalizedError {
    case notConfigured
    case authenticationRequired

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "FitMatch DB 연결 설정이 없습니다."
        case .authenticationRequired:
            return "로그인이 필요한 기능입니다."
        }
    }
}

nonisolated private struct FitMatchResolveProductParameters: Encodable, Sendable {
    let pPayload: FitMatchProductResolutionRequest

    enum CodingKeys: String, CodingKey {
        case pPayload = "p_payload"
    }
}

nonisolated private struct FitMatchRegisterClosetItemParameters: Encodable, Sendable {
    let pProductID: UUID
    let pProductSizeID: UUID?
    let pIsReference: Bool
    let pOverride: FitMatchClosetClassificationOverride?

    enum CodingKeys: String, CodingKey {
        case pProductID = "p_product_id"
        case pProductSizeID = "p_product_size_id"
        case pIsReference = "p_is_reference"
        case pOverride = "p_override"
    }
}

nonisolated private struct FitMatchUpsertClosetItemParameters: Encodable, Sendable {
    let pClientItemID: UUID
    let pItem: FitMatchClosetItemPayload
    let pProductID: UUID?
    let pProductSizeID: UUID?
    let pOverride: FitMatchClosetClassificationOverride?

    enum CodingKeys: String, CodingKey {
        case pClientItemID = "p_client_item_id"
        case pItem = "p_item"
        case pProductID = "p_product_id"
        case pProductSizeID = "p_product_size_id"
        case pOverride = "p_override"
    }
}

nonisolated private struct FitMatchSetClosetReferenceParameters: Encodable, Sendable {
    let pClosetItemID: UUID
    let pIsReference: Bool

    enum CodingKeys: String, CodingKey {
        case pClosetItemID = "p_closet_item_id"
        case pIsReference = "p_is_reference"
    }
}

nonisolated private struct FitMatchDeleteClosetItemParameters: Encodable, Sendable {
    let pClosetItemID: UUID

    enum CodingKeys: String, CodingKey {
        case pClosetItemID = "p_closet_item_id"
    }
}

nonisolated private struct FitMatchGetProductRuntimeParameters: Encodable, Sendable {
    let pPayload: FitMatchProductResolutionRequest

    enum CodingKeys: String, CodingKey {
        case pPayload = "p_payload"
    }
}

nonisolated private struct FitMatchFindReferenceCandidatesParameters: Encodable, Sendable {
    let pTargetProductID: UUID

    enum CodingKeys: String, CodingKey {
        case pTargetProductID = "p_target_product_id"
    }
}

nonisolated private struct FitMatchBeginComparisonParameters: Encodable, Sendable {
    let pReferenceItemID: UUID
    let pTargetProductID: UUID
    let pAllowExtended: Bool
    let pClientHistoryID: UUID

    enum CodingKeys: String, CodingKey {
        case pReferenceItemID = "p_reference_item_id"
        case pTargetProductID = "p_target_product_id"
        case pAllowExtended = "p_allow_extended"
        case pClientHistoryID = "p_client_history_id"
    }
}

nonisolated private struct FitMatchComparisonResultPayload: Encodable, Sendable {
    let results: [FitMatchComparisonResultSubmission]
    let summary: [String: String]
}

nonisolated private struct FitMatchCompleteComparisonParameters: Encodable, Sendable {
    let pRunID: UUID
    let pResultPayload: FitMatchComparisonResultPayload

    enum CodingKeys: String, CodingKey {
        case pRunID = "p_run_id"
        case pResultPayload = "p_result_payload"
    }
}

actor FitMatchSupabaseDomainClient: FitMatchDatabaseDomainServicing {
    static let shared = FitMatchSupabaseDomainClient()

    private let client: SupabaseClient?

    init(configuration: (url: URL, publishableKey: String)? = nil) {
        if let configuration {
            client = SupabaseClient(
                supabaseURL: configuration.url,
                supabaseKey: configuration.publishableKey
            )
        } else if FitMatchSupabaseConfiguration.live(requiresDatabaseShadow: true) != nil {
            client = FitMatchSupabaseClientProvider.shared
        } else {
            client = nil
        }
    }

    func resolve(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductResolutionResponse {
        let client = try await authenticatedClient()
        return try await client
            .rpc(
                "fitmatch_resolve_product",
                params: FitMatchResolveProductParameters(pPayload: request)
            )
            .execute()
            .value
    }

    func submitProductObservation(_ request: FitMatchProductObservationRequest) async throws
        -> FitMatchProductObservationResponse {
        let client = try await authenticatedClient()
        return try await client.functions.invoke(
            "product-observation",
            options: FunctionInvokeOptions(body: request)
        )
    }

    func registerClosetItem(_ request: FitMatchRegisterClosetItemRequest) async throws -> UUID {
        let client = try await authenticatedClient()
        return try await client
            .rpc(
                "fitmatch_register_closet_item",
                params: FitMatchRegisterClosetItemParameters(
                    pProductID: request.productID,
                    pProductSizeID: request.productSizeID,
                    pIsReference: request.isReference,
                    pOverride: request.override
                )
            )
            .execute()
            .value
    }

    func upsertClosetItem(_ request: FitMatchUpsertClosetItemRequest) async throws
        -> FitMatchUpsertClosetItemResponse {
        let client = try await authenticatedClient()
        return try await client
            .rpc(
                "fitmatch_upsert_closet_item",
                params: FitMatchUpsertClosetItemParameters(
                    pClientItemID: request.clientItemID,
                    pItem: request.item,
                    pProductID: request.productID,
                    pProductSizeID: request.productSizeID,
                    pOverride: request.override
                )
            )
            .execute()
            .value
    }

    func listClosetItems() async throws -> FitMatchClosetItemsResponse {
        let client = try await authenticatedClient()
        return try await client
            .rpc("fitmatch_list_closet_items")
            .execute()
            .value
    }

    func setClosetReference(closetItemID: UUID, isReference: Bool) async throws
        -> FitMatchSetClosetReferenceResponse {
        let client = try await authenticatedClient()
        return try await client
            .rpc(
                "fitmatch_set_closet_reference",
                params: FitMatchSetClosetReferenceParameters(
                    pClosetItemID: closetItemID,
                    pIsReference: isReference
                )
            )
            .execute()
            .value
    }

    func deleteClosetItem(closetItemID: UUID) async throws
        -> FitMatchDeleteClosetItemResponse {
        let client = try await authenticatedClient()
        return try await client
            .rpc(
                "fitmatch_delete_closet_item",
                params: FitMatchDeleteClosetItemParameters(
                    pClosetItemID: closetItemID
                )
            )
            .execute()
            .value
    }

    func fetchProductRuntime(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductRuntimeResponse {
        let client = try await authenticatedClient()
        return try await client
            .rpc(
                "fitmatch_get_product_runtime",
                params: FitMatchGetProductRuntimeParameters(pPayload: request)
            )
            .execute()
            .value
    }

    func findReferenceCandidates(targetProductID: UUID) async throws
        -> FitMatchReferenceCandidatesResponse {
        let client = try await authenticatedClient()
        return try await client
            .rpc(
                "fitmatch_find_reference_candidates",
                params: FitMatchFindReferenceCandidatesParameters(
                    pTargetProductID: targetProductID
                )
            )
            .execute()
            .value
    }

    func beginComparison(_ request: FitMatchBeginComparisonRequest) async throws
        -> FitMatchBeginComparisonResponse {
        let client = try await authenticatedClient()
        return try await client
            .rpc(
                "fitmatch_begin_comparison",
                params: FitMatchBeginComparisonParameters(
                    pReferenceItemID: request.referenceItemID,
                    pTargetProductID: request.targetProductID,
                    pAllowExtended: request.allowExtended,
                    pClientHistoryID: request.clientHistoryID
                )
            )
            .execute()
            .value
    }

    func completeComparison(_ request: FitMatchCompleteComparisonRequest) async throws
        -> FitMatchCompleteComparisonResponse {
        let client = try await authenticatedClient()
        return try await client
            .rpc(
                "fitmatch_complete_comparison",
                params: FitMatchCompleteComparisonParameters(
                    pRunID: request.runID,
                    pResultPayload: FitMatchComparisonResultPayload(
                        results: request.results,
                        summary: request.summary
                    )
                )
            )
            .execute()
            .value
    }

    private func authenticatedClient() async throws -> SupabaseClient {
        guard let client else {
            throw FitMatchSupabaseProductResolverError.notConfigured
        }
        do {
            _ = try await client.auth.session
        } catch {
            throw FitMatchSupabaseProductResolverError.authenticationRequired
        }
        return client
    }
}

typealias FitMatchSupabaseProductResolver = FitMatchSupabaseDomainClient

extension ParsedProductInfo {
    var usesStructuredCategoryAsCanonicalSource: Bool {
        sourceName.localizedCaseInsensitiveContains("zara")
    }

    func fitMatchDatabaseResolutionRequest() -> FitMatchProductResolutionRequest? {
        guard let productID = productID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !productID.isEmpty,
              !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let source: String
        if sourceName.localizedCaseInsensitiveContains("유니클로") {
            source = "uniqlo"
        } else if sourceName.localizedCaseInsensitiveContains("무신사") {
            source = "musinsa"
        } else if sourceName.localizedCaseInsensitiveContains("zara") || sourceName.localizedCaseInsensitiveContains("자라") {
            source = "zara"
        } else if sourceName.localizedCaseInsensitiveContains("cos") {
            source = "cos"
        } else {
            return nil
        }
        let metadata = productMetadata
        let path = sourceCategoryPath
            ?? metadata.sourceCategoryPath
            ?? metadata.baseCategoryFullPath
        let codes = [
            metadata.categoryDepth1Code,
            metadata.categoryDepth2Code,
            metadata.categoryDepth3Code,
            metadata.categoryDepth4Code
        ].compactMap { value -> String? in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return value
        }
        let audience = metadata.genderCodes.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        return FitMatchProductResolutionRequest(
            source: source,
            externalProductID: productID,
            productName: productName.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceCategoryPath: path?.trimmingCharacters(in: .whitespacesAndNewlines),
            audience: audience?.isEmpty == false ? audience : nil,
            sourceCategoryCodes: codes.isEmpty ? nil : codes
        )
    }

    func fitMatchLocalClassificationSnapshot() -> FitMatchLocalClassificationSnapshot {
        let metadata = productMetadata
        let classification = ParsedClosetClassification.resolve(
            category: category,
            detailCategory: detailCategory,
            sourceDepths: [
                sourceCategoryDepth1 ?? metadata.sourceCategoryDepth1,
                sourceCategoryDepth2 ?? metadata.sourceCategoryDepth2,
                sourceCategoryDepth3 ?? metadata.sourceCategoryDepth3,
                sourceCategoryDepth4 ?? metadata.sourceCategoryDepth4
            ],
            sourcePath: sourceCategoryPath ?? metadata.sourceCategoryPath ?? metadata.baseCategoryFullPath,
            productName: usesStructuredCategoryAsCanonicalSource ? "" : productName
        )
        return FitMatchLocalClassificationSnapshot(classification)
    }

    func fitMatchProductObservationRequest(
        observedAt: Date = Date()
    ) -> FitMatchProductObservationRequest? {
        guard let resolution = fitMatchDatabaseResolutionRequest() else { return nil }
        let metadata = productMetadata
        let classificationSafetyAudit = ParsedClosetClassification.auditExplicitContradictions(
            category: category,
            detailCategory: detailCategory,
            sourceDepths: [
                sourceCategoryDepth1 ?? metadata.sourceCategoryDepth1,
                sourceCategoryDepth2 ?? metadata.sourceCategoryDepth2,
                sourceCategoryDepth3 ?? metadata.sourceCategoryDepth3,
                sourceCategoryDepth4 ?? metadata.sourceCategoryDepth4
            ],
            sourcePath: sourceCategoryPath
                ?? metadata.sourceCategoryPath
                ?? metadata.baseCategoryFullPath,
            productName: productName
        )
        let color = metadata.checkedColorName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerVariantID = metadata.externalVariantID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let variantID: String
        if resolution.source == "zara", providerVariantID?.isEmpty == false {
            variantID = providerVariantID!
        } else {
            variantID = color?.isEmpty == false ? color! : "__default__"
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let observationSizes = sizes.enumerated().compactMap { index, size -> FitMatchProductObservationSize? in
            let label = size.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { return nil }
            let measurements = size.measurementRecords.enumerated().compactMap {
                measurementIndex,
                measurement -> FitMatchProductObservationMeasurement? in
                guard measurement.value.isFinite, measurement.value > 0 else { return nil }
                let rawLabel = measurement.rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rawLabel.isEmpty else { return nil }
                let trimmedRawCode = measurement.rawCode?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let identity = trimmedRawCode?.isEmpty == false
                    ? trimmedRawCode!
                    : "\(measurement.measurementCode.rawValue):\(measurementIndex)"
                return FitMatchProductObservationMeasurement(
                    measurementIdentity: identity,
                    rawCode: trimmedRawCode?.isEmpty == false ? trimmedRawCode : nil,
                    rawLabel: rawLabel,
                    rawValue: measurement.value,
                    rawUnit: measurement.unit.rawValue,
                    rawRepresentation: measurement.rawInfo.flatMap {
                        let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        return value.isEmpty ? nil : value
                    },
                    evidence: [
                        "method_source": measurement.methodSource,
                        "method_profile": measurement.methodProfile ?? "",
                        "input_source": measurement.inputSource.rawValue,
                        "mapping_version": measurement.mappingVersion,
                        "evidence_level": measurement.evidenceLevel.rawValue,
                        "semantic_status": measurement.semanticStatus.rawValue,
                        "raw_value_text": measurement.rawValueText ?? ""
                    ]
                )
            }
            return FitMatchProductObservationSize(
                sizeIdentity: ParsedProductSizeNormalizer.normalizedSizeKey(for: label),
                sizeLabel: label,
                normalizedSizeLabel: SizeTokenNormalizer.displayName(for: label),
                displayOrder: index,
                stockStatus: "unknown",
                measurements: measurements
            )
        }

        let conflictEvidence = classificationSafetyAudit.conflicts.map {
            "\($0.dimension.rawValue)=\($0.trustedValue)->\($0.explicitValue)"
        }.joined(separator: ";")
        let parserFieldSourcesJSON: String = {
            guard let fieldSources = parserProvenance?.fieldSources,
                  JSONSerialization.isValidJSONObject(fieldSources),
                  let data = try? JSONSerialization.data(
                    withJSONObject: fieldSources,
                    options: [.sortedKeys]
                  ),
                  let value = String(data: data, encoding: .utf8) else {
                return "{}"
            }
            return value
        }()
        let rawPayload: [String: String] = [
            "observation_contract": "ios-parser-observation-v1",
            "parser_provenance_available": parserProvenance == nil ? "false" : "true",
            "parser_provenance_contract": parserProvenance.map { _ in
                ProductParserProvenance.contractVersion
            } ?? "legacy_unavailable",
            "parser_code": parserProvenance?.parserCode ?? "legacy_unknown",
            "parser_version": parserProvenance?.parserVersion ?? "not_declared",
            "parser_field_sources": parserFieldSourcesJSON,
            "source_name": sourceName,
            "brand_name": brandName,
            "measurement_availability": measurementAvailability.rawValue,
            "parser_notice": parserNotice ?? "",
            "style_number": metadata.styleNo ?? "",
            "external_variant_id": metadata.externalVariantID ?? "",
            "external_product_reference": metadata.externalProductReference ?? "",
            "internal_product_id": resolution.source == "zara" ? resolution.externalProductID : "",
            "checked_size_name": metadata.checkedSizeName ?? "",
            "price": price.map(String.init) ?? "",
            "local_classification_conflict": classificationSafetyAudit.requiresReview ? "true" : "false",
            "local_classification_conflict_dimensions": classificationSafetyAudit.conflicts
                .map(\.dimension.rawValue)
                .joined(separator: ","),
            "local_classification_conflict_evidence": conflictEvidence,
            "local_classification_safety_policy_version": ParsedClosetClassificationSafetyAudit.policyVersion
        ]
        return FitMatchProductObservationRequest(
            payload: FitMatchProductObservationPayload(
                source: resolution.source,
                externalProductID: resolution.externalProductID,
                productName: resolution.productName,
                canonicalURL: canonicalURLString ?? sourceURL.absoluteString,
                audience: resolution.audience,
                sourceCategoryPath: resolution.sourceCategoryPath,
                sourceCategoryCodes: resolution.sourceCategoryCodes ?? [],
                imageURL: imageURLString,
                observedAt: formatter.string(from: observedAt),
                rawPayload: rawPayload,
                variants: [
                    FitMatchProductObservationVariant(
                        externalVariantID: variantID,
                        variantName: color,
                        colorCode: color,
                        colorName: color,
                        sizes: observationSizes
                    )
                ]
            )
        )
    }
}
