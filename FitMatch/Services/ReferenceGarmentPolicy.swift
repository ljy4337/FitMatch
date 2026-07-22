import Foundation

enum ReferenceGarmentPolicy {
    static func conflicts(_ lhs: UserFit, _ rhs: UserFit) -> Bool {
        guard lhs.resolvedGenderCode == rhs.resolvedGenderCode,
              lhs.resolvedCategoryCode == rhs.resolvedCategoryCode,
              lhs.resolvedDetailCategoryCode == rhs.resolvedDetailCategoryCode else {
            return false
        }
        return true
    }
}
