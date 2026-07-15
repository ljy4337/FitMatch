import Foundation

enum ReferenceGarmentPolicy {
    static func conflicts(_ lhs: UserFit, _ rhs: UserFit) -> Bool {
        guard lhs.resolvedGenderCode == rhs.resolvedGenderCode,
              lhs.resolvedCategoryCode == rhs.resolvedCategoryCode,
              lhs.resolvedDetailCategoryCode == rhs.resolvedDetailCategoryCode else {
            return false
        }

        let lhsType = lhs.resolvedNormalizedProductTypeCode
        let rhsType = rhs.resolvedNormalizedProductTypeCode
        if let lhsType, let rhsType {
            return lhsType == rhsType
        }

        // Unknown product types keep the existing conservative one-reference-per-class behavior.
        return true
    }
}
