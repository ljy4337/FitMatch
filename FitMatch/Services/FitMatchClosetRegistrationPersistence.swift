import SwiftData

/// The single local persistence action used after a Closet form has already
/// produced a valid `UserFit`. This intentionally owns no classification,
/// measurement, or reference policy; it only makes the view's save/rollback
/// boundary explicit and headless-callable.
@MainActor
enum FitMatchClosetRegistrationPersistence {
    @discardableResult
    static func save(_ item: UserFit, in modelContext: ModelContext) -> Bool {
        modelContext.insert(item)
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            return false
        }
    }
}
