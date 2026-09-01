import Foundation
import Supabase

nonisolated struct FitMatchProductResolutionRequest: Codable, Equatable, Sendable {
    let source: String
    let externalProductID: String
    let productName: String
    let sourceCategoryPath: String?
    let audience: String?
    let sourceCategoryCodes: [String]?
    let structuredFacts: [String: String]

    init(
        source: String,
        externalProductID: String,
        productName: String,
        sourceCategoryPath: String?,
        audience: String?,
        sourceCategoryCodes: [String]?,
        structuredFacts: [String: String] = [:]
    ) {
        self.source = source
        self.externalProductID = externalProductID
        self.productName = productName
        self.sourceCategoryPath = sourceCategoryPath
        self.audience = FitMatchCanonicalAudience.code(from: audience)
        self.sourceCategoryCodes = sourceCategoryCodes
        self.structuredFacts = structuredFacts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(String.self, forKey: .source)
        externalProductID = try container.decode(String.self, forKey: .externalProductID)
        productName = try container.decode(String.self, forKey: .productName)
        sourceCategoryPath = try container.decodeIfPresent(String.self, forKey: .sourceCategoryPath)
        audience = FitMatchCanonicalAudience.code(
            from: try container.decodeIfPresent(String.self, forKey: .audience)
        )
        sourceCategoryCodes = try container.decodeIfPresent([String].self, forKey: .sourceCategoryCodes)
        structuredFacts = try container.decodeIfPresent(
            [String: String].self,
            forKey: .structuredFacts
        ) ?? [:]
    }

    enum CodingKeys: String, CodingKey {
        case source
        case externalProductID = "external_product_id"
        case productName = "product_name"
        case sourceCategoryPath = "source_category_path"
        case audience
        case sourceCategoryCodes = "source_category_codes"
        case structuredFacts = "structured_facts"
    }
}

