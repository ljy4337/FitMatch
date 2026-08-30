import Foundation

/// Identifies who supplied the classification currently stored on a local model.
///
/// This intentionally reuses `canonicalResolutionMethod` so the server-authority
/// integration does not require a SwiftData schema migration.
enum FitMatchClassificationAuthorityProvenance: String, Codable, Sendable {
    case serverConfirmed = "server_confirmed"
    case userExplicit = "user_explicit"
    case localHint = "local_hint"
    case serverReviewRequired = "server_review_required"
    case serverNotComparable = "server_not_comparable"
    case serverUnavailable = "server_unavailable"

    var isComparisonAuthority: Bool {
        self == .serverConfirmed || self == .userExplicit
    }

    static func storedValue(_ value: String?) -> Self? {
        guard let value else { return nil }
        if let exact = Self(rawValue: value) { return exact }

        // Existing server rows already use this value for a user-authored
        // classification override. Preserve that provenance during lazy sync.
        if value == "manual_override" || value == "user_confirmed_closet_classification" {
            return .userExplicit
        }
        return nil
    }
}

/// Keeps a sourced item's fail-closed server state from becoming a user
/// override merely because an editable picker was shown.
enum FitMatchClosetClassificationEditPolicy {
    static func resultingAuthority(
        current: FitMatchClassificationAuthorityProvenance?,
        isSourced: Bool,
        isExplicitSet: Bool,
        didExplicitlyChangeClassification: Bool
    ) -> FitMatchClassificationAuthorityProvenance {
        // A composite garment set is never a comparison authority, regardless
        // of whether it came from a retailer import or the manual Closet form.
        if isExplicitSet {
            switch current {
            case .serverReviewRequired, .serverNotComparable, .serverUnavailable:
                return current ?? .localHint
            default:
                break
            }
            return .localHint
        }

        if isSourced {
            switch current {
            case .serverReviewRequired, .serverNotComparable, .serverUnavailable:
                return current ?? .serverUnavailable
            default:
                break
            }
        }

        if didExplicitlyChangeClassification {
            return .userExplicit
        }
        return current ?? .localHint
    }

    static func isSourced(_ product: Product) -> Bool {
        product.sourceType != .manual
    }

    static func isSourced(_ item: UserFit) -> Bool {
        item.sourceType != .manual || item.sourceProduct != nil
    }

    static func isExplicitSet(_ product: Product) -> Bool {
        let structure = FitMatchStoredRetailerFacts.decode(product.labelNames)
            .structuredFacts["product_structure"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return structure == "set"
            || ParsedClosetClassification.isExplicitCompositeGarmentSet(product.name)
    }

    static func isExplicitSet(_ item: UserFit) -> Bool {
        if let product = item.sourceProduct, isExplicitSet(product) {
            return true
        }
        return ParsedClosetClassification.isExplicitCompositeGarmentSet(item.productName)
    }
}

extension Product {
    var classificationAuthorityProvenance: FitMatchClassificationAuthorityProvenance? {
        FitMatchClassificationAuthorityProvenance.storedValue(canonicalResolutionMethod)
    }

    func markClassificationAuthority(
        _ provenance: FitMatchClassificationAuthorityProvenance,
        sourceIdentity: String? = nil
    ) {
        canonicalResolutionMethod = provenance.rawValue
        if let sourceIdentity {
            canonicalSourceIdentity = sourceIdentity
        }
        canonicalEligibility = provenance.isComparisonAuthority
    }
}

extension UserFit {
    var classificationAuthorityProvenance: FitMatchClassificationAuthorityProvenance? {
        FitMatchClassificationAuthorityProvenance.storedValue(canonicalResolutionMethod)
    }

    func markClassificationAuthority(
        _ provenance: FitMatchClassificationAuthorityProvenance,
        sourceIdentity: String? = nil
    ) {
        canonicalResolutionMethod = provenance.rawValue
        if let sourceIdentity {
            canonicalSourceIdentity = sourceIdentity
        }
        canonicalEligibility = provenance.isComparisonAuthority
        if !provenance.isComparisonAuthority {
            isRepresentative = false
        }
    }

    func fitMatchServerReferenceSnapshot() -> FitMatchLocalReferenceSnapshot? {
        guard isActiveClosetItem,
              classificationAuthorityProvenance?.isComparisonAuthority == true,
              !FitMatchClosetClassificationEditPolicy.isExplicitSet(self),
              let categoryCode = resolvedCategoryCode,
              let detailCode = resolvedDetailCategoryCode,
              let familyCode = garmentTypeRawValue?.trimmingCharacters(
                in: .whitespacesAndNewlines
              ),
              !familyCode.isEmpty,
              familyCode != "unknown" else {
            return nil
        }

        var values: [String: Double] = [:]
        for record in measurementRecords where record.value.isFinite && record.value > 0 {
            values[record.measurementCodeRawValue] = record.value
        }
        if values.isEmpty {
            let legacyValues: [(String, Double)] = [
                ("shoulder_width", shoulder),
                ("chest_width", chest),
                ("body_length", totalLength),
                ("sleeve_length", sleeveLength),
                ("waist_width", waist),
                ("hip_width", hip),
                ("thigh_width", thigh),
                ("rise", rise),
                ("hem_width", hem),
                ("foot_length", footLength),
                ("under_bust_width", underBust)
            ]
            for (key, value) in legacyValues where value.isFinite && value > 0 {
                values[key] = value
            }
        }

        let bodyLength = canonicalProfileSnapshot?.lengthAxes.body
        return FitMatchLocalReferenceSnapshot(
            productName: productName,
            sizeName: sizeName.trimmingCharacters(in: .whitespacesAndNewlines),
            categoryCode: categoryCode,
            detailCode: detailCode,
            familyCode: familyCode,
            lengthCode: sleeveTypeRawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
            bodyLengthCode: bodyLength == "unknown" || bodyLength == "not_applicable"
                ? nil
                : bodyLength,
            measurements: values
        )
    }
}
