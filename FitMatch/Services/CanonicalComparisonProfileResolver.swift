import Foundation

struct CanonicalComparisonProfileResolver {
    private let store: CanonicalTaxonomyBundleStore

    init(store: CanonicalTaxonomyBundleStore = .shared) {
        self.store = store
    }

    func resolve(
        source: String?,
        externalCategoryID: String?,
        target: String?,
        sourceCategoryPath: String?
    ) -> CanonicalComparisonProfile? {
        store.profile(for: CanonicalTaxonomyLookupInput(
            source: source,
            externalCategoryID: externalCategoryID,
            target: target,
            sourceCategoryPath: sourceCategoryPath
        ))
    }

    func apply(_ profile: CanonicalComparisonProfile?, to product: Product) {
        guard let profile else { return }
        let preservesClassificationConflict = product.canonicalEligibility == false
            && product.canonicalResolutionMethod
                == ParsedClosetClassificationSafetyAudit.conflictResolutionMethod
        product.canonicalProfileSnapshotJSON = CanonicalProfileSnapshotCoder.encode(profile)
        if !preservesClassificationConflict {
            product.canonicalPolicyVersion = profile.policyVersion
            product.canonicalResolutionMethod = profile.resolutionMethod
            product.canonicalEligibility = profile.eligibility
        }
        product.canonicalSourceIdentity = profile.sourceIdentity
        if let family = profile.appGarmentFamily { product.garmentType = family }
        // A provider-wide canonical path is a fallback. Keep a more specific
        // product classification (name/detail/measurements) when it is already set.
        if product.sleeveType == .unknown, let length = profile.appLengthType {
            product.sleeveType = length
        }
        if let construction = profile.appConstructionType, construction != .unknown {
            product.constructionType = construction
        }
    }

    func apply(_ profile: CanonicalComparisonProfile?, to item: UserFit) {
        guard let profile else { return }
        let preservesClassificationConflict = item.canonicalEligibility == false
            && item.canonicalResolutionMethod
                == ParsedClosetClassificationSafetyAudit.conflictResolutionMethod
        item.canonicalProfileSnapshotJSON = CanonicalProfileSnapshotCoder.encode(profile)
        if !preservesClassificationConflict {
            item.canonicalPolicyVersion = profile.policyVersion
            item.canonicalResolutionMethod = profile.resolutionMethod
            item.canonicalEligibility = profile.eligibility
        }
        item.canonicalSourceIdentity = profile.sourceIdentity
        if let family = profile.appGarmentFamily { item.garmentType = family }
        if item.sleeveType == .unknown, let length = profile.appLengthType {
            item.sleeveType = length
        }
        if let construction = profile.appConstructionType, construction != .unknown {
            item.constructionType = construction
        }
    }
}
