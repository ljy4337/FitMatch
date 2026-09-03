import Foundation

nonisolated enum FitMatchJSONValue: Codable, Equatable, Sendable {
    case object([String: FitMatchJSONValue])
    case array([FitMatchJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: FitMatchJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([FitMatchJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

nonisolated extension FitMatchJSONValue {
    var objectValue: [String: FitMatchJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [FitMatchJSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var numberValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }
}

nonisolated struct VNextProductReadinessDTO: Decodable, Equatable, Sendable {
    let status: String
    let reason: String?
    let readySizeCount: Int
    let policyMetricCount: Int

    enum CodingKeys: String, CodingKey {
        case status, reason
        case readySizeCount = "ready_size_count"
        case policyMetricCount = "policy_metric_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        readySizeCount = try container.decodeIfPresent(Int.self, forKey: .readySizeCount) ?? 0
        policyMetricCount = try container.decodeIfPresent(Int.self, forKey: .policyMetricCount) ?? 0
    }
}

nonisolated struct VNextRuntimeProductDTO: Decodable, Equatable, Sendable {
    let id: UUID
    let sourceCode: String
    let sourceProductKey: String
    let productName: String
    let brandName: String?
    let canonicalURL: String?
    let imageURL: String?
    let classificationStatus: String
    let productStructureCode: String
    let audienceCode: String
    let categoryCode: String?
    let garmentTypeCode: String?
    let comparisonPolicyCode: String?
    let sleeveLengthCode: String?
    let lowerLengthCode: String?
    let bodyLengthCode: String?
    let resolverVersion: String?
    let inputFingerprint: String?
    let latestIngestionFingerprint: String?

    enum CodingKeys: String, CodingKey {
        case id
        case sourceCode = "source_code"
        case sourceProductKey = "source_product_key"
        case productName = "product_name"
        case brandName = "brand_name"
        case canonicalURL = "canonical_url"
        case imageURL = "image_url"
        case classificationStatus = "classification_status"
        case productStructureCode = "product_structure_code"
        case audienceCode = "audience_code"
        case categoryCode = "category_code"
        case garmentTypeCode = "garment_type_code"
        case comparisonPolicyCode = "comparison_policy_code"
        case sleeveLengthCode = "sleeve_length_code"
        case lowerLengthCode = "lower_length_code"
        case bodyLengthCode = "body_length_code"
        case resolverVersion = "resolver_version"
        case inputFingerprint = "input_fingerprint"
        case latestIngestionFingerprint = "latest_ingestion_fingerprint"
    }
}

nonisolated struct VNextAvailabilityDTO: Decodable, Equatable, Sendable {
    let status: String
    let observedAt: String?
    let validUntil: String?
    let evidenceFingerprint: String?

    enum CodingKeys: String, CodingKey {
        case status
        case observedAt = "observed_at"
        case validUntil = "valid_until"
        case evidenceFingerprint = "evidence_fingerprint"
    }
}

nonisolated struct VNextCanonicalMeasurementDTO: Decodable, Equatable, Sendable {
    let measurementCode: String
    let value: Double
    let unitCode: String
    let basisCode: String?
    let sourceMeasurementCode: String?

    enum CodingKeys: String, CodingKey {
        case measurementCode = "fitmatch_measurement_code"
        case value
        case unitCode = "unit_code"
        case basisCode = "basis_code"
        case sourceMeasurementCode = "source_measurement_code"
    }
}

nonisolated struct VNextCanonicalMeasurementsDTO: Decodable, Equatable, Sendable {
    let measurements: [VNextCanonicalMeasurementDTO]
    let semanticConflictCount: Int

    enum CodingKeys: String, CodingKey {
        case measurements
        case semanticConflictCount = "semantic_conflict_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        measurements = try container.decodeIfPresent(
            [VNextCanonicalMeasurementDTO].self,
            forKey: .measurements
        ) ?? []
        semanticConflictCount = try container.decodeIfPresent(
            Int.self,
            forKey: .semanticConflictCount
        ) ?? 0
    }
}

nonisolated struct VNextRuntimeSizeDTO: Decodable, Equatable, Sendable {
    let id: UUID
    let sourceSizeKey: String?
    let sizeLabel: String
    let availability: VNextAvailabilityDTO
    let canonicalMeasurements: VNextCanonicalMeasurementsDTO

    enum CodingKeys: String, CodingKey {
        case id
        case sourceSizeKey = "source_size_key"
        case sizeLabel = "size_label"
        case availability
        case canonicalMeasurements = "canonical_measurements"
    }
}

nonisolated struct VNextRuntimeVariantDTO: Decodable, Equatable, Sendable {
    let id: UUID
    let sourceVariantKey: String?
    let variantLabel: String?
    let colorName: String?
    let sizes: [VNextRuntimeSizeDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case sourceVariantKey = "source_variant_key"
        case variantLabel = "variant_label"
        case colorName = "color_name"
        case sizes
    }
}

nonisolated enum VNextClassificationRecoverability: String, Decodable, Sendable {
    case recoverable = "RECOVERABLE"
    case unrecoverable = "UNRECOVERABLE"
}

nonisolated enum VNextUnknownClassificationField: String, Decodable, Sendable {
    case garmentType = "garment_type"
    case sleeveLength = "sleeve_length"
    case lowerLength = "lower_length"
    case bodyLength = "body_length"
}

nonisolated struct VNextKnownClassificationFactsDTO: Decodable, Equatable, Sendable {
    let audienceCode: String?
    let productStructureCode: String?
    let categoryCode: String?
    let garmentTypeCode: String?
    let sleeveLengthCode: String?
    let lowerLengthCode: String?
    let bodyLengthCode: String?
    let comparisonPolicyCode: String?

    enum CodingKeys: String, CodingKey {
        case audienceCode = "audience_code"
        case productStructureCode = "product_structure_code"
        case categoryCode = "category_code"
        case garmentTypeCode = "garment_type_code"
        case sleeveLengthCode = "sleeve_length_code"
        case lowerLengthCode = "lower_length_code"
        case bodyLengthCode = "body_length_code"
        case comparisonPolicyCode = "comparison_policy_code"
    }
}

nonisolated struct VNextClassificationRecoveryCandidateDTO:
    Decodable, Equatable, Identifiable, Sendable {
    let candidateID: String
    let candidateFingerprint: String
    let displayName: String
    let categoryCode: String
    let garmentTypeCode: String
    let sleeveLengthCode: String?
    let lowerLengthCode: String?
    let bodyLengthCode: String?
    let comparisonPolicyCode: String

    var id: String { candidateID }

    func value(for field: VNextUnknownClassificationField) -> String? {
        switch field {
        case .garmentType:
            garmentTypeCode
        case .sleeveLength:
            sleeveLengthCode
        case .lowerLength:
            lowerLengthCode
        case .bodyLength:
            bodyLengthCode
        }
    }

    enum CodingKeys: String, CodingKey {
        case candidateID = "candidate_id"
        case candidateFingerprint = "candidate_fingerprint"
        case displayName = "display_name"
        case categoryCode = "category_code"
        case garmentTypeCode = "garment_type_code"
        case sleeveLengthCode = "sleeve_length_code"
        case lowerLengthCode = "lower_length_code"
        case bodyLengthCode = "body_length_code"
        case comparisonPolicyCode = "comparison_policy_code"
    }
}

nonisolated struct VNextClassificationRecoveryGarmentGroup:
    Equatable, Identifiable, Sendable {
    let garmentTypeCode: String
    let displayName: String
    let candidates: [VNextClassificationRecoveryCandidateDTO]

    var id: String { garmentTypeCode }

    /// Only axes whose server-issued values actually differ need a follow-up.
    /// No tuple value is inferred or rewritten here.
    var differingFields: [VNextUnknownClassificationField] {
        [
            .sleeveLength,
            .lowerLength,
            .bodyLength
        ].filter { field in
            guard let first = candidates.first?.value(for: field) else {
                return candidates.contains { $0.value(for: field) != nil }
            }
            return candidates.dropFirst().contains {
                $0.value(for: field) != first
            }
        }
    }
}

nonisolated struct VNextClassificationRecoveryContractDTO:
    Decodable, Equatable, Sendable {
    static let completeTupleContractVersion =
        "fitmatch-vnext-recovery-v6-complete-tuple-garment-first"

    let productID: UUID
    let globalStatus: String
    let recoverability: VNextClassificationRecoverability
    let unrecoverableReason: String?
    let fixedFacts: VNextKnownClassificationFactsDTO
    let unknownFields: [VNextUnknownClassificationField]
    let candidates: [VNextClassificationRecoveryCandidateDTO]
    let candidateCount: Int
    let productInputFingerprint: String
    let productEvidenceFingerprint: String
    let resolverVersion: String
    let candidateContractVersion: String
    let candidateSetHash: String?
    let currentReviewReason: String?

    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case globalStatus = "global_status"
        case recoverability
        case unrecoverableReason = "unrecoverable_reason"
        case fixedFacts = "fixed_facts"
        case unknownFields = "unknown_fields"
        case candidates
        case candidateCount = "candidate_count"
        case productInputFingerprint = "product_input_fingerprint"
        case productEvidenceFingerprint = "product_evidence_fingerprint"
        case resolverVersion = "resolver_version"
        case candidateContractVersion = "candidate_contract_version"
        case candidateSetHash = "candidate_set_hash"
        case currentReviewReason = "current_review_reason"
    }

    var isSafelyRecoverable: Bool {
        recoverability == .recoverable
            && candidateContractVersion == Self.completeTupleContractVersion
            && (1...3).contains(candidates.count)
            && candidateCount == candidates.count
            && candidateSetHash?.isEmpty == false
            && candidates.allSatisfy(isCompleteCandidateShape)
            && candidates.allSatisfy(matchesFixedFacts)
            && unknownFields == presentationUnknownFields
    }

    var garmentGroups: [VNextClassificationRecoveryGarmentGroup] {
        var orderedCodes: [String] = []
        var groupedCandidates: [String: [VNextClassificationRecoveryCandidateDTO]] = [:]

        for candidate in candidates {
            if groupedCandidates[candidate.garmentTypeCode] == nil {
                orderedCodes.append(candidate.garmentTypeCode)
            }
            groupedCandidates[candidate.garmentTypeCode, default: []].append(candidate)
        }

        return orderedCodes.compactMap { garmentTypeCode in
            guard let candidates = groupedCandidates[garmentTypeCode],
                  let first = candidates.first else { return nil }
            return VNextClassificationRecoveryGarmentGroup(
                garmentTypeCode: garmentTypeCode,
                displayName: first.displayName,
                candidates: candidates
            )
        }
    }

    var presentationUnknownFields: [VNextUnknownClassificationField] {
        var result: [VNextUnknownClassificationField] = []
        if garmentGroups.count > 1 {
            result.append(.garmentType)
        }
        for field in [
            VNextUnknownClassificationField.sleeveLength,
            .lowerLength,
            .bodyLength
        ] where garmentGroups.contains(where: {
            $0.differingFields.contains(field)
        }) {
            result.append(field)
        }
        return result
    }

    private func isCompleteCandidateShape(
        _ candidate: VNextClassificationRecoveryCandidateDTO
    ) -> Bool {
        !candidate.candidateID.isEmpty
            && !candidate.candidateFingerprint.isEmpty
            && !candidate.displayName.isEmpty
            && !candidate.categoryCode.isEmpty
            && !candidate.garmentTypeCode.isEmpty
            && !candidate.comparisonPolicyCode.isEmpty
            && [
                candidate.sleeveLengthCode,
                candidate.lowerLengthCode,
                candidate.bodyLengthCode
            ].compactMap { $0 }.allSatisfy { !$0.isEmpty && $0 != "UNKNOWN" }
    }

    private func matchesFixedFacts(
        _ candidate: VNextClassificationRecoveryCandidateDTO
    ) -> Bool {
        (fixedFacts.categoryCode == nil
            || fixedFacts.categoryCode == candidate.categoryCode)
            && (fixedFacts.garmentTypeCode == nil
                || fixedFacts.garmentTypeCode == candidate.garmentTypeCode)
            && (fixedFacts.sleeveLengthCode == nil
                || fixedFacts.sleeveLengthCode == candidate.sleeveLengthCode)
            && (fixedFacts.lowerLengthCode == nil
                || fixedFacts.lowerLengthCode == candidate.lowerLengthCode)
            && (fixedFacts.bodyLengthCode == nil
                || fixedFacts.bodyLengthCode == candidate.bodyLengthCode)
            && (fixedFacts.comparisonPolicyCode == nil
                || fixedFacts.comparisonPolicyCode ==
                   candidate.comparisonPolicyCode)
    }
}

nonisolated struct VNextUserProductClassificationOverrideDTO:
    Decodable, Equatable, Sendable {
    let id: UUID
    let productID: UUID
    let classificationSource: String
    let audienceCode: String
    let categoryCode: String
    let garmentTypeCode: String
    let comparisonPolicyCode: String
    let sleeveLengthCode: String?
    let lowerLengthCode: String?
    let bodyLengthCode: String?
    let selectedCandidateFingerprint: String
    let candidateContractVersion: String
    let candidateSetHash: String
    let revision: Int
    let clearedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case productID = "product_id"
        case classificationSource = "classification_source"
        case audienceCode = "audience_code"
        case categoryCode = "category_code"
        case garmentTypeCode = "garment_type_code"
        case comparisonPolicyCode = "comparison_policy_code"
        case sleeveLengthCode = "sleeve_length_code"
        case lowerLengthCode = "lower_length_code"
        case bodyLengthCode = "body_length_code"
        case selectedCandidateFingerprint = "selected_candidate_fingerprint"
        case candidateContractVersion = "candidate_contract_version"
        case candidateSetHash = "candidate_set_hash"
        case revision
        case clearedAt = "cleared_at"
    }
}

nonisolated struct VNextEffectiveTargetClassificationDTO:
    Decodable, Equatable, Sendable {
    let productID: UUID
    let state: String
    let classificationStatus: String
    let effectiveSource: String
    let categoryCode: String?
    let garmentTypeCode: String?
    let audienceCode: String
    let sleeveLengthCode: String?
    let lowerLengthCode: String?
    let bodyLengthCode: String?
    let comparisonPolicyCode: String?
    let productStructureCode: String
    let personalProjection: FitMatchJSONValue?
    let overrideRevision: Int?
    let effectiveAuthorityFingerprint: String
    let effectiveContractVersion: String

    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case state
        case classificationStatus = "classification_status"
        case effectiveSource = "effective_source"
        case categoryCode = "category_code"
        case garmentTypeCode = "garment_type_code"
        case audienceCode = "audience_code"
        case sleeveLengthCode = "sleeve_length_code"
        case lowerLengthCode = "lower_length_code"
        case bodyLengthCode = "body_length_code"
        case comparisonPolicyCode = "comparison_policy_code"
        case productStructureCode = "product_structure_code"
        case personalProjection = "personal_projection"
        case overrideRevision = "override_revision"
        case effectiveAuthorityFingerprint = "effective_authority_fingerprint"
        case effectiveContractVersion = "effective_contract_version"
    }

    var isPersonalComparisonAuthority: Bool {
        state == "PERSONAL_CONFIRMED"
            && classificationStatus == "CONFIRMED"
            && effectiveSource == "USER_EXPLICIT"
    }
}

/// The server's effective classification is one authority-issued tuple.
///
/// When it exists, each field (including an intentionally absent axis) belongs
/// to that tuple. Callers must not fill individual values from the global
/// Product tuple, which would construct a classification the server never
/// issued. Global fields are used only when the entire effective object is
/// absent from the current contract.
nonisolated struct VNextRuntimeClassificationTuple: Equatable, Sendable {
    let usesEffectiveClassification: Bool
    let classificationStatus: String
    let effectiveSource: String?
    let categoryCode: String?
    let garmentTypeCode: String?
    let audienceCode: String
    let sleeveLengthCode: String?
    let lowerLengthCode: String?
    let bodyLengthCode: String?
    let comparisonPolicyCode: String?
    let productStructureCode: String
    let contractVersion: String?
    let authorityFingerprint: String?
    let overrideRevision: Int?

    init(
        product: VNextRuntimeProductDTO,
        effective: VNextEffectiveTargetClassificationDTO?
    ) {
        if let effective {
            usesEffectiveClassification = true
            classificationStatus = effective.classificationStatus
            effectiveSource = effective.effectiveSource
            categoryCode = effective.categoryCode
            garmentTypeCode = effective.garmentTypeCode
            audienceCode = effective.audienceCode
            sleeveLengthCode = effective.sleeveLengthCode
            lowerLengthCode = effective.lowerLengthCode
            bodyLengthCode = effective.bodyLengthCode
            comparisonPolicyCode = effective.comparisonPolicyCode
            productStructureCode = effective.productStructureCode
            contractVersion = effective.effectiveContractVersion
            authorityFingerprint = effective.effectiveAuthorityFingerprint
            overrideRevision = effective.overrideRevision
        } else {
            usesEffectiveClassification = false
            classificationStatus = product.classificationStatus
            effectiveSource = nil
            categoryCode = product.categoryCode
            garmentTypeCode = product.garmentTypeCode
            audienceCode = product.audienceCode
            sleeveLengthCode = product.sleeveLengthCode
            lowerLengthCode = product.lowerLengthCode
            bodyLengthCode = product.bodyLengthCode
            comparisonPolicyCode = product.comparisonPolicyCode
            productStructureCode = product.productStructureCode
            contractVersion = product.resolverVersion
            authorityFingerprint = nil
            overrideRevision = nil
        }
    }
}

nonisolated struct VNextUserClassificationMutationDTO:
    Decodable, Equatable, Sendable {
    let saved: Bool?
    let cleared: Bool?
    let idempotent: Bool
    let event: String?
    let override: VNextUserProductClassificationOverrideDTO?
    let overrideID: UUID?
    let revision: Int?
    let effectiveClassification: VNextEffectiveTargetClassificationDTO

    enum CodingKeys: String, CodingKey {
        case saved, cleared, idempotent, event, override, revision
        case overrideID = "override_id"
        case effectiveClassification = "effective_classification"
    }
}

nonisolated struct VNextProductRuntimeDTO: Decodable, Equatable, Sendable {
    let found: Bool
    let product: VNextRuntimeProductDTO?
    let readiness: VNextProductReadinessDTO?
    let variants: [VNextRuntimeVariantDTO]
    let effectiveClassification: VNextEffectiveTargetClassificationDTO?

    enum CodingKeys: String, CodingKey {
        case found, product, readiness, variants
        case effectiveClassification = "effective_classification"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        found = try container.decodeIfPresent(Bool.self, forKey: .found) ?? false
        product = try container.decodeIfPresent(VNextRuntimeProductDTO.self, forKey: .product)
        readiness = try container.decodeIfPresent(VNextProductReadinessDTO.self, forKey: .readiness)
        variants = try container.decodeIfPresent(
            [VNextRuntimeVariantDTO].self,
            forKey: .variants
        ) ?? []
        effectiveClassification = try container.decodeIfPresent(
            VNextEffectiveTargetClassificationDTO.self,
            forKey: .effectiveClassification
        )
    }
}

nonisolated struct VNextClosetMeasurementDTO: Decodable, Equatable, Sendable {
    let measurementCode: String
    let value: Double
    let unitCode: String
    let valueSource: String
    let rawLabelSnapshot: String?

    enum CodingKeys: String, CodingKey {
        case measurementCode = "fitmatch_measurement_code"
        case value
        case unitCode = "unit_code"
        case valueSource = "value_source"
        case rawLabelSnapshot = "raw_label_snapshot"
    }
}

nonisolated struct VNextClosetItemDTO: Decodable, Equatable, Sendable {
    let id: UUID
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
    let categoryCode: String?
    let garmentTypeCode: String
    let sleeveLengthCode: String?
    let lowerLengthCode: String?
    let bodyLengthCode: String?
    let classificationSource: String
    let classificationFingerprint: String?
    let classificationResolverVersion: String?
    let sourceCode: String
    let sourceProductKey: String?
    let sourceCategoryPath: String?
    let isReference: Bool
    let fitPreferenceCode: String?
    let notes: String?
    let satisfaction: Int?
    let createdAt: String
    let updatedAt: String
    let measurements: [VNextClosetMeasurementDTO]

    enum CodingKeys: String, CodingKey {
        case id
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
        case categoryCode = "category_code"
        case garmentTypeCode = "garment_type_code"
        case sleeveLengthCode = "sleeve_length_code"
        case lowerLengthCode = "lower_length_code"
        case bodyLengthCode = "body_length_code"
        case classificationSource = "classification_source"
        case classificationFingerprint = "classification_fingerprint"
        case classificationResolverVersion = "classification_resolver_version"
        case sourceCode = "source_code"
        case sourceProductKey = "source_product_key"
        case sourceCategoryPath = "source_category_path"
        case isReference = "is_reference"
        case fitPreferenceCode = "fit_preference_code"
        case notes, satisfaction
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case measurements
    }
}

nonisolated struct VNextComparisonAuthorizationDTO: Decodable, Equatable, Sendable {
    let decision: String
    let allowed: Bool
    let mode: String
    let reasonCode: String?
    let reason: String?
    let referenceMeasurementDomain: String?
    let targetMeasurementDomain: String?
    let usedMeasurementCodes: [String]
    let excludedMeasurementCodes: [String]
    let excludedMeasurementReasons: [VNextMeasurementExclusionReasonDTO]
    let requiredMeasurementCodes: [String]
    let minimumCommon: Int?
    let commonMeasurementCount: Int?
    let requiredAnyCount: Int?
    let policyCode: String?
    let policyVersion: String?
    let policyChecksum: String?

    enum CodingKeys: String, CodingKey {
        case decision, allowed, mode, reason
        case reasonCode = "reason_code"
        case referenceMeasurementDomain = "reference_measurement_domain"
        case targetMeasurementDomain = "target_measurement_domain"
        case usedMeasurementCodes = "used_measurement_codes"
        case excludedMeasurementCodes = "excluded_measurement_codes"
        case excludedMeasurementReasons = "excluded_measurement_reasons"
        case requiredMeasurementCodes = "required_measurement_codes"
        case minimumCommon = "minimum_common"
        case commonMeasurementCount = "common_measurement_count"
        case requiredAnyCount = "required_any_count"
        case policyCode = "policy_code"
        case policyVersion = "policy_version"
        case policyChecksum = "policy_checksum"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        decision = try container.decodeIfPresent(String.self, forKey: .decision) ?? "BLOCKED"
        allowed = try container.decodeIfPresent(Bool.self, forKey: .allowed) ?? false
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? "NONE"
        reasonCode = try container.decodeIfPresent(String.self, forKey: .reasonCode)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        referenceMeasurementDomain = try container.decodeIfPresent(
            String.self,
            forKey: .referenceMeasurementDomain
        )
        targetMeasurementDomain = try container.decodeIfPresent(
            String.self,
            forKey: .targetMeasurementDomain
        )
        usedMeasurementCodes = try container.decodeIfPresent(
            [String].self,
            forKey: .usedMeasurementCodes
        ) ?? []
        excludedMeasurementCodes = try container.decodeIfPresent(
            [String].self,
            forKey: .excludedMeasurementCodes
        ) ?? []
        excludedMeasurementReasons = try container.decodeIfPresent(
            [VNextMeasurementExclusionReasonDTO].self,
            forKey: .excludedMeasurementReasons
        ) ?? []
        requiredMeasurementCodes = try container.decodeIfPresent(
            [String].self,
            forKey: .requiredMeasurementCodes
        ) ?? []
        minimumCommon = try container.decodeIfPresent(Int.self, forKey: .minimumCommon)
        commonMeasurementCount = try container.decodeIfPresent(
            Int.self,
            forKey: .commonMeasurementCount
        )
        requiredAnyCount = try container.decodeIfPresent(Int.self, forKey: .requiredAnyCount)
        policyCode = try container.decodeIfPresent(String.self, forKey: .policyCode)
        policyVersion = try container.decodeIfPresent(String.self, forKey: .policyVersion)
        policyChecksum = try container.decodeIfPresent(String.self, forKey: .policyChecksum)
    }
}

nonisolated struct VNextMeasurementExclusionReasonDTO: Decodable, Equatable, Sendable {
    let measurementCode: String
    let reasonCode: String

    enum CodingKeys: String, CodingKey {
        case measurementCode = "measurement_code"
        case reasonCode = "reason_code"
    }
}

nonisolated struct VNextReferenceCandidateDTO: Decodable, Equatable, Sendable {
    let closetItemID: UUID
    let itemName: String
    let sizeLabel: String?
    let productID: UUID?
    let variantID: UUID?
    let productSizeID: UUID?
    let isCurrentReference: Bool
    let decision: String
    let allowed: Bool
    let mode: String
    let manualExplicitRequired: Bool
    let reasonCode: String?
    let reason: String?
    let commonMeasurementCount: Int?
    let usedMeasurementCodes: [String]?
    let excludedMeasurementCodes: [String]?
    let excludedMeasurementReasons: [VNextMeasurementExclusionReasonDTO]?
    let referenceMeasurementDomain: String?
    let targetMeasurementDomain: String?
    let eligibleProductSizeIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case closetItemID = "closet_item_id"
        case itemName = "item_name"
        case sizeLabel = "size_label"
        case productID = "product_id"
        case variantID = "variant_id"
        case productSizeID = "product_size_id"
        case isCurrentReference = "is_current_reference"
        case decision, allowed, mode, reason
        case reasonCode = "reason_code"
        case manualExplicitRequired = "manual_explicit_required"
        case commonMeasurementCount = "common_measurement_count"
        case usedMeasurementCodes = "used_measurement_codes"
        case excludedMeasurementCodes = "excluded_measurement_codes"
        case excludedMeasurementReasons = "excluded_measurement_reasons"
        case referenceMeasurementDomain = "reference_measurement_domain"
        case targetMeasurementDomain = "target_measurement_domain"
        case eligibleProductSizeIDs = "eligible_product_size_ids"
    }
}

nonisolated struct VNextReferenceCandidatesDTO: Decodable, Equatable, Sendable {
    let targetProductID: UUID
    let targetVariantID: UUID
    let candidates: [VNextReferenceCandidateDTO]
    let blocked: [VNextReferenceCandidateDTO]
    let status: String

    enum CodingKeys: String, CodingKey {
        case targetProductID = "target_product_id"
        case targetVariantID = "target_variant_id"
        case candidates, blocked, status
    }
}

nonisolated struct VNextAuthorizedMeasurementDTO: Codable, Equatable, Sendable {
    let measurementCode: String
    let referenceValue: Double
    let targetValue: Double
    let difference: Double
    let absoluteDifference: Double
    let unitCode: String
    let basisCode: String?
    let weight: Double
    let requirementMode: String
    let priority: Int

    enum CodingKeys: String, CodingKey {
        case measurementCode = "measurement_code"
        case referenceValue = "reference_value"
        case targetValue = "target_value"
        case difference
        case absoluteDifference = "absolute_difference"
        case unitCode = "unit_code"
        case basisCode = "basis_code"
        case weight
        case requirementMode = "requirement_mode"
        case priority
    }
}

nonisolated struct VNextAuthorizedCandidateDTO: Decodable, Equatable, Sendable {
    let productSizeID: UUID
    let sizeLabel: String
    let availability: VNextAvailabilityDTO
    let comparisonMeasurements: [VNextAuthorizedMeasurementDTO]
    let authorization: VNextComparisonAuthorizationDTO

    enum CodingKeys: String, CodingKey {
        case productSizeID = "product_size_id"
        case sizeLabel = "size_label"
        case availability
        case comparisonMeasurements = "comparison_measurements"
        case authorization
    }
}

nonisolated struct VNextEligibleCandidateSizesDTO: Decodable, Equatable, Sendable {
    let allowed: Bool
    let decision: String
    let mode: String
    let reasonCode: String?
    let reason: String?
    let referenceClosetItemID: UUID?
    let targetProductID: UUID?
    let targetVariantID: UUID?
    let authorizedCandidateProductSizeIDs: [UUID]
    let candidates: [VNextAuthorizedCandidateDTO]
    let candidateAuthorityFingerprint: String?
    let effectiveAuthorityFingerprint: String?
    let effectiveSource: String?
    let personalOverrideRevision: Int?

    enum CodingKeys: String, CodingKey {
        case allowed, decision, mode, reason, candidates
        case reasonCode = "reason_code"
        case referenceClosetItemID = "reference_closet_item_id"
        case targetProductID = "target_product_id"
        case targetVariantID = "target_variant_id"
        case authorizedCandidateProductSizeIDs = "authorized_candidate_product_size_ids"
        case candidateAuthorityFingerprint = "candidate_authority_fingerprint"
        case effectiveAuthorityFingerprint = "effective_authority_fingerprint"
        case effectiveSource = "classification_source"
        case personalOverrideRevision = "override_revision"
    }
}

nonisolated struct VNextComparisonPolicyMetricDTO: Decodable, Equatable, Sendable {
    let metricMode: String
    let measurementCode: String?
    let weight: Double
    let requirementMode: String
    let priority: Int
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case metricMode = "metric_mode"
        case measurementCode = "fitmatch_measurement_code"
        case weight, priority
        case requirementMode = "requirement_mode"
        case isActive = "is_active"
    }
}

