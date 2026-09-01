import Foundation

/// Applies the user-confirmed reference-garment change before the caller
/// persists it. The mutation is intentionally small: the existing
/// `ReferenceGarmentPolicy` remains the sole conflict authority, while Views
/// keep their own alert and error presentation.
@MainActor
enum FitMatchClosetReferenceMutation {
    static func setRepresentative(
        _ selectedItem: UserFit,
        among userFits: [UserFit],
        now: Date = Date()
    ) {
        userFits
            .filter {
                $0.id != selectedItem.id
                    && $0.isRepresentative
                    && ReferenceGarmentPolicy.conflicts($0, selectedItem)
            }
            .forEach {
                $0.isRepresentative = false
                $0.updatedAt = now
            }

        selectedItem.isRepresentative = true
        selectedItem.updatedAt = now
    }

    static func clearRepresentative(
        _ item: UserFit,
        now: Date = Date()
    ) {
        item.isRepresentative = false
        item.updatedAt = now
    }
}
