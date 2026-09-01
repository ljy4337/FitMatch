import Foundation

enum SizeTableRecoveryFeature {
    static let isEnabled = true
}

enum SizeTableRecoveryFailure: String, Equatable {
    case imageCandidatesAvailable
    case incompleteOCR
    case noImageCandidates
}

struct SizeTableRecoveryContext: Equatable {
    var failure: SizeTableRecoveryFailure
    var imageURLStrings: [String]
}

enum SizeTableRecoveryValidator {
    static func validationMessage(
        for forms: [ClothingSizeForm],
        category: ClothingCategory,
        detailCategory: ClosetDetailCategory
    ) -> String? {
        let names = forms.map { ParsedProductSizeNormalizer.normalizedSizeKey(for: $0.sizeName) }
        if names.contains(where: \.isEmpty) {
            return "모든 행에 사이즈명을 입력해 주세요."
        }
        if Set(names).count != names.count {
            return "중복된 사이즈명은 저장할 수 없습니다."
        }
        if forms.contains(where: {
            $0.makeSizeOption(category: category, detailCategory: detailCategory) == nil
        }) {
            return "각 사이즈 행에 비교 가능한 치수를 입력해 주세요."
        }
        return nil
    }
}

/// The non-visual completion action shared by `SizeTableRecoveryView` and
/// headless callers. It owns only the existing selected-size validation and
/// recovery selection side effect; it does not infer a size or alter any
/// comparison policy.
@MainActor
enum FitMatchSizeTableRecoveryAction {
    enum Outcome: Equatable {
        case completed(selectedSizeID: UUID)
        case blocked(String)
    }

    static func complete(
        selectedSize: ClothingSizeForm?,
        viewModel: ShoppingProductViewModel
    ) -> Outcome {
        guard let selectedSize else {
            return .blocked("비교할 사이즈를 선택해 주세요.")
        }
        if let message = SizeTableRecoveryValidator.validationMessage(
            for: [selectedSize],
            category: viewModel.category,
            detailCategory: viewModel.detailCategory
        ) {
            return .blocked(message)
        }

        viewModel.recoverySelectedSizeID = selectedSize.id
        return .completed(selectedSizeID: selectedSize.id)
    }
}