nonisolated struct VNextComparisonPolicySnapshotDTO: Decodable, Equatable, Sendable {
    let policyCode: String?
    let policyVersion: String?
    let policyChecksum: String?
    let metrics: [VNextComparisonPolicyMetricDTO]

    enum CodingKeys: String, CodingKey {
        case policyCode = "policy_code"
        case policyVersion = "policy_version"
        case policyChecksum = "policy_checksum"
        case metrics
    }
}

nonisolated struct VNextComparisonTargetSnapshotDTO: Decodable, Equatable, Sendable {
    let productID: UUID
    let variantID: UUID
    let authorizedCandidateProductSizeIDs: [UUID]
    let candidateAuthorityFingerprint: String?
    let classificationStatus: String
    let garmentTypeCode: String?
    let sleeveLengthCode: String?
    let lowerLengthCode: String?
    let bodyLengthCode: String?
    let candidates: [VNextAuthorizedCandidateDTO]

    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case variantID = "variant_id"
        case authorizedCandidateProductSizeIDs = "authorized_candidate_product_size_ids"
        case candidateAuthorityFingerprint = "candidate_authority_fingerprint"
        case classificationStatus = "classification_status"
        case garmentTypeCode = "garment_type_code"
        case sleeveLengthCode = "sleeve_length_code"
        case lowerLengthCode = "lower_length_code"
        case bodyLengthCode = "body_length_code"
        case candidates
    }
}

