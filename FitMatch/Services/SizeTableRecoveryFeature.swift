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
/// headless callers. Comparison recovery requires a persisted user supplement
/// and a fresh server runtime; local Closet draft selection is separate.
@MainActor
enum FitMatchSizeTableRecoveryAction {
    enum Outcome: Equatable {
        case completed(selectedSizeID: UUID)
        case blocked(String)
    }

    static func loadImage(
        contextID: UUID,
        viewModel: ShoppingProductViewModel,
        userID: UUID?,
        currentUserID: @MainActor () -> UUID?,
        load: @MainActor () async throws -> Data?
    ) async -> Data? {
        guard !Task.isCancelled, viewModel.sizeRecoveryContextID == contextID,
              currentUserID() == userID else { return nil }
        let data = try? await load()
        guard !Task.isCancelled, viewModel.sizeRecoveryContextID == contextID,
              currentUserID() == userID else { return nil }
        return data
    }

    static func completeForClosetRegistration(
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

    static func complete(
        selectedSize: ClothingSizeForm?,
        viewModel: ShoppingProductViewModel,
        userID: UUID?,
        currentUserID: @MainActor () -> UUID?,
        inputSource: String
    ) async -> Outcome {
        guard let selectedSize else { return .blocked("비교할 사이즈를 선택해 주세요.") }
        if let message = SizeTableRecoveryValidator.validationMessage(
            for: [selectedSize], category: viewModel.category, detailCategory: viewModel.detailCategory
        ) { return .blocked(message) }
        guard let userID, currentUserID() == userID else {
            return .blocked("로그인이 필요한 기능입니다. 다시 로그인한 뒤 시도해 주세요.")
        }
        guard await viewModel.completeSizeRecovery(
            selectedSize: selectedSize, inputSource: inputSource,
            userID: userID, currentUserID: currentUserID
        ), let selectedID = viewModel.recoverySelectedSizeID else {
            return .blocked(viewModel.recoveryErrorMessage
                ?? "보완한 사이즈 정보를 서버에서 확인하지 못했어요. 입력을 유지한 채 다시 시도해 주세요.")
        }
        return .completed(selectedSizeID: selectedID)
    }
}
