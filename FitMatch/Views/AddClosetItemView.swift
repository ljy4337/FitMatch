import SwiftUI
import SwiftData

struct AddClosetItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Brand.name) private var brands: [Brand]
    @StateObject private var viewModel: AddClosetItemViewModel
    @State private var isShowingDeleteAlert = false

    let onSave: (UserFit) -> Void
    let onDelete: (() -> Void)?
    private let isEditing: Bool

    init(
        item: UserFit? = nil,
        prefillCategory: ClothingCategory? = nil,
        prefillDetailCategory: ClosetDetailCategory? = nil,
        prefillGender: UserGender? = nil,
        prefillBrand: String? = nil,
        prefillProductName: String? = nil,
        onDelete: (() -> Void)? = nil,
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
        self.isEditing = item != nil
        self.onDelete = onDelete
        self.onSave = onSave
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                addHeader
                sourceSection
                categorySection
                productInfoSection
                measurementSection
                fitSection
                deleteSection
            }
            .padding(20)
            .padding(.bottom, 140)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(isEditing ? "내 옷 정보 수정" : "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            normalizeInputSelection()
        }
        .safeAreaInset(edge: .bottom) {
            bottomSaveBar
        }
        .alert("이 옷을 삭제할까요?", isPresented: $isShowingDeleteAlert) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                onDelete?()
                dismiss()
            }
        } message: {
            Text("삭제한 옷 정보는 복구할 수 없습니다.")
        }
    }

    private var addHeader: some View {
        CardView(radius: 26, padding: 20) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: isEditing ? "pencil" : "plus")
                    .font(.title3.weight(.black))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(width: 48, height: 48)
                    .background(Color.primary, in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text(isEditing ? "내 옷 정보 수정" : "내 옷 추가")
                        .font(.title2.weight(.black))
                        .foregroundStyle(.primary)
                    Text(isEditing ? "저장된 핏 정보를 다시 정리합니다." : "핏이 마음에 드는 옷의 정보를 저장합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var sourceSection: some View {
        AddClosetSectionCard(index: 1, title: "상품 출처", subtitle: "브랜드와 구매처를 구분해 저장합니다.", systemImage: "tag") {
            VStack(alignment: .leading, spacing: 16) {
                AddClosetSelectionMenu(
                    title: "출처 유형",
                    value: viewModel.sourceType.displayName,
                    options: ProductSourceType.allCases,
                    optionTitle: \.displayName,
                    selection: $viewModel.sourceType
                ) { selectedType in
                    normalizeSourceSelection(for: selectedType)
                }

                switch viewModel.sourceType {
                case .officialStore:
                    AddClosetSelectionMenu(
                        title: "공식 브랜드",
                        value: viewModel.brand,
                        options: ProductSourceType.officialStoreNames,
                        optionTitle: { $0 },
                        selection: $viewModel.brand
                    ) { selectedBrand in
                        viewModel.sourceName = "\(selectedBrand) 공식몰"
                    }
                    Text("선택한 공식 브랜드가 브랜드명으로 저장됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .marketplace:
                    AddClosetSelectionMenu(
                        title: "쇼핑 플랫폼",
                        value: viewModel.sourceName,
                        options: ProductSourceType.marketplaceNames,
                        optionTitle: { $0 },
                        selection: $viewModel.sourceName
                    )
                    AddClosetTextField(title: "입점 브랜드", placeholder: "브랜드명 입력", text: $viewModel.brand)
                case .manual:
                    AddClosetTextField(title: "출처명", placeholder: "출처명 입력", text: $viewModel.sourceName)
                    AddClosetTextField(title: "브랜드", placeholder: "브랜드명 입력", text: $viewModel.brand)
                }
            }
        }
    }

    private var categorySection: some View {
        AddClosetSectionCard(index: 2, title: "분류", subtitle: "추천 비교에 사용할 카테고리입니다.", systemImage: "square.grid.2x2") {
            VStack(alignment: .leading, spacing: 16) {
                AddClosetSelectionMenu(
                    title: "성별",
                    value: viewModel.gender.rawValue,
                    options: inputGenders,
                    optionTitle: \.rawValue,
                    selection: $viewModel.gender
                ) { _ in
                    normalizeCategorySelection()
                }

                AddClosetSelectionMenu(
                    title: "카테고리",
                    value: viewModel.category.rawValue,
                    options: serviceCategories,
                    optionTitle: \.rawValue,
                    selection: $viewModel.category
                ) { _ in
                    normalizeDetailCategorySelection()
                }

                AddClosetSelectionMenu(
                    title: "세부 카테고리",
                    value: viewModel.detailCategory.rawValue,
                    options: detailCategories,
                    optionTitle: \.rawValue,
                    selection: $viewModel.detailCategory
                )
            }
        }
    }

    private var productInfoSection: some View {
        AddClosetSectionCard(index: 3, title: "상품 정보", subtitle: "목록과 검색에서 표시됩니다.", systemImage: "textformat") {
            VStack(alignment: .leading, spacing: 16) {
                AddClosetTextField(title: "상품명", placeholder: "상품명 입력", text: $viewModel.productName)
            }
        }
    }

    private var measurementSection: some View {
        AddClosetSectionCard(index: 4, title: "실측값", subtitle: "둘레가 아닌 단면 기준으로 입력합니다.", systemImage: "ruler") {
            VStack(alignment: .leading, spacing: 16) {
                if measurementKinds.isEmpty {
                    Text("선택한 카테고리는 실측 입력 없이 저장할 수 있습니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(measurementKinds) { kind in
                        AddClosetMeasurementField(
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
        }
    }

    private var fitSection: some View {
        AddClosetSectionCard(index: 5, title: "핏 기록", subtitle: "나중에 같은 핏을 찾는 기준이 됩니다.", systemImage: "sparkles") {
            VStack(alignment: .leading, spacing: 16) {
                AddClosetSelectionMenu(
                    title: "핏",
                    value: viewModel.fitPreference.rawValue,
                    options: FitPreference.allCases,
                    optionTitle: \.rawValue,
                    selection: $viewModel.fitPreference
                )
                TextField("핏 메모", text: $viewModel.fitMemo, axis: .vertical)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .lineLimit(3...5)
            }
        }
    }

    @ViewBuilder
    private var deleteSection: some View {
        if isEditing, onDelete != nil {
            Button(role: .destructive) {
                isShowingDeleteAlert = true
            } label: {
                Text("삭제")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.red.opacity(0.2), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private var bottomSaveBar: some View {
        VStack(spacing: 10) {
            if let saveGuideText {
                Label(saveGuideText, systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                saveItemAndDismiss()
            } label: {
                Text(isEditing ? "수정 저장" : "내 옷장에 저장")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(viewModel.canSave ? Color(.systemBackground) : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        viewModel.canSave ? Color.primary : Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSave)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.regularMaterial)
    }

    private func saveItemAndDismiss() {
        guard let item = viewModel.makeUserFit() else {
            return
        }

        onSave(item)
        dismiss()
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

    private var saveGuideText: String? {
        if viewModel.canSave {
            return nil
        }

        if viewModel.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "브랜드명을 입력하면 저장할 수 있습니다."
        }

        if viewModel.productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "상품명을 입력하면 저장할 수 있습니다."
        }

        if viewModel.measurements == nil {
            return "실측값을 1개 이상 입력해 주세요. 입력한 값은 0보다 큰 숫자여야 합니다."
        }

        return nil
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

private struct AddClosetSectionCard<Content: View>: View {
    let index: Int
    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        CardView(radius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.primary)
                        Text("\(index)")
                            .font(.caption.weight(.black))
                            .foregroundStyle(Color(.systemBackground))
                    }
                    .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Image(systemName: systemImage)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                            Text(title)
                                .font(.headline.weight(.black))
                                .foregroundStyle(.primary)
                        }

                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                content
            }
        }
    }
}

private struct AddClosetTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .font(.subheadline.weight(.semibold))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.055), lineWidth: 1)
                }
        }
    }
}

private struct AddClosetSelectionMenu<Option: Hashable>: View {
    let title: String
    let value: String
    let options: [Option]
    let optionTitle: (Option) -> String
    @Binding var selection: Option
    var onSelect: (Option) -> Void = { _ in }

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                    onSelect(option)
                } label: {
                    if option == selection {
                        Label(optionTitle(option), systemImage: "checkmark")
                    } else {
                        Text(optionTitle(option))
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(value.isEmpty ? "선택" : value)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color(.systemBackground), in: Circle())
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .padding(.horizontal, 16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color.primary.opacity(0.055), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct AddClosetMeasurementField: View {
    let title: String
    let placeholder: String
    @Binding var value: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Text("단면 기준")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TextField(placeholder, text: $value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.title3.weight(.bold))
                .frame(width: 76)

            Text("cm")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.primary.opacity(0.055), lineWidth: 1)
        }
    }
}