nonisolated struct VNextComparisonBeginSnapshotDTO: Decodable, Equatable, Sendable {
    let snapshotSchemaVersion: Int
    let target: VNextComparisonTargetSnapshotDTO
    let policy: VNextComparisonPolicySnapshotDTO
    let authorization: VNextComparisonAuthorizationDTO
    let excludedMeasurementCodes: [String]
    let referenceSnapshot: FitMatchJSONValue
    let authoritySnapshot: FitMatchJSONValue
    let inputSnapshot: FitMatchJSONValue

    enum CodingKeys: String, CodingKey {
        case snapshotSchemaVersion = "snapshot_schema_version"
        case target = "target_snapshot"
        case policy = "policy_snapshot"
        case authorization = "authorization_snapshot"
        case excludedMeasurementCodes = "excluded_measurement_codes"
        case referenceSnapshot = "reference_snapshot"
        case authoritySnapshot = "authority_snapshot"
        case inputSnapshot = "input_snapshot"
    }
}

nonisolated struct VNextBeginComparisonDTO: Decodable, Equatable, Sendable {
    let comparisonID: UUID
    let created: Bool
    let idempotent: Bool
    let resultStatus: String
    let authorization: VNextComparisonAuthorizationDTO?
    let authorizedCandidateProductSizeIDs: [UUID]
    let candidateAuthorityFingerprint: String?
    let effectiveAuthorityFingerprint: String?
    let snapshotSchemaVersion: Int?
    let snapshot: VNextComparisonBeginSnapshotDTO

    enum CodingKeys: String, CodingKey {
        case comparisonID = "comparison_id"
        case created, idempotent
        case resultStatus = "result_status"
        case authorization
        case authorizedCandidateProductSizeIDs = "authorized_candidate_product_size_ids"
        case candidateAuthorityFingerprint = "candidate_authority_fingerprint"
        case effectiveAuthorityFingerprint = "effective_authority_fingerprint"
        case snapshotSchemaVersion = "snapshot_schema_version"
        case snapshot
    }
}

