import SwiftUI
import SwiftData

struct AddClosetItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Brand.name) private var brands: [Brand]
    @StateObject private var viewModel: AddClosetItemViewModel

    let onSave: (UserFit) -> Void

    init(
        item: UserFit? = nil,
        prefillCategory: ClothingCategory? = nil,
        prefillDetailCategory: ClosetDetailCategory? = nil,
        prefillGender: UserGender? = nil,
        prefillBrand: String? = nil,
        prefillProductName: String? = nil,
        onSave: @escaping (UserFit) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: AddClosetItemViewModel(
                item: item,
                prefillCategory: prefillCategory,
                prefillDetailCategory: prefillDetailCategory,
                prefillGender: prefillGender,
                prefillBrand: prefillBrand,
                prefillProductName: prefillProductName
            )
        )
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("상품 출처") {
                Picker("출처 유형", selection: $viewModel.sourceType) {
                    ForEach(ProductSourceType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .onChange(of: viewModel.sourceType) { _, newValue in
                    normalizeSourceSelection(for: newValue)
                }

                switch viewModel.sourceType {
                case .officialStore:
                    Picker("공식 브랜드", selection: $viewModel.brand) {
                        ForEach(ProductSourceType.officialStoreNames, id: \.self) { brand in
                            Text(brand).tag(brand)
                        }
                    }
                    .onChange(of: viewModel.brand) { _, newValue in
                        viewModel.sourceName = "\(newValue) 공식몰"
                    }
                    Text("선택한 공식 브랜드가 브랜드명으로 저장됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .marketplace:
                    Picker("쇼핑 플랫폼", selection: $viewModel.sourceName) {
                        ForEach(ProductSourceType.marketplaceNames, id: \.self) { platform in
                            Text(platform).tag(platform)
                        }
                    }
                    TextField("브랜드명 직접 입력", text: $viewModel.brand)
                case .manual:
                    TextField("출처명 직접 입력", text: $viewModel.sourceName)
                    TextField("브랜드명 직접 입력", text: $viewModel.brand)
                }
            }

            Section("분류") {
                Picker("성별", selection: $viewModel.gender) {
                    ForEach(inputGenders) { gender in
                        Text(gender.rawValue).tag(gender)
                    }
                }
                .onChange(of: viewModel.gender) { _, _ in
                    normalizeCategorySelection()
                }

                Picker("카테고리", selection: $viewModel.category) {
                    ForEach(serviceCategories) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .onChange(of: viewModel.category) { _, _ in
                    normalizeDetailCategorySelection()
                }

                Picker("세부 카테고리", selection: $viewModel.detailCategory) {
                    ForEach(detailCategories) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
            }

            Section("상품") {
                TextField("상품명", text: $viewModel.productName)
            }

            Section("실측값") {
                if measurementKinds.isEmpty {
                    Text("선택한 카테고리는 실측 입력 없이 저장할 수 있습니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(measurementKinds) { kind in
                        MeasurementField(
                            title: kind.title,
                            placeholder: kind.placeholder,
                            value: binding(for: kind)
                        )
                    }
                    Text("둘레가 아닌 단면 기준으로 입력합니다. 쇼핑몰 표기가 둘레라면 2로 나눈 값을 입력하세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("핏 기록") {
                Picker("핏", selection: $viewModel.fitPreference) {
                    ForEach(FitPreference.allCases) { fit in
                        Text(fit.rawValue).tag(fit)
                    }
                }
                TextField("핏 메모", text: $viewModel.fitMemo, axis: .vertical)
                    .lineLimit(3...5)
            }
        }
        .navigationTitle("기준 옷")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            normalizeInputSelection()
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("저장") {
                    guard let item = viewModel.makeUserFit() else {
                        return
                    }

                    onSave(item)
                    dismiss()
                }
                .disabled(!viewModel.canSave)
            }
        }
    }

    private var serviceCategories: [ClothingCategory] {
        ClothingCategory.closetCategories(for: viewModel.gender).filter { $0 != .other }
    }

    private var detailCategories: [ClosetDetailCategory] {
        ClosetDetailCategory.options(for: viewModel.category, gender: viewModel.gender).filter { $0 != .other }
    }

    private var inputGenders: [UserGender] {
        [.men, .women]
    }

    private func normalizeInputSelection() {
        if !inputGenders.contains(viewModel.gender) {
            viewModel.gender = .men
        }
        normalizeCategorySelection()
    }

    private var measurementKinds: [MeasurementKind] {
        viewModel.measurementKinds
    }

    private func normalizeCategorySelection() {
        if !serviceCategories.contains(viewModel.category) {
            viewModel.category = serviceCategories.first ?? .top
        }
        normalizeDetailCategorySelection()
    }

    private func normalizeDetailCategorySelection() {
        if !detailCategories.contains(viewModel.detailCategory) {
            viewModel.detailCategory = detailCategories.first ?? .shortSleeve
        }
    }

    private func binding(for kind: MeasurementKind) -> Binding<String> {
        switch kind {
        case .shoulder:
            return $viewModel.shoulder
        case .chest:
            return $viewModel.chest
        case .totalLength:
            return $viewModel.totalLength
        case .sleeveLength:
            return $viewModel.sleeveLength
        case .waist:
            return $viewModel.waist
        case .hip:
            return $viewModel.hip
        case .thigh:
            return $viewModel.thigh
        case .rise:
            return $viewModel.rise
        case .hem:
            return $viewModel.hem
        case .footLength:
            return $viewModel.footLength
        case .underBust:
            return $viewModel.underBust
        }
    }

    private func normalizeSourceSelection(for sourceType: ProductSourceType) {
        switch sourceType {
        case .officialStore:
            let selectedBrand = ProductSourceType.officialStoreNames.contains(viewModel.brand)
                ? viewModel.brand
                : ProductSourceType.officialStoreNames[0]
            viewModel.brand = selectedBrand
            viewModel.sourceName = "\(selectedBrand) 공식몰"
            viewModel.usesCustomBrand = false
        case .marketplace:
            if !ProductSourceType.marketplaceNames.contains(viewModel.sourceName) {
                viewModel.sourceName = ProductSourceType.marketplaceNames[0]
            }
            viewModel.usesCustomBrand = true
        case .manual:
            if viewModel.sourceName.isEmpty || ProductSourceType.marketplaceNames.contains(viewModel.sourceName) {
                viewModel.sourceName = "직접 입력"
            }
            viewModel.usesCustomBrand = true
        }
    }
}
