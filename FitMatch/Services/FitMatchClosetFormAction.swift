import Foundation

/// User-visible form validation shared by the manual Closet save control and
/// headless production-action tests. It expresses only existing form state;
/// classification and measurement interpretation remain in the ViewModel.
@MainActor
enum FitMatchClosetFormValidation {
    static func message(for viewModel: AddClosetItemViewModel) -> String? {
        if viewModel.canSave {
            return nil
        }

        if viewModel.gender == .unknown {
            return "성별을 선택해 주세요."
        }

        if viewModel.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "브랜드명을 입력해 주세요."
        }

        if viewModel.productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "상품명을 입력해 주세요."
        }

        if !viewModel.hasValidTaxonomySelection {
            return "선택한 카테고리와 세부 카테고리를 다시 확인해 주세요."
        }

        if !viewModel.measurementKinds.isEmpty, viewModel.measurementEntrySource == nil {
            return "실측 정보를 확인한 출처를 선택해 주세요."
        }

        if viewModel.measurementEntrySource == .otherSizeChart,
           viewModel.measurementSourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "사이즈표를 확인한 쇼핑몰 이름을 입력해 주세요."
        }

        if viewModel.measurementEntrySource == .otherSizeChart,
           viewModel.measurementKinds.contains(where: {
               !viewModel.value(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                   && (viewModel.measurementSourceLabels[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
           }) {
            return "입력한 실측값의 원본 항목명을 입력해 주세요."
        }

        if viewModel.measurements == nil {
            return "실측값을 1개 이상 입력해 주세요. 입력한 값은 0보다 큰 숫자여야 합니다."
        }

        return viewModel.directMeasurementValidationMessage
    }
}

/// The production action behind the manual-form save button. The caller owns
/// its persistence side effect, which keeps editing/link-registration flows
/// intact while making one safe action available to headless tests.
@MainActor
enum FitMatchClosetFormAction {
    enum Outcome {
        case saved(UserFit)
        case blocked(reason: String)
        case persistenceFailed
    }

    static func save(
        from viewModel: AddClosetItemViewModel,
        persist: (UserFit) -> Bool
    ) -> Outcome {
        if let reason = FitMatchClosetFormValidation.message(for: viewModel) {
            return .blocked(reason: reason)
        }
        guard let item = viewModel.makeUserFit() else {
            return .blocked(reason: "입력한 옷 정보를 저장할 수 없어요. 내용을 다시 확인해 주세요.")
        }
        return persist(item) ? .saved(item) : .persistenceFailed
    }
}