extension VNextBeginComparisonDTO {
    /// A same-ID replay is the original immutable begin snapshot, not a new
    /// weaker authorization. Older RPC envelopes omitted duplicated top-level
    /// proof fields even though the owned `snapshot` already contained them.
    /// Only that immutable snapshot is used as a fallback here; current
    /// runtime authority is never consulted or synthesized.
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        comparisonID = try container.decode(UUID.self, forKey: .comparisonID)
        created = try container.decodeIfPresent(Bool.self, forKey: .created) ?? false
        idempotent = try container.decodeIfPresent(Bool.self, forKey: .idempotent) ?? false
        resultStatus = try container.decodeIfPresent(String.self, forKey: .resultStatus) ?? "PENDING"
        snapshot = try container.decode(VNextComparisonBeginSnapshotDTO.self, forKey: .snapshot)
        authorization = try container.decodeIfPresent(
            VNextComparisonAuthorizationDTO.self,
            forKey: .authorization
        ) ?? snapshot.authorization
        authorizedCandidateProductSizeIDs = try container.decodeIfPresent(
            [UUID].self,
            forKey: .authorizedCandidateProductSizeIDs
        ) ?? snapshot.target.authorizedCandidateProductSizeIDs
        candidateAuthorityFingerprint = try container.decodeIfPresent(
            String.self,
            forKey: .candidateAuthorityFingerprint
        ) ?? snapshot.target.candidateAuthorityFingerprint
        effectiveAuthorityFingerprint = try container.decodeIfPresent(
            String.self,
            forKey: .effectiveAuthorityFingerprint
        ) ?? snapshot.inputSnapshot.objectValue?["effective_authority_fingerprint"]?.stringValue
        snapshotSchemaVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .snapshotSchemaVersion
        ) ?? snapshot.snapshotSchemaVersion
    }
}

