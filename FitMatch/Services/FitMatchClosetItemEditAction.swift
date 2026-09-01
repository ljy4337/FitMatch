import Foundation
import SwiftData

/// The non-visual persistence actions behind Closet detail editing.  This
/// keeps the detail View as the presentation owner (including its reference
/// replacement confirmation) while ensuring that manual and imported edits
/// have one production implementation available to headless callers.
@MainActor
enum FitMatchClosetItemEditAction {
    enum Outcome: Equatable {
        case saved
        case persistenceFailed
    }

    /// Applies the exact direct/manual edit mutation used after the detail
    /// screen has resolved any reference-replacement confirmation.
    static func saveManual(
        item: UserFit,
        editedItem: UserFit,
        activeClosetItems: [UserFit],
        in modelContext: ModelContext,
        now: Date = Date(),
        performSave: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Outcome {
        item.sourceType = editedItem.sourceType
        item.sourceName = editedItem.sourceName
        item.brandName = editedItem.brandName
        item.gender = editedItem.gender
        item.genderCode = editedItem.resolvedGenderCode
        item.productName = editedItem.productName
        item.category = editedItem.category
        item.detailCategory = editedItem.detailCategory
        item.categoryCode = editedItem.resolvedCategoryCode
        item.detailCategoryCode = editedItem.resolvedDetailCategoryCode
        item.normalizedProductTypeCode = editedItem.resolvedNormalizedProductTypeCode
        // `category` / `detailCategory` setters intentionally clear cached
        // comparison attributes while a form is being edited. The form has
        // already resolved its own explicit Closet classification before this
        // persistence action is called, so retain that exact form snapshot
        // rather than leaving a formerly valid reference without a family or
        // sleeve when only its measurements are saved.
        item.garmentTypeRawValue = editedItem.garmentTypeRawValue
        item.sleeveTypeRawValue = editedItem.sleeveTypeRawValue
        item.constructionTypeRawValue = editedItem.constructionTypeRawValue
        item.canonicalProfileSnapshotJSON = editedItem.canonicalProfileSnapshotJSON
        item.canonicalPolicyVersion = editedItem.canonicalPolicyVersion
        item.sizeName = editedItem.sizeName
        item.measurements = editedItem.measurements
        item.fitMemo = editedItem.fitMemo
        item.fitPreference = editedItem.fitPreference
        item.satisfaction = editedItem.satisfaction
        item.isRepresentative = editedItem.isRepresentative
        item.measurementRecords.forEach(modelContext.delete)
        item.replaceMeasurementRecords(with: editedItem.measurementRecords)
        _ = ComparisonProfileMatcher().profile(for: item)

        if item.isRepresentative {
            activeClosetItems
                .filter {
                    $0.id != item.id
                        && $0.isRepresentative
                        && ReferenceGarmentPolicy.conflicts($0, item)
                }
                .forEach {
                    $0.isRepresentative = false
                    $0.updatedAt = now
                }
        }
        item.updatedAt = now
        return persist(in: modelContext, using: performSave)
    }

    /// Applies an imported item's selected-size update and the existing
    /// explicit-Closet-picker authority rule. A size-only sourced edit never
    /// manufactures a personal classification authority.
    static func saveImported(
        item: UserFit,
        selectedSize: ProductSize,
        category: ClothingCategory,
        detailCategory: ClosetDetailCategory,
        categoryCode: String,
        detailCode: String,
        didExplicitlyChangeClassification: Bool,
        in modelContext: ModelContext,
        now: Date = Date(),
        performSave: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Outcome {
        let resultingAuthority = FitMatchClosetClassificationEditPolicy.resultingAuthority(
            current: item.classificationAuthorityProvenance,
            isSourced: FitMatchClosetClassificationEditPolicy.isSourced(item),
            isExplicitSet: FitMatchClosetClassificationEditPolicy.isExplicitSet(item),
            didExplicitlyChangeClassification: didExplicitlyChangeClassification,
            scope: .existingClosetItem
        )
        if didExplicitlyChangeClassification, resultingAuthority == .userExplicit {
            item.category = category
            item.detailCategory = detailCategory
            item.categoryCode = categoryCode
            item.detailCategoryCode = detailCode
            item.normalizedProductTypeCode = detailCode
            _ = ComparisonProfileMatcher().profile(for: item)
            item.markClassificationAuthority(
                .userExplicit,
                sourceIdentity: "user_explicit_closet_edit"
            )
        } else {
            item.markClassificationAuthority(
                resultingAuthority,
                sourceIdentity: resultingAuthority == .localHint
                    ? "ios_existing_set_validation"
                    : item.canonicalSourceIdentity
            )
        }
        item.sizeName = selectedSize.name.fitMatchDisplaySizeName
        item.measurements = selectedSize.measurements
        item.sourceProductSize = selectedSize
        item.measurementRecords.forEach(modelContext.delete)
        item.replaceMeasurementRecords(with: selectedSize.measurementRecords)
        item.updatedAt = now
        return persist(in: modelContext, using: performSave)
    }

    private static func persist(
        in modelContext: ModelContext,
        using persist: (ModelContext) throws -> Void
    ) -> Outcome {
        do {
            try persist(modelContext)
            return .saved
        } catch {
            modelContext.rollback()
            return .persistenceFailed
        }
    }
}