nonisolated struct FitMatchDatabaseClassification: Decodable, Equatable, Sendable {
    let classificationID: UUID?
    let categoryCode: String?
    let detailCode: String?
    let garmentTypeCode: String?
    let familyCode: String?
    let lengthCode: String?
    let bodyLengthCode: String?
    let status: String
    let method: String?
    let authorityStatus: String?
    let confidence: Double?
    let requiresUserConfirmation: Bool
    let taxonomyPolicyVersion: String?
    let decisionVersion: String?

    init(
        classificationID: UUID?,
        categoryCode: String?,
        detailCode: String?,
        garmentTypeCode: String? = nil,
        familyCode: String?,
        lengthCode: String?,
        bodyLengthCode: String?,
        status: String,
        method: String?,
        authorityStatus: String? = nil,
        confidence: Double?,
        requiresUserConfirmation: Bool,
        taxonomyPolicyVersion: String?,
        decisionVersion: String?
    ) {
        self.classificationID = classificationID
        self.categoryCode = categoryCode
        self.detailCode = detailCode
        self.garmentTypeCode = garmentTypeCode
        self.familyCode = familyCode
        self.lengthCode = lengthCode
        self.bodyLengthCode = bodyLengthCode
        self.status = status
        self.method = method
        self.authorityStatus = authorityStatus
        self.confidence = confidence
        self.requiresUserConfirmation = requiresUserConfirmation
        self.taxonomyPolicyVersion = taxonomyPolicyVersion
        self.decisionVersion = decisionVersion
    }

    enum CodingKeys: String, CodingKey {
        case classificationID = "classification_id"
        case categoryCode = "category_code"
        case detailCode = "detail_code"
        case garmentTypeCode = "garment_type_code"
        case familyCode = "family_code"
        case lengthCode = "length_code"
        case bodyLengthCode = "body_length_code"
        case status
        case method
        case authorityStatus = "authority_status"
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
    let authorityPersisted: Bool?
    let classification: FitMatchDatabaseClassification
    let comparisonReady: Bool

    init(
        productID: UUID?,
        intakeRequestID: UUID?,
        catalogState: String,
        categoryEvidenceMatches: Bool?,
        authorityPersisted: Bool? = nil,
        classification: FitMatchDatabaseClassification,
        comparisonReady: Bool
    ) {
        self.productID = productID
        self.intakeRequestID = intakeRequestID
        self.catalogState = catalogState
        self.categoryEvidenceMatches = categoryEvidenceMatches
        self.authorityPersisted = authorityPersisted
        self.classification = classification
        self.comparisonReady = comparisonReady
    }

    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case intakeRequestID = "intake_request_id"
        case catalogState = "catalog_state"
        case categoryEvidenceMatches = "category_evidence_matches"
        case authorityPersisted = "authority_persisted"
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
    let availabilityObservedAt: String?
    let availabilityValidUntil: String?
    let availabilityEvidence: [String: String]
    let measurements: [FitMatchProductObservationMeasurement]

    init(
        sizeIdentity: String,
        sizeLabel: String,
        normalizedSizeLabel: String,
        displayOrder: Int,
        stockStatus: String,
        availabilityObservedAt: String? = nil,
        availabilityValidUntil: String? = nil,
        availabilityEvidence: [String: String] = [:],
        measurements: [FitMatchProductObservationMeasurement]
    ) {
        self.sizeIdentity = sizeIdentity
        self.sizeLabel = sizeLabel
        self.normalizedSizeLabel = normalizedSizeLabel
        self.displayOrder = displayOrder
        self.stockStatus = stockStatus
        self.availabilityObservedAt = availabilityObservedAt
        self.availabilityValidUntil = availabilityValidUntil
        self.availabilityEvidence = availabilityEvidence
        self.measurements = measurements
    }

    enum CodingKeys: String, CodingKey {
        case sizeIdentity = "size_identity"
        case sizeLabel = "size_label"
        case normalizedSizeLabel = "normalized_size_label"
        case displayOrder = "display_order"
        case stockStatus = "stock_status"
        case availabilityObservedAt = "observed_at"
        case availabilityValidUntil = "valid_until"
        case availabilityEvidence = "availability_evidence"
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
    let structuredFacts: [String: String]
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
        case structuredFacts = "structured_facts"
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
    let audienceCode: String?
    let categoryCode: String
    let detailCode: String
    let familyCode: String
    let lengthCode: String?
    let bodyLengthCode: String?
    let reason: String?
    let evidence: [String: String]

    init(
        audienceCode: String? = nil,
        categoryCode: String,
        detailCode: String,
        familyCode: String,
        lengthCode: String?,
        bodyLengthCode: String? = nil,
        reason: String?,
        evidence: [String: String]
    ) {
        self.audienceCode = audienceCode
        self.categoryCode = categoryCode
        self.detailCode = detailCode
        self.familyCode = familyCode
        self.lengthCode = lengthCode
        self.bodyLengthCode = bodyLengthCode
        self.reason = reason
        self.evidence = evidence
    }

    enum CodingKeys: String, CodingKey {
        case audienceCode = "audience_code"
        case categoryCode = "category_code"
        case detailCode = "detail_code"
        case familyCode = "family_code"
        case lengthCode = "length_code"
        case bodyLengthCode = "body_length_code"
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
    let productVariantID: UUID?
    let productSizeID: UUID?
    let override: FitMatchClosetClassificationOverride?

    init(
        clientItemID: UUID,
        item: FitMatchClosetItemPayload,
        productID: UUID?,
        productVariantID: UUID? = nil,
        productSizeID: UUID?,
        override: FitMatchClosetClassificationOverride?
    ) {
        self.clientItemID = clientItemID
        self.item = item
        self.productID = productID
        self.productVariantID = productVariantID
        self.productSizeID = productSizeID
        self.override = override
    }
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

    init(
        closetItemID: UUID,
        clientItemID: UUID,
        syncRevision: Int,
        classificationStatus: String,
        categoryCode: String,
        detailCode: String,
        familyCode: String?,
        lengthCode: String?,
        bodyLengthCode: String?,
        isReference: Bool
    ) {
        self.closetItemID = closetItemID
        self.clientItemID = clientItemID
        self.syncRevision = syncRevision
        self.classificationStatus = classificationStatus
        self.categoryCode = categoryCode
        self.detailCode = detailCode
        self.familyCode = familyCode
        self.lengthCode = lengthCode
        self.bodyLengthCode = bodyLengthCode
        self.isReference = isReference
    }

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

    init(
        closetItemID: UUID,
        clientItemID: UUID,
        productID: UUID?,
        externalProductID: String?,
        productAudience: String?,
        sourceCategoryCodes: [String],
        variantID: UUID?,
        productSizeID: UUID?,
        brand: String?,
        productName: String,
        sizeName: String?,
        genderCode: String?,
        source: String,
        sourceCategoryPath: String?,
        productURL: String?,
        imageURL: String?,
        measurements: [String: Double],
        measurementRecords: [FitMatchClosetMeasurementRecordPayload],
        fitMemo: String,
        fitPreferenceCode: String,
        satisfaction: Int,
        isReference: Bool,
        classificationStatus: String,
        classificationSource: String?,
        categoryCode: String,
        detailCode: String,
        canonicalCategoryCode: String?,
        canonicalDetailCode: String?,
        familyCode: String?,
        lengthCode: String?,
        bodyLengthCode: String?,
        classificationSnapshot: [String: String?],
        clientSnapshot: [String: String],
        clientCreatedAt: String?,
        clientUpdatedAt: String?,
        syncRevision: Int,
        createdAt: String,
        updatedAt: String
    ) {
        self.closetItemID = closetItemID
        self.clientItemID = clientItemID
        self.productID = productID
        self.externalProductID = externalProductID
        self.productAudience = productAudience
        self.sourceCategoryCodes = sourceCategoryCodes
        self.variantID = variantID
        self.productSizeID = productSizeID
        self.brand = brand
        self.productName = productName
        self.sizeName = sizeName
        self.genderCode = genderCode
        self.source = source
        self.sourceCategoryPath = sourceCategoryPath
        self.productURL = productURL
        self.imageURL = imageURL
        self.measurements = measurements
        self.measurementRecords = measurementRecords
        self.fitMemo = fitMemo
        self.fitPreferenceCode = fitPreferenceCode
        self.satisfaction = satisfaction
        self.isReference = isReference
        self.classificationStatus = classificationStatus
        self.classificationSource = classificationSource
        self.categoryCode = categoryCode
        self.detailCode = detailCode
        self.canonicalCategoryCode = canonicalCategoryCode
        self.canonicalDetailCode = canonicalDetailCode
        self.familyCode = familyCode
        self.lengthCode = lengthCode
        self.bodyLengthCode = bodyLengthCode
        self.classificationSnapshot = classificationSnapshot
        self.clientSnapshot = clientSnapshot
        self.clientCreatedAt = clientCreatedAt
        self.clientUpdatedAt = clientUpdatedAt
        self.syncRevision = syncRevision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

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

    init(state: String, items: [FitMatchClosetItemRecord]) {
        self.state = state
        self.items = items
    }
}

nonisolated struct FitMatchSetClosetReferenceResponse: Decodable, Equatable, Sendable {
    let closetItemID: UUID
    let isReference: Bool
    let syncRevision: Int

    init(closetItemID: UUID, isReference: Bool, syncRevision: Int = 0) {
        self.closetItemID = closetItemID
        self.isReference = isReference
        self.syncRevision = syncRevision
    }

    enum CodingKeys: String, CodingKey {
        case closetItemID = "closet_item_id"
        case isReference = "is_reference"
        case syncRevision = "sync_revision"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        closetItemID = try container.decode(UUID.self, forKey: .closetItemID)
        isReference = try container.decode(Bool.self, forKey: .isReference)
        syncRevision = try container.decodeIfPresent(Int.self, forKey: .syncRevision) ?? 0
    }
}

nonisolated struct FitMatchDeleteClosetItemResponse: Decodable, Equatable, Sendable {
    let closetItemID: UUID
    let deletedAt: String

    init(closetItemID: UUID, deletedAt: String) {
        self.closetItemID = closetItemID
        self.deletedAt = deletedAt
    }

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
    let vnext: VNextProductRuntimeDTO?

    init(
        runtimeState: String,
        comparisonReady: Bool,
        product: FitMatchRuntimeProduct,
        classification: FitMatchDatabaseClassification?,
        variants: [FitMatchRuntimeVariant],
        vnext: VNextProductRuntimeDTO? = nil
    ) {
        self.runtimeState = runtimeState
        self.comparisonReady = comparisonReady
        self.product = product
        self.classification = classification
        self.variants = variants
        self.vnext = vnext
    }

    enum CodingKeys: String, CodingKey {
        case runtimeState = "runtime_state"
        case comparisonReady = "comparison_ready"
        case product
        case classification
        case variants
        case vnext
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runtimeState = try container.decode(String.self, forKey: .runtimeState)
        comparisonReady = try container.decode(Bool.self, forKey: .comparisonReady)
        product = try container.decode(FitMatchRuntimeProduct.self, forKey: .product)
        classification = try container.decodeIfPresent(
            FitMatchDatabaseClassification.self,
            forKey: .classification
        )
        variants = try container.decodeIfPresent(
            [FitMatchRuntimeVariant].self,
            forKey: .variants
        ) ?? []
        vnext = try container.decodeIfPresent(VNextProductRuntimeDTO.self, forKey: .vnext)
    }
}

nonisolated struct FitMatchDatabaseCompatibility: Decodable, Equatable, Sendable {
    let allowed: Bool
    let level: String
    let reason: String?
    let excludedMeasurements: [String]
    let minimumCommonMeasurements: Int?

    init(
        allowed: Bool,
        level: String,
        reason: String?,
        excludedMeasurements: [String],
        minimumCommonMeasurements: Int?
    ) {
        self.allowed = allowed
        self.level = level
        self.reason = reason
        self.excludedMeasurements = excludedMeasurements
        self.minimumCommonMeasurements = minimumCommonMeasurements
    }

    enum CodingKeys: String, CodingKey {
        case allowed
        case level
        case reason
        case excludedMeasurements = "excluded_measurements"
        case excludedMeasurementCodes = "excluded_measurement_codes"
        case minimumCommonMeasurements = "minimum_common_measurements"
        case minimumCommon = "minimum_common"
        case mode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        allowed = try container.decodeIfPresent(Bool.self, forKey: .allowed) ?? false
        let mode = try container.decodeIfPresent(String.self, forKey: .mode)
        level = try container.decodeIfPresent(String.self, forKey: .level)
            ?? (mode == "AUTOMATIC" ? "direct" : mode == "MANUAL_EXTENDED" ? "extended" : "incompatible")
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        excludedMeasurements = try container.decodeIfPresent(
            [String].self,
            forKey: .excludedMeasurements
        ) ?? (try container.decodeIfPresent(
            [String].self,
            forKey: .excludedMeasurementCodes
        ) ?? [])
        minimumCommonMeasurements = try container.decodeIfPresent(
            Int.self,
            forKey: .minimumCommonMeasurements
        ) ?? (try container.decodeIfPresent(Int.self, forKey: .minimumCommon))
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
    let vnext: VNextReferenceCandidatesDTO?

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
        vnext = nil
    }

    init(vnext value: VNextReferenceCandidatesDTO) {
        vnext = value
        let source = value.candidates
        automaticCount = source.filter { $0.decision == "AUTOMATIC" && $0.allowed }.count
        manualCount = source.filter { $0.decision == "MANUAL_EXTENDED" && $0.allowed }.count
        structuralCount = automaticCount + manualCount
        if automaticCount > 0 { state = "automatic" }
        else if manualCount > 0 { state = "manual_selection" }
        else if source.contains(where: { $0.decision == "MEASUREMENTS_REQUIRED" }) {
            state = "measurements_required"
        } else { state = "no_compatible_garment" }
        candidates = source.map { candidate in
            let automatic = FitMatchDatabaseCompatibility(
                allowed: candidate.allowed && candidate.decision == "AUTOMATIC",
                level: candidate.decision == "AUTOMATIC" ? "direct" : "incompatible",
                reason: candidate.reason,
                excludedMeasurements: [],
                minimumCommonMeasurements: nil
            )
            let manual = FitMatchDatabaseCompatibility(
                allowed: candidate.allowed && candidate.decision == "MANUAL_EXTENDED",
                level: candidate.decision == "MANUAL_EXTENDED" ? "extended" : "incompatible",
                reason: candidate.reason,
                excludedMeasurements: [],
                minimumCommonMeasurements: nil
            )
            return FitMatchReferenceCandidate(
                closetItemID: candidate.closetItemID,
                productName: candidate.itemName,
                sizeName: candidate.sizeLabel,
                isReference: candidate.isCurrentReference,
                automaticReady: automatic.allowed,
                manualReady: manual.allowed,
                measurementOverlapCount: 0,
                automaticCompatibility: automatic,
                manualCompatibility: manual
            )
        }
        policyVersion = "fitmatch-vnext-reference-candidates-v1"
    }
}

nonisolated struct FitMatchBeginComparisonRequest: Encodable, Equatable, Sendable {
    let referenceItemID: UUID
    let targetProductID: UUID
    let allowExtended: Bool
    let clientHistoryID: UUID
    let targetVariantID: UUID?
    let authorizationProductSizeID: UUID?
    let candidateProductSizeIDs: [UUID]?
    let effectiveAuthorityFingerprint: String?
    let personalOverrideRevision: Int?

    init(
        referenceItemID: UUID,
        targetProductID: UUID,
        allowExtended: Bool,
        clientHistoryID: UUID,
        targetVariantID: UUID? = nil,
        authorizationProductSizeID: UUID? = nil,
        candidateProductSizeIDs: [UUID]? = nil,
        effectiveAuthorityFingerprint: String? = nil,
        personalOverrideRevision: Int? = nil
    ) {
        self.referenceItemID = referenceItemID
        self.targetProductID = targetProductID
        self.allowExtended = allowExtended
        self.clientHistoryID = clientHistoryID
        self.targetVariantID = targetVariantID
        self.authorizationProductSizeID = authorizationProductSizeID
        self.candidateProductSizeIDs = candidateProductSizeIDs
        self.effectiveAuthorityFingerprint = effectiveAuthorityFingerprint
        self.personalOverrideRevision = personalOverrideRevision
    }
}

nonisolated struct FitMatchSetUserProductClassificationRequest:
    Equatable, Sendable {
    let productID: UUID
    let selectedCandidateFingerprint: String
    let expectedCandidateSetHash: String
    let expectedProductInputFingerprint: String
    let expectedProductEvidenceFingerprint: String
    let mutationID: UUID
    let expectedRevision: Int
}

nonisolated struct FitMatchClearUserProductClassificationRequest:
    Equatable, Sendable {
    let productID: UUID
    let mutationID: UUID
    let expectedRevision: Int
}

nonisolated struct FitMatchBeginComparisonResponse: Decodable, Equatable, Sendable {
    let runID: UUID
    let status: String
    let compatibility: FitMatchDatabaseCompatibility
    let vnext: VNextBeginComparisonDTO?

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case status
        case compatibility
    }

    init(from decoder: Decoder) throws {
        if let exact = try? VNextBeginComparisonDTO(from: decoder) {
            runID = exact.comparisonID
            status = exact.resultStatus.lowercased()
            compatibility = FitMatchDatabaseCompatibility(
                allowed: exact.snapshot.authorization.allowed,
                level: exact.snapshot.authorization.mode == "AUTOMATIC"
                    ? "direct" : "extended",
                reason: exact.snapshot.authorization.reason,
                excludedMeasurements: exact.snapshot.authorization.excludedMeasurementCodes,
                minimumCommonMeasurements: exact.snapshot.authorization.minimumCommon
            )
            vnext = exact
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runID = try container.decode(UUID.self, forKey: .runID)
        status = try container.decode(String.self, forKey: .status)
        compatibility = try container.decode(
            FitMatchDatabaseCompatibility.self,
            forKey: .compatibility
        )
        vnext = nil
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
    func classificationRecoveryOptions(productID: UUID) async throws
        -> VNextClassificationRecoveryContractDTO
    func setUserProductClassification(
        _ request: FitMatchSetUserProductClassificationRequest
    ) async throws -> VNextUserClassificationMutationDTO
    func clearUserProductClassification(
        _ request: FitMatchClearUserProductClassificationRequest
    ) async throws -> VNextUserClassificationMutationDTO
    func registerClosetItem(_ request: FitMatchRegisterClosetItemRequest) async throws -> UUID
    func upsertClosetItem(_ request: FitMatchUpsertClosetItemRequest) async throws
        -> FitMatchUpsertClosetItemResponse
    func listClosetItems() async throws -> FitMatchClosetItemsResponse
    func setClosetReference(closetItemID: UUID, isReference: Bool) async throws
        -> FitMatchSetClosetReferenceResponse
    func updateClosetItem(_ request: FitMatchUpsertClosetItemRequest, closetItemID: UUID) async throws
        -> FitMatchUpsertClosetItemResponse
    func setClosetClassificationOverride(
        closetItemID: UUID,
        override: FitMatchClosetClassificationOverride
    ) async throws
    func clearClosetClassificationOverride(closetItemID: UUID) async throws
    func deleteClosetItem(closetItemID: UUID) async throws
        -> FitMatchDeleteClosetItemResponse
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
    func completeComparison(_ request: FitMatchCompleteComparisonRequest) async throws
        -> FitMatchCompleteComparisonResponse
    func completeVNextComparison(
        comparisonID: UUID,
        payload: VNextComparisonCompletionPayload
    ) async throws -> VNextCompleteComparisonDTO
    func fetchVNextComparisonHistory() async throws -> [VNextComparisonHistoryDTO]
    func hideVNextComparisonHistories(clientComparisonIDs: [UUID]) async throws
        -> VNextComparisonHistoryVisibilityDTO
}

enum FitMatchSupabaseProductResolverError: LocalizedError {
    case notConfigured
    case authenticationRequired
    case vnextIdentityRequired
    case vnextCompletionRequired
    case invalidVNextResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "FitMatch DB 연결 설정이 없습니다."
        case .authenticationRequired:
            return "로그인이 필요한 기능입니다."
        case .vnextIdentityRequired:
            return "vNext 상품·variant·size 식별자가 필요합니다."
        case .vnextCompletionRequired:
            return "vNext begin 스냅샷 기반 완료 요청이 필요합니다."
        case .invalidVNextResponse:
            return "vNext 서버 응답을 검증할 수 없습니다."
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

nonisolated private struct VNextRuntimeParameters: Encodable, Sendable {
    let pSourceCode: String
    let pSourceProductKey: String

    enum CodingKeys: String, CodingKey {
        case pSourceCode = "p_source_code"
        case pSourceProductKey = "p_source_product_key"
    }
}

nonisolated private struct VNextJSONRequestParameters<Payload: Encodable & Sendable>:
    Encodable, Sendable {
    let pRequest: Payload

    enum CodingKeys: String, CodingKey { case pRequest = "p_request" }
}

nonisolated private struct VNextClosetIDParameters: Encodable, Sendable {
    let pClosetItemID: UUID
    enum CodingKeys: String, CodingKey { case pClosetItemID = "p_closet_item_id" }
}

nonisolated private struct VNextClosetUpdateParameters<Payload: Encodable & Sendable>:
    Encodable, Sendable {
    let pClosetItemID: UUID
    let pRequest: Payload

    enum CodingKeys: String, CodingKey {
        case pClosetItemID = "p_closet_item_id"
        case pRequest = "p_request"
    }
}

nonisolated private struct VNextClosetOverrideParameters: Encodable, Sendable {
    let pClosetItemID: UUID
    let pOverride: VNextClosetOverridePayload

    enum CodingKeys: String, CodingKey {
        case pClosetItemID = "p_closet_item_id"
        case pOverride = "p_override"
    }
}

nonisolated private struct VNextClosetMeasurementPayload: Encodable, Sendable {
    let fitmatchMeasurementCode: String
    let value: Double
    let unitCode: String
    let rawLabel: String?

    enum CodingKeys: String, CodingKey {
        case fitmatchMeasurementCode = "fitmatch_measurement_code"
        case value
        case unitCode = "unit_code"
        case rawLabel = "raw_label"
    }
}

nonisolated private struct VNextClosetMutationPayload: Encodable, Sendable {
    let clientItemID: UUID
    let productID: UUID?
    let productVariantID: UUID?
    let productSizeID: UUID?
    let itemName: String
    let brandName: String?
    let imageURL: String?
    let productURL: String?
    let sizeLabel: String?
    let audienceCode: String
    let garmentTypeCode: String?
    let sleeveLengthCode: String?
    let lowerLengthCode: String?
    let bodyLengthCode: String?
    let fitPreferenceCode: String
    let notes: String
    let satisfaction: Int
    let measurements: [VNextClosetMeasurementPayload]?

    enum CodingKeys: String, CodingKey {
        case clientItemID = "client_item_id"
        case productID = "product_id"
        case productVariantID = "product_variant_id"
        case productSizeID = "product_size_id"
        case itemName = "item_name"
        case brandName = "brand_name"
        case imageURL = "image_url"
        case productURL = "product_url"
        case sizeLabel = "size_label"
        case audienceCode = "audience_code"
        case garmentTypeCode = "garment_type_code"
        case sleeveLengthCode = "sleeve_length_code"
        case lowerLengthCode = "lower_length_code"
        case bodyLengthCode = "body_length_code"
        case fitPreferenceCode = "fit_preference_code"
        case notes, satisfaction, measurements
    }
}

nonisolated private struct VNextClosetOverridePayload: Encodable, Sendable {
    let audienceCode: String
    let garmentTypeCode: String
    let sleeveLengthCode: String?
    let lowerLengthCode: String?
    let bodyLengthCode: String?

    enum CodingKeys: String, CodingKey {
        case audienceCode = "audience_code"
        case garmentTypeCode = "garment_type_code"
        case sleeveLengthCode = "sleeve_length_code"
        case lowerLengthCode = "lower_length_code"
        case bodyLengthCode = "body_length_code"
    }
}

nonisolated private struct VNextReferenceCandidatesParameters: Encodable, Sendable {
    let pTargetProductID: UUID
    let pTargetVariantID: UUID

    enum CodingKeys: String, CodingKey {
        case pTargetProductID = "p_target_product_id"
        case pTargetVariantID = "p_target_variant_id"
    }
}

nonisolated private struct VNextEligibleCandidateParameters: Encodable, Sendable {
    let pReferenceClosetItemID: UUID
    let pTargetProductID: UUID
    let pTargetVariantID: UUID
    let pManualExplicit: Bool

    enum CodingKeys: String, CodingKey {
        case pReferenceClosetItemID = "p_reference_closet_item_id"
        case pTargetProductID = "p_target_product_id"
        case pTargetVariantID = "p_target_variant_id"
        case pManualExplicit = "p_manual_explicit"
    }
}

nonisolated private struct VNextRecoveryOptionsParameters: Encodable, Sendable {
    let pProductID: UUID

    enum CodingKeys: String, CodingKey {
        case pProductID = "p_product_id"
    }
}

nonisolated private struct VNextSetUserProductClassificationParameters:
    Encodable, Sendable {
    let pProductID: UUID
    let pSelectedCandidateFingerprint: String
    let pExpectedCandidateSetHash: String
    let pExpectedProductInputFingerprint: String
    let pExpectedProductEvidenceFingerprint: String
    let pMutationID: UUID
    let pExpectedRevision: Int

    enum CodingKeys: String, CodingKey {
        case pProductID = "p_product_id"
        case pSelectedCandidateFingerprint = "p_selected_candidate_fingerprint"
        case pExpectedCandidateSetHash = "p_expected_candidate_set_hash"
        case pExpectedProductInputFingerprint = "p_expected_product_input_fingerprint"
        case pExpectedProductEvidenceFingerprint = "p_expected_product_evidence_fingerprint"
        case pMutationID = "p_mutation_id"
        case pExpectedRevision = "p_expected_revision"
    }
}

nonisolated private struct VNextClearUserProductClassificationParameters:
    Encodable, Sendable {
    let pProductID: UUID
    let pMutationID: UUID
    let pExpectedRevision: Int

    enum CodingKeys: String, CodingKey {
        case pProductID = "p_product_id"
        case pMutationID = "p_mutation_id"
        case pExpectedRevision = "p_expected_revision"
    }
}

nonisolated private struct VNextBeginComparisonPayload: Encodable, Sendable {
    let clientComparisonID: UUID
    let referenceClosetItemID: UUID
    let targetProductID: UUID
    let targetVariantID: UUID
    let authorizationProductSizeID: UUID?
    let manualExplicit: Bool
    let candidateProductSizeIDs: [UUID]?
    let effectiveAuthorityFingerprint: String?
    let personalOverrideRevision: Int?

    enum CodingKeys: String, CodingKey {
        case clientComparisonID = "client_comparison_id"
        case referenceClosetItemID = "reference_closet_item_id"
        case targetProductID = "target_product_id"
        case targetVariantID = "target_variant_id"
        case authorizationProductSizeID = "authorization_product_size_id"
        case manualExplicit = "manual_explicit"
        case candidateProductSizeIDs = "candidate_product_size_ids"
        case effectiveAuthorityFingerprint = "effective_authority_fingerprint"
        case personalOverrideRevision = "personal_override_revision"
    }
}

nonisolated private struct VNextCompleteComparisonParameters: Encodable, Sendable {
    let pComparisonID: UUID
    let pResult: VNextComparisonCompletionPayload

    enum CodingKeys: String, CodingKey {
        case pComparisonID = "p_comparison_id"
        case pResult = "p_result"
    }
}

nonisolated private struct VNextHideComparisonHistoryParameters: Encodable, Sendable {
    let pClientComparisonIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case pClientComparisonIDs = "p_client_comparison_ids"
    }
}

nonisolated private struct VNextClosetMutationResponse: Decodable, Sendable {
    let itemID: UUID?
    let closetItemID: UUID?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case closetItemID = "closet_item_id"
        case deletedAt = "deleted_at"
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
        let exact = try await fetchVNextRuntime(request)
        guard exact.found, let product = exact.product else {
            return FitMatchProductResolutionResponse(
                productID: nil,
                intakeRequestID: nil,
                catalogState: "new",
                categoryEvidenceMatches: nil,
                authorityPersisted: false,
                classification: Self.unresolvedClassification,
                comparisonReady: false
            )
        }
        let runtime = try Self.mapRuntime(exact)
        return FitMatchProductResolutionResponse(
            productID: product.id,
            intakeRequestID: nil,
            catalogState: "current",
            categoryEvidenceMatches: true,
            authorityPersisted: true,
            classification: runtime.classification ?? Self.unresolvedClassification,
            comparisonReady: runtime.comparisonReady
        )
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
        throw FitMatchSupabaseProductResolverError.vnextIdentityRequired
    }

    func upsertClosetItem(_ request: FitMatchUpsertClosetItemRequest) async throws
        -> FitMatchUpsertClosetItemResponse {
        let client = try await authenticatedClient()
        let payload = Self.closetPayload(request)
        let response: VNextClosetMutationResponse = try await client
            .rpc(
                "fitmatch_vnext_upsert_closet_item",
                params: VNextJSONRequestParameters(pRequest: payload)
            )
            .execute()
            .value
        guard let itemID = response.itemID else {
            throw FitMatchSupabaseProductResolverError.invalidVNextResponse
        }
        return Self.closetMutationCompatibilityResponse(
            itemID: itemID,
            request: request
        )
    }

    func updateClosetItem(
        _ request: FitMatchUpsertClosetItemRequest,
        closetItemID: UUID
    ) async throws -> FitMatchUpsertClosetItemResponse {
        let client = try await authenticatedClient()
        let payload = Self.closetPayload(request)
        let response: VNextClosetMutationResponse = try await client
            .rpc(
                "fitmatch_vnext_update_closet_item",
                params: VNextClosetUpdateParameters(
                    pClosetItemID: closetItemID,
                    pRequest: payload
                )
            )
            .execute()
            .value
        guard response.closetItemID == closetItemID else {
            throw FitMatchSupabaseProductResolverError.invalidVNextResponse
        }
        return Self.closetMutationCompatibilityResponse(
            itemID: closetItemID,
            request: request
        )
    }

    func listClosetItems() async throws -> FitMatchClosetItemsResponse {
        let client = try await authenticatedClient()
        let items: [VNextClosetItemDTO] = try await client
            .rpc("fitmatch_vnext_list_closet_items")
            .execute()
            .value
        return FitMatchClosetItemsResponse(
            state: "ready",
            items: items.map(Self.mapClosetItem)
        )
    }

    func setClosetReference(closetItemID: UUID, isReference: Bool) async throws
        -> FitMatchSetClosetReferenceResponse {
        let client = try await authenticatedClient()
        let function = isReference
            ? "fitmatch_vnext_set_closet_reference"
            : "fitmatch_vnext_unset_closet_reference"
        let response: FitMatchSetClosetReferenceResponse = try await client
            .rpc(
                function,
                params: VNextClosetIDParameters(pClosetItemID: closetItemID)
            )
            .execute()
            .value
        return response
    }

    func setClosetClassificationOverride(
        closetItemID: UUID,
        override: FitMatchClosetClassificationOverride
    ) async throws {
        let client = try await authenticatedClient()
        let payload = Self.overridePayload(override)
        let _: VNextClosetMutationResponse = try await client
            .rpc(
                "fitmatch_vnext_set_closet_classification_override",
                params: VNextClosetOverrideParameters(
                    pClosetItemID: closetItemID,
                    pOverride: payload
                )
            )
            .execute()
            .value
    }

    func clearClosetClassificationOverride(closetItemID: UUID) async throws {
        let client = try await authenticatedClient()
        let _: VNextClosetMutationResponse = try await client
            .rpc(
                "fitmatch_vnext_clear_closet_classification_override",
                params: VNextClosetIDParameters(pClosetItemID: closetItemID)
            )
            .execute()
            .value
    }

    func deleteClosetItem(closetItemID: UUID) async throws
        -> FitMatchDeleteClosetItemResponse {
        let client = try await authenticatedClient()
        return try await client
            .rpc(
                "fitmatch_vnext_delete_closet_item",
                params: VNextClosetIDParameters(pClosetItemID: closetItemID)
            )
            .execute()
            .value
    }

    func fetchProductRuntime(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductRuntimeResponse {
        try Self.mapRuntime(try await fetchVNextRuntime(request))
    }

    func classificationRecoveryOptions(productID: UUID) async throws
        -> VNextClassificationRecoveryContractDTO {
        let client = try await authenticatedClient()
        return try await client
            .rpc(
                "fitmatch_vnext_get_classification_recovery_options",
                params: VNextRecoveryOptionsParameters(pProductID: productID)
            )
            .execute()
            .value
    }

    func setUserProductClassification(
        _ request: FitMatchSetUserProductClassificationRequest
    ) async throws -> VNextUserClassificationMutationDTO {
        let client = try await authenticatedClient()
        return try await client
            .rpc(
                "fitmatch_vnext_set_user_product_classification",
                params: VNextSetUserProductClassificationParameters(
                    pProductID: request.productID,
                    pSelectedCandidateFingerprint:
                        request.selectedCandidateFingerprint,
                    pExpectedCandidateSetHash: request.expectedCandidateSetHash,
                    pExpectedProductInputFingerprint:
                        request.expectedProductInputFingerprint,
                    pExpectedProductEvidenceFingerprint:
                        request.expectedProductEvidenceFingerprint,
                    pMutationID: request.mutationID,
                    pExpectedRevision: request.expectedRevision
                )
            )
            .execute()
            .value
    }

    func clearUserProductClassification(
        _ request: FitMatchClearUserProductClassificationRequest
    ) async throws -> VNextUserClassificationMutationDTO {
        let client = try await authenticatedClient()
        return try await client
            .rpc(
                "fitmatch_vnext_clear_user_product_classification",
                params: VNextClearUserProductClassificationParameters(
                    pProductID: request.productID,
                    pMutationID: request.mutationID,
                    pExpectedRevision: request.expectedRevision
                )
            )
            .execute()
            .value
    }

    func findReferenceCandidates(targetProductID: UUID) async throws
        -> FitMatchReferenceCandidatesResponse {
        throw FitMatchSupabaseProductResolverError.vnextIdentityRequired
    }

    func findReferenceCandidates(targetProductID: UUID, targetVariantID: UUID) async throws
        -> FitMatchReferenceCandidatesResponse {
        let client = try await authenticatedClient()
        let exact: VNextReferenceCandidatesDTO = try await client
            .rpc(
                "fitmatch_vnext_find_reference_candidates",
                params: VNextReferenceCandidatesParameters(
                    pTargetProductID: targetProductID,
                    pTargetVariantID: targetVariantID
                )
            )
            .execute()
            .value
        return FitMatchReferenceCandidatesResponse(vnext: exact)
    }

    func eligibleCandidateSizes(
        referenceClosetItemID: UUID,
        targetProductID: UUID,
        targetVariantID: UUID,
        manualExplicit: Bool
    ) async throws -> VNextEligibleCandidateSizesDTO {
        let client = try await authenticatedClient()
        return try await client
            .rpc(
                "fitmatch_vnext_eligible_candidate_sizes",
                params: VNextEligibleCandidateParameters(
                    pReferenceClosetItemID: referenceClosetItemID,
                    pTargetProductID: targetProductID,
                    pTargetVariantID: targetVariantID,
                    pManualExplicit: manualExplicit
                )
            )
            .execute()
            .value
    }

    func beginComparison(_ request: FitMatchBeginComparisonRequest) async throws
        -> FitMatchBeginComparisonResponse {
        guard let targetVariantID = request.targetVariantID else {
            throw FitMatchSupabaseProductResolverError.vnextIdentityRequired
        }
        let client = try await authenticatedClient()
        return try await client
            .rpc(
                "fitmatch_vnext_begin_comparison",
                params: VNextJSONRequestParameters(pRequest: VNextBeginComparisonPayload(
                    clientComparisonID: request.clientHistoryID,
                    referenceClosetItemID: request.referenceItemID,
                    targetProductID: request.targetProductID,
                    targetVariantID: targetVariantID,
                    authorizationProductSizeID: request.authorizationProductSizeID,
                    manualExplicit: request.allowExtended,
                    candidateProductSizeIDs: request.candidateProductSizeIDs,
                    effectiveAuthorityFingerprint:
                        request.effectiveAuthorityFingerprint,
                    personalOverrideRevision: request.personalOverrideRevision
                ))
            )
            .execute()
            .value
    }

    func completeComparison(_ request: FitMatchCompleteComparisonRequest) async throws
        -> FitMatchCompleteComparisonResponse {
        throw FitMatchSupabaseProductResolverError.vnextCompletionRequired
    }

    func completeVNextComparison(
        comparisonID: UUID,
        payload: VNextComparisonCompletionPayload
    ) async throws -> VNextCompleteComparisonDTO {
        let client = try await authenticatedClient()
        return try await client
            .rpc(
                "fitmatch_vnext_complete_comparison",
                params: VNextCompleteComparisonParameters(
                    pComparisonID: comparisonID,
                    pResult: payload
                )
            )
            .execute()
            .value
    }

    func fetchVNextComparisonHistory() async throws -> [VNextComparisonHistoryDTO] {
        let client = try await authenticatedClient()
        return try await client
            .rpc("fitmatch_vnext_comparison_history")
            .execute()
            .value
    }

    func hideVNextComparisonHistories(
        clientComparisonIDs: [UUID]
    ) async throws -> VNextComparisonHistoryVisibilityDTO {
        let client = try await authenticatedClient()
        return try await client
            .rpc(
                "fitmatch_vnext_hide_comparison_history",
                params: VNextHideComparisonHistoryParameters(
                    pClientComparisonIDs: clientComparisonIDs
                )
            )
            .execute()
            .value
    }

    private func fetchVNextRuntime(
        _ request: FitMatchProductResolutionRequest
    ) async throws -> VNextProductRuntimeDTO {
        let client = try await authenticatedClient()
        return try await client
            .rpc(
                "fitmatch_vnext_get_product_runtime",
                params: VNextRuntimeParameters(
                    pSourceCode: request.source,
                    pSourceProductKey: request.externalProductID
                )
            )
            .execute()
            .value
    }

    nonisolated private static let unresolvedClassification = FitMatchDatabaseClassification(
        classificationID: nil,
        categoryCode: nil,
        detailCode: nil,
        garmentTypeCode: nil,
        familyCode: nil,
        lengthCode: nil,
        bodyLengthCode: nil,
        status: "review_required",
        method: "fitmatch_vnext",
        authorityStatus: "server",
        confidence: nil,
        requiresUserConfirmation: true,
        taxonomyPolicyVersion: nil,
        decisionVersion: nil
    )

    nonisolated private static func mapRuntime(
        _ exact: VNextProductRuntimeDTO
    ) throws -> FitMatchProductRuntimeResponse {
        guard exact.found,
              let product = exact.product,
              let readiness = exact.readiness else {
            throw FitMatchSupabaseProductResolverError.invalidVNextResponse
        }
        let effective = exact.effectiveClassification
        if let effective, effective.productID != product.id {
            throw FitMatchSupabaseProductResolverError.invalidVNextResponse
        }
        let effectiveTuple = VNextRuntimeClassificationTuple(
            product: product,
            effective: effective
        )
        let serverStatus = effectiveTuple.classificationStatus
        let normalizedStatus: String
        switch serverStatus {
        case "CONFIRMED": normalizedStatus = "confirmed"
        case "REVIEW_REQUIRED": normalizedStatus = "review_required"
        case "NOT_APPLICABLE": normalizedStatus = "not_comparable"
        default: throw FitMatchSupabaseProductResolverError.invalidVNextResponse
        }
        if let effective {
            let validState: Bool
            switch (effective.state, effective.classificationStatus, effective.effectiveSource) {
            case ("GLOBAL_CONFIRMED", "CONFIRMED", "GLOBAL_CONFIRMED"),
                 ("SUPERSEDED_MATCH", "CONFIRMED", "GLOBAL_CONFIRMED"),
                 ("SUPERSEDED_CONFLICT", "CONFIRMED", "GLOBAL_CONFIRMED"),
                 ("PERSONAL_CONFIRMED", "CONFIRMED", "USER_EXPLICIT"),
                 ("REVIEW_REQUIRED", "REVIEW_REQUIRED", "NONE"),
                 ("STALE_RECONFIRM_REQUIRED", "REVIEW_REQUIRED", "NONE"),
                 ("GLOBAL_NOT_APPLICABLE", "NOT_APPLICABLE", "GLOBAL_NOT_APPLICABLE"):
                validState = true
            default:
                validState = false
            }
            guard validState else {
                throw FitMatchSupabaseProductResolverError.invalidVNextResponse
            }
        }
        let effectiveCategory = effectiveTuple.categoryCode
        let effectiveGarment = effectiveTuple.garmentTypeCode
        let effectivePolicy = effectiveTuple.comparisonPolicyCode
        let effectiveSleeve = effectiveTuple.sleeveLengthCode
        let effectiveLower = effectiveTuple.lowerLengthCode
        let effectiveBody = effectiveTuple.bodyLengthCode
        if normalizedStatus == "confirmed" {
            guard effectiveCategory?.isEmpty == false,
                  effectiveGarment?.isEmpty == false,
                  effectivePolicy?.isEmpty == false else {
                throw FitMatchSupabaseProductResolverError.invalidVNextResponse
            }
        }
        let classification = FitMatchDatabaseClassification(
            classificationID: product.id,
            categoryCode: effectiveCategory,
            detailCode: effectiveGarment,
            garmentTypeCode: effectiveGarment,
            familyCode: effectivePolicy,
            lengthCode: effectiveSleeve ?? effectiveLower,
            bodyLengthCode: effectiveBody,
            status: normalizedStatus,
            method: effectiveTuple.contractVersion,
            authorityStatus: effectiveTuple.effectiveSource == "USER_EXPLICIT"
                ? "user_explicit" : "server",
            confidence: nil,
            requiresUserConfirmation: normalizedStatus != "confirmed",
            taxonomyPolicyVersion: effectiveTuple.contractVersion,
            decisionVersion: nil
        )
        let variants = exact.variants.enumerated().map { variantIndex, variant in
            FitMatchRuntimeVariant(
                variantID: variant.id,
                externalVariantID: variant.sourceVariantKey,
                variantName: variant.variantLabel,
                colorCode: nil,
                colorName: variant.colorName,
                sizes: variant.sizes.enumerated().map { sizeIndex, size in
                    FitMatchRuntimeSize(
                        productSizeID: size.id,
                        externalSizeID: size.sourceSizeKey,
                        sizeLabel: size.sizeLabel,
                        normalizedSizeLabel: SizeTokenNormalizer.displayName(
                            for: size.sizeLabel
                        ),
                        displayOrder: sizeIndex,
                        stockStatus: size.availability.status,
                        measurements: size.canonicalMeasurements.measurements.map { metric in
                            FitMatchRuntimeMeasurement(
                                measurementCode: metric.measurementCode,
                                rawLabel: metric.sourceMeasurementCode
                                    ?? metric.measurementCode,
                                rawValue: metric.value,
                                rawUnit: metric.unitCode,
                                normalizedValue: metric.value,
                                normalizedUnit: metric.unitCode,
                                comparisonBasis: metric.basisCode,
                                isComparable: true,
                                exclusionReason: nil,
                                policyVersion: product.resolverVersion
                            )
                        }
                    )
                }
            )
        }
        let runtimeState: String
        switch readiness.status {
        case "READY": runtimeState = "ready"
        case "CLASSIFICATION_REQUIRED": runtimeState = "classification_required"
        case "NOT_APPLICABLE": runtimeState = "not_comparable"
        case "NO_AVAILABLE_SIZE": runtimeState = "sizes_required"
        default: runtimeState = "measurements_required"
        }
        return FitMatchProductRuntimeResponse(
            runtimeState: runtimeState,
            comparisonReady: readiness.status == "READY",
            product: FitMatchRuntimeProduct(
                productID: product.id,
                source: product.sourceCode,
                externalProductID: product.sourceProductKey,
                productName: product.productName,
                canonicalURL: product.canonicalURL,
                audience: effectiveTuple.audienceCode,
                sourceCategoryPath: nil,
                sourceCategoryCodes: [],
                imageURL: product.imageURL,
                lifecycleStatus: "active",
                inputFingerprint: product.inputFingerprint ?? ""
            ),
            classification: classification,
            variants: variants,
            vnext: exact
        )
    }

    nonisolated private static func closetPayload(
        _ request: FitMatchUpsertClosetItemRequest
    ) -> VNextClosetMutationPayload {
        let override = request.override
        let category = override?.categoryCode ?? request.item.categoryCode
        let garment = override?.familyCode ?? request.item.familyCode
        let length = override?.lengthCode ?? request.item.lengthCode
        let measurements: [VNextClosetMeasurementPayload]
        if request.item.measurementRecords.isEmpty {
            measurements = request.item.measurements.sorted { $0.key < $1.key }.map {
                VNextClosetMeasurementPayload(
                    fitmatchMeasurementCode: $0.key,
                    value: $0.value,
                    unitCode: "cm",
                    rawLabel: $0.key
                )
            }
        } else {
            measurements = request.item.measurementRecords.compactMap { record in
                guard record.value.isFinite, record.value > 0 else { return nil }
                return VNextClosetMeasurementPayload(
                    fitmatchMeasurementCode: record.measurementCode,
                    value: record.value,
                    unitCode: record.unit,
                    rawLabel: record.rawLabel
                )
            }
        }
        return VNextClosetMutationPayload(
            clientItemID: request.clientItemID,
            productID: request.productID,
            productVariantID: request.productVariantID,
            productSizeID: request.productSizeID,
            itemName: request.item.productName,
            brandName: request.item.brand,
            imageURL: request.item.imageURL,
            productURL: request.item.productURL,
            sizeLabel: request.item.sizeName,
            audienceCode: vnextAudience(request.item.genderCode),
            garmentTypeCode: garment,
            sleeveLengthCode: category == "tops" ? length : nil,
            lowerLengthCode: category == "bottoms" ? length : nil,
            bodyLengthCode: request.item.bodyLengthCode
                ?? (category == "dresses" ? length : nil),
            fitPreferenceCode: request.item.fitPreferenceCode,
            notes: request.item.fitMemo,
            satisfaction: request.item.satisfaction,
            // Product-linked items always hydrate canonical measurements from
            // the selected vNext size. Local cache values are never allowed to
            // overwrite sourced measurement authority during an edit.
            measurements: request.productID == nil ? measurements : nil
        )
    }

    nonisolated private static func overridePayload(
        _ value: FitMatchClosetClassificationOverride
    ) -> VNextClosetOverridePayload {
        VNextClosetOverridePayload(
            audienceCode: vnextAudience(value.audienceCode ?? "unknown"),
            garmentTypeCode: value.familyCode,
            sleeveLengthCode: value.categoryCode == "tops" ? value.lengthCode : nil,
            lowerLengthCode: value.categoryCode == "bottoms" ? value.lengthCode : nil,
            bodyLengthCode: value.bodyLengthCode
                ?? (value.categoryCode == "dresses" ? value.lengthCode : nil)
        )
    }

    nonisolated private static func closetMutationCompatibilityResponse(
        itemID: UUID,
        request: FitMatchUpsertClosetItemRequest
    ) -> FitMatchUpsertClosetItemResponse {
        FitMatchUpsertClosetItemResponse(
            closetItemID: itemID,
            clientItemID: request.clientItemID,
            syncRevision: 0,
            classificationStatus: "confirmed",
            categoryCode: request.override?.categoryCode ?? request.item.categoryCode,
            detailCode: request.override?.detailCode ?? request.item.detailCode,
            familyCode: request.override?.familyCode ?? request.item.familyCode,
            lengthCode: request.override?.lengthCode ?? request.item.lengthCode,
            bodyLengthCode: request.item.bodyLengthCode,
            isReference: request.item.isReference
        )
    }

    nonisolated private static func mapClosetItem(
        _ item: VNextClosetItemDTO
    ) -> FitMatchClosetItemRecord {
        let measurements = Dictionary(uniqueKeysWithValues: item.measurements.map {
            ($0.measurementCode, $0.value)
        })
        let records = item.measurements.map { measurement in
            FitMatchClosetMeasurementRecordPayload(
                value: measurement.value,
                unit: measurement.unitCode,
                measurementCode: measurement.measurementCode,
                displayKind: displayKind(for: measurement.measurementCode),
                methodSource: "fitmatch_vnext_snapshot",
                methodProfile: item.classificationResolverVersion,
                inputSource: item.productID == nil
                    ? MeasurementInputSource.userMeasured.rawValue
                    : MeasurementInputSource.importedSizeChart.rawValue,
                standardVersion: nil,
                mappingVersion: item.classificationResolverVersion
                    ?? "fitmatch-vnext-closet-v1",
                rawCode: measurement.measurementCode,
                rawLabel: measurement.rawLabelSnapshot ?? measurement.measurementCode,
                rawInfo: nil,
                rawValueText: String(measurement.value),
                evidenceLevel: item.productID == nil
                    ? MeasurementEvidenceLevel.fitmatchDefined.rawValue
                    : MeasurementEvidenceLevel.officialText.rawValue,
                semanticStatus: MeasurementSemanticStatus.mapped.rawValue
            )
        }
        let isPersonal = item.classificationSource == "USER_EXPLICIT"
            || item.classificationSource == "USER_EDITED"
        return FitMatchClosetItemRecord(
            closetItemID: item.id,
            clientItemID: item.clientItemID,
            productID: item.productID,
            externalProductID: item.sourceProductKey,
            productAudience: item.audienceCode,
            sourceCategoryCodes: [],
            variantID: item.productVariantID,
            productSizeID: item.productSizeID,
            brand: item.brandName,
            productName: item.itemName,
            sizeName: item.sizeLabel,
            genderCode: item.audienceCode.lowercased(),
            source: item.sourceCode,
            sourceCategoryPath: item.sourceCategoryPath,
            productURL: item.productURL,
            imageURL: item.imageURL,
            measurements: measurements,
            measurementRecords: records,
            fitMemo: item.notes ?? "",
            fitPreferenceCode: item.fitPreferenceCode ?? "regular",
            satisfaction: item.satisfaction ?? 3,
            isReference: item.isReference,
            classificationStatus: "confirmed",
            classificationSource: isPersonal ? "manual_override" : "product_metadata",
            categoryCode: item.categoryCode ?? "other",
            detailCode: item.garmentTypeCode,
            canonicalCategoryCode: item.categoryCode,
            canonicalDetailCode: item.garmentTypeCode,
            familyCode: item.garmentTypeCode,
            lengthCode: item.sleeveLengthCode ?? item.lowerLengthCode,
            bodyLengthCode: item.bodyLengthCode,
            classificationSnapshot: [
                "classification_fingerprint": item.classificationFingerprint,
                "decision_version": item.classificationResolverVersion
            ],
            clientSnapshot: [:],
            clientCreatedAt: item.createdAt,
            clientUpdatedAt: item.updatedAt,
            syncRevision: 0,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }

    nonisolated private static func vnextAudience(_ value: String) -> String {
        switch value.lowercased() {
        case "men", "male": return "MEN"
        case "women", "female": return "WOMEN"
        case "kids", "child": return "KIDS"
        default: return "UNISEX"
        }
    }

    nonisolated private static func displayKind(for code: String) -> String {
        if code.contains("shoulder") { return MeasurementDisplayKind.shoulder.rawValue }
        if code.contains("chest") { return MeasurementDisplayKind.chest.rawValue }
        if code.contains("sleeve") { return MeasurementDisplayKind.sleeveLength.rawValue }
        if code.contains("body_length") || code.contains("outseam")
            || code.contains("inseam") || code.contains("skirt_length") {
            return MeasurementDisplayKind.totalLength.rawValue
        }
        if code.contains("upper_abdomen") { return MeasurementDisplayKind.upperAbdomen.rawValue }
        if code.contains("upper_waist") { return MeasurementDisplayKind.upperWaist.rawValue }
        if code.contains("waist") { return MeasurementDisplayKind.waist.rawValue }
        if code.contains("hip") { return MeasurementDisplayKind.hip.rawValue }
        if code.contains("thigh") { return MeasurementDisplayKind.thigh.rawValue }
        if code.contains("rise") { return MeasurementDisplayKind.rise.rawValue }
        if code.contains("hem") { return MeasurementDisplayKind.hem.rawValue }
        if code.contains("foot") { return MeasurementDisplayKind.footLength.rawValue }
        if code.contains("under_bust") { return MeasurementDisplayKind.underBust.rawValue }
        return MeasurementDisplayKind.unknown.rawValue
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
        let audience = FitMatchCanonicalAudience.code(from: metadata.genderCodes)
        var structuredFacts = metadata.structuredFacts.reduce(into: [String: String]()) {
            facts,
            entry in
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return }
            facts[key] = value
        }
        let isExplicitSet = ParsedClosetClassification.isExplicitCompositeGarmentSet(productName)
            || (source == "musinsa" && MusinsaUnsupportedProductPolicy.isTopBottomSet(
                categoryDepth2Name: metadata.categoryDepth2Name
                    ?? sourceCategoryDepth2
            ))
        if isExplicitSet {
            structuredFacts["product_structure"] = "set"
        }
        return FitMatchProductResolutionRequest(
            source: source,
            externalProductID: productID,
            productName: productName.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceCategoryPath: path?.trimmingCharacters(in: .whitespacesAndNewlines),
            audience: audience,
            sourceCategoryCodes: codes.isEmpty ? nil : codes,
            structuredFacts: structuredFacts
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
            let normalizedStatus: String = {
                if let explicit = size.availabilityStatus?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased(),
                   ["AVAILABLE", "SOLD_OUT", "UNKNOWN"].contains(explicit) {
                    return explicit
                }
                guard let checkedSize = metadata.checkedSizeName?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      !checkedSize.isEmpty,
                      SizeTokenNormalizer.displayName(for: checkedSize)
                        .localizedCaseInsensitiveCompare(
                            SizeTokenNormalizer.displayName(for: label)
                        ) == .orderedSame else {
                    return "UNKNOWN"
                }
                if metadata.isOutOfStock
                    || metadata.stockStatusRawValue == ProductStockStatus.outOfStock.rawValue {
                    return "SOLD_OUT"
                }
                if metadata.stockStatusRawValue == ProductStockStatus.inStock.rawValue {
                    return "AVAILABLE"
                }
                return "UNKNOWN"
            }()
            let availabilityObservedAt = size.availabilityObservedAt ?? (
                normalizedStatus == "UNKNOWN" ? nil : observedAt
            )
            return FitMatchProductObservationSize(
                sizeIdentity: ParsedProductSizeNormalizer.normalizedSizeKey(for: label),
                sizeLabel: label,
                normalizedSizeLabel: SizeTokenNormalizer.displayName(for: label),
                displayOrder: index,
                stockStatus: normalizedStatus,
                availabilityObservedAt: availabilityObservedAt.map(formatter.string(from:)),
                availabilityValidUntil: size.availabilityValidUntil.map(formatter.string(from:)),
                availabilityEvidence: size.availabilityEvidence,
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
                structuredFacts: resolution.structuredFacts,
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