nonisolated struct VNextCandidateRankingDTO: Codable, Equatable, Sendable {
    let productSizeID: UUID
    let rank: Int
    let score: Double

    enum CodingKeys: String, CodingKey {
        case productSizeID = "product_size_id"
        case rank, score
    }
}

nonisolated struct VNextMetricEvidenceDTO: Codable, Equatable, Sendable {
    let productSizeID: UUID
    let measurementCode: String
    let referenceValue: Double
    let targetValue: Double
    let difference: Double
    let absoluteDifference: Double
    let weight: Double

    enum CodingKeys: String, CodingKey {
        case productSizeID = "product_size_id"
        case measurementCode = "measurement_code"
        case referenceValue = "reference_value"
        case targetValue = "target_value"
        case difference
        case absoluteDifference = "absolute_difference"
        case weight
    }
}

nonisolated struct VNextComparisonCompletionPayload: Codable, Equatable, Sendable {
    let recommendedProductSizeID: UUID
    let score: Double
    let reliability: Int
    let coverage: Double
    let engineVersion: String
    let candidateSizeRanking: [VNextCandidateRankingDTO]
    let metricEvidence: [VNextMetricEvidenceDTO]

    enum CodingKeys: String, CodingKey {
        case recommendedProductSizeID = "recommended_product_size_id"
        case score, reliability, coverage
        case engineVersion = "engine_version"
        case candidateSizeRanking = "candidate_size_ranking"
        case metricEvidence = "metric_evidence"
    }
}

