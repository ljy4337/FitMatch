import Foundation

/// The production action behind a new manual Closet registration.  It keeps
/// the form's own validation/`UserFit` construction intact, then applies the
/// existing reference-conflict policy before persistence.  A new manual
/// reference therefore cannot leave two conflicting active references merely
/// because it was created from the registration sheet rather than edited
/// later in the detail screen.
@MainActor
enum FitMatchClosetManualRegistrationAction {
    static func save(
        from viewModel: AddClosetItemViewModel,
        activeClosetItems: [UserFit],
        persist: (UserFit) -> Bool
    ) -> FitMatchClosetFormAction.Outcome {
        FitMatchClosetFormAction.save(from: viewModel) { item in
            let conflictingReferences = activeClosetItems.filter {
                $0.id != item.id
                    && $0.isRepresentative
                    && ReferenceGarmentPolicy.conflicts($0, item)
            }
            let priorReferenceState = conflictingReferences.map {
                (item: $0, isRepresentative: $0.isRepresentative, updatedAt: $0.updatedAt)
            }
            if item.isRepresentative {
                FitMatchClosetReferenceMutation.setRepresentative(
                    item,
                    among: activeClosetItems
                )
            }
            guard persist(item) else {
                // A failed new-item save cannot leave an already-persisted
                // reference silently unset. This matters even when the
                // persistence boundary rolls back its context, because a
                // test/local failure boundary may simply return `false`.
                priorReferenceState.forEach { prior in
                    prior.item.isRepresentative = prior.isRepresentative
                    prior.item.updatedAt = prior.updatedAt
                }
                return false
            }
            return true
        }
    }
}
