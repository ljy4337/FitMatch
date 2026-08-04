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
        product.canonicalProfileSnapshotJSON = CanonicalProfileSnapshotCoder.encode(profile)
        product.canonicalPolicyVersion = profile.policyVersion
        product.canonicalResolutionMethod = profile.resolutionMethod
        product.canonicalSourceIdentity = profile.sourceIdentity
        product.canonicalEligibility = profile.eligibility
        if let family = profile.appGarmentFamily { product.garmentType = family }
        if let length = profile.appLengthType { product.sleeveType = length }
        if let construction = profile.appConstructionType, construction != .unknown {
            product.constructionType = construction
        }
    }

    func apply(_ profile: CanonicalComparisonProfile?, to item: UserFit) {
        guard let profile else { return }
        item.canonicalProfileSnapshotJSON = CanonicalProfileSnapshotCoder.encode(profile)
        item.canonicalPolicyVersion = profile.policyVersion
        item.canonicalResolutionMethod = profile.resolutionMethod
        item.canonicalSourceIdentity = profile.sourceIdentity
        item.canonicalEligibility = profile.eligibility
        if let family = profile.appGarmentFamily { item.garmentType = family }
        if let length = profile.appLengthType { item.sleeveType = length }
        if let construction = profile.appConstructionType, construction != .unknown {
            item.constructionType = construction
        }
    }
}