nonisolated struct VNextCompleteComparisonDTO: Decodable, Equatable, Sendable {
    let comparisonID: UUID
    let completed: Bool
    let idempotent: Bool
    let recommendedProductSizeID: UUID
    let recommendedSizeLabel: String
    let validatedEvidenceCount: Int?
    let coverage: Double?

    enum CodingKeys: String, CodingKey {
        case comparisonID = "comparison_id"
        case completed, idempotent
        case recommendedProductSizeID = "recommended_product_size_id"
        case recommendedSizeLabel = "recommended_size_label"
        case validatedEvidenceCount = "validated_evidence_count"
        case coverage
    }
}

nonisolated struct VNextComparisonHistoryVisibilityDTO: Decodable, Equatable, Sendable {
    let clientComparisonIDs: [UUID]
    let hidden: Bool
    let idempotent: Bool

    enum CodingKeys: String, CodingKey {
        case clientComparisonIDs = "client_comparison_ids"
        case hidden, idempotent
    }
}

nonisolated struct VNextComparisonHistoryDTO: Decodable, Equatable, Sendable {
    let id: UUID
    let clientComparisonID: UUID
    let referenceClientItemID: UUID?
    let targetProductID: UUID
    let targetVariantID: UUID
    let targetProductName: String
    let targetImageURL: String?
    let targetSourceCode: String
    let targetSourceProductKey: String?
    let targetCanonicalURL: String?
    let targetCategoryCode: String?
    let resultStatus: String
    let recommendedProductSizeID: UUID?
    let recommendedSizeLabel: String?
    let fitScore: Double?
    let reliabilityLevel: Int?
    let coverageRatio: Double?
    let engineVersion: String
    let resultEvidence: VNextComparisonCompletionPayload?
    let createdAt: String
    let snapshotSchemaVersion: Int
    let excludedMeasurementCodes: [String]
    let referenceSnapshot: FitMatchJSONValue
    let targetSnapshot: VNextComparisonTargetSnapshotDTO?
    let authoritySnapshot: FitMatchJSONValue
    let policySnapshot: VNextComparisonPolicySnapshotDTO?
    let authorizationSnapshot: VNextComparisonAuthorizationDTO?
    let inputSnapshot: FitMatchJSONValue

    enum CodingKeys: String, CodingKey {
        case id
        case clientComparisonID = "client_comparison_id"
        case referenceClientItemID = "reference_client_item_id"
        case targetProductID = "target_product_id"
        case targetVariantID = "target_variant_id"
        case targetProductName = "target_product_name_snapshot"
        case targetImageURL = "target_image_url_snapshot"
        case targetSourceCode = "target_source_code_snapshot"
        case targetSourceProductKey = "target_source_product_key"
        case targetCanonicalURL = "target_canonical_url"
        case targetCategoryCode = "target_category_code"
        case resultStatus = "result_status"
        case recommendedProductSizeID = "recommended_product_size_id"
        case recommendedSizeLabel = "recommended_size_label"
        case fitScore = "fit_score"
        case reliabilityLevel = "reliability_level"
        case coverageRatio = "coverage_ratio"
        case engineVersion = "engine_version"
        case resultEvidence = "result_evidence"
        case createdAt = "created_at"
        case snapshotSchemaVersion = "snapshot_schema_version"
        case excludedMeasurementCodes = "excluded_measurement_codes"
        case referenceSnapshot = "reference_snapshot"
        case targetSnapshot = "target_snapshot"
        case authoritySnapshot = "authority_snapshot"
        case policySnapshot = "policy_snapshot"
        case authorizationSnapshot = "authorization_snapshot"
        case inputSnapshot = "input_snapshot"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        clientComparisonID = try container.decode(UUID.self, forKey: .clientComparisonID)
        referenceClientItemID = try container.decodeIfPresent(
            UUID.self,
            forKey: .referenceClientItemID
        )
        targetProductID = try container.decode(UUID.self, forKey: .targetProductID)
        targetVariantID = try container.decode(UUID.self, forKey: .targetVariantID)
        targetProductName = try container.decodeIfPresent(
            String.self,
            forKey: .targetProductName
        ) ?? "FitMatch 상품"
        targetImageURL = try container.decodeIfPresent(String.self, forKey: .targetImageURL)
        targetSourceCode = try container.decodeIfPresent(
            String.self,
            forKey: .targetSourceCode
        ) ?? "unknown"
        targetSourceProductKey = try container.decodeIfPresent(
            String.self,
            forKey: .targetSourceProductKey
        )
        targetCanonicalURL = try container.decodeIfPresent(
            String.self,
            forKey: .targetCanonicalURL
        )
        targetCategoryCode = try container.decodeIfPresent(
            String.self,
            forKey: .targetCategoryCode
        )
        resultStatus = try container.decode(String.self, forKey: .resultStatus)
        recommendedProductSizeID = try container.decodeIfPresent(
            UUID.self,
            forKey: .recommendedProductSizeID
        )
        recommendedSizeLabel = try container.decodeIfPresent(
            String.self,
            forKey: .recommendedSizeLabel
        )
        fitScore = try container.decodeIfPresent(Double.self, forKey: .fitScore)
        reliabilityLevel = try container.decodeIfPresent(Int.self, forKey: .reliabilityLevel)
        coverageRatio = try container.decodeIfPresent(Double.self, forKey: .coverageRatio)
        engineVersion = try container.decodeIfPresent(
            String.self,
            forKey: .engineVersion
        ) ?? "unknown"
        resultEvidence = try? container.decode(
            VNextComparisonCompletionPayload.self,
            forKey: .resultEvidence
        )
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        snapshotSchemaVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .snapshotSchemaVersion
        ) ?? 0
        excludedMeasurementCodes = try container.decodeIfPresent(
            [String].self,
            forKey: .excludedMeasurementCodes
        ) ?? []
        referenceSnapshot = try container.decodeIfPresent(
            FitMatchJSONValue.self,
            forKey: .referenceSnapshot
        ) ?? .object([:])
        targetSnapshot = try? container.decode(
            VNextComparisonTargetSnapshotDTO.self,
            forKey: .targetSnapshot
        )
        authoritySnapshot = try container.decodeIfPresent(
            FitMatchJSONValue.self,
            forKey: .authoritySnapshot
        ) ?? .object([:])
        policySnapshot = try? container.decode(
            VNextComparisonPolicySnapshotDTO.self,
            forKey: .policySnapshot
        )
        authorizationSnapshot = try? container.decode(
            VNextComparisonAuthorizationDTO.self,
            forKey: .authorizationSnapshot
        )
        inputSnapshot = try container.decodeIfPresent(
            FitMatchJSONValue.self,
            forKey: .inputSnapshot
        ) ?? .object([:])
    }

    var snapshotBegin: VNextBeginComparisonDTO? {
        guard let targetSnapshot,
              let policySnapshot,
              let authorizationSnapshot,
              snapshotSchemaVersion >= 3,
              authorizationSnapshot.allowed,
              !targetSnapshot.authorizedCandidateProductSizeIDs.isEmpty else {
            return nil
        }
        return VNextBeginComparisonDTO(
            comparisonID: id,
            created: false,
            idempotent: true,
            resultStatus: "PENDING",
            authorization: authorizationSnapshot,
            authorizedCandidateProductSizeIDs:
                targetSnapshot.authorizedCandidateProductSizeIDs,
            candidateAuthorityFingerprint:
                targetSnapshot.candidateAuthorityFingerprint,
            effectiveAuthorityFingerprint: inputSnapshot.objectValue?[
                "effective_authority_fingerprint"
            ]?.stringValue,
            snapshotSchemaVersion: snapshotSchemaVersion,
            snapshot: VNextComparisonBeginSnapshotDTO(
                snapshotSchemaVersion: snapshotSchemaVersion,
                target: targetSnapshot,
                policy: policySnapshot,
                authorization: authorizationSnapshot,
                excludedMeasurementCodes: excludedMeasurementCodes,
                referenceSnapshot: referenceSnapshot,
                authoritySnapshot: authoritySnapshot,
                inputSnapshot: inputSnapshot
            )
        )
    }

    var pendingBegin: VNextBeginComparisonDTO? {
        resultStatus == "PENDING" ? snapshotBegin : nil
    }
}
