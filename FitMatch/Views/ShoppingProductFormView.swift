import SwiftUI
import SwiftData

struct ShoppingProductFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserFit.createdAt, order: .reverse) private var userFits: [UserFit]
    @Query(sort: \Brand.name) private var brands: [Brand]
    @Query(sort: \RecommendationHistory.createdAt, order: .reverse) private var histories: [RecommendationHistory]
    @StateObject private var viewModel: ShoppingProductViewModel
    @State private var isShowingMissingBasisDialog = false
    @State private var isShowingAddBaseline = false
    @State private var isShowingReferencePicker = false
    @State private var shouldAutoCalculateInitialURL: Bool
    @State private var didAutoCalculateInitialURL = false

    init(initialURL: String? = nil) {
        _viewModel = StateObject(wrappedValue: ShoppingProductViewModel(initialURL: initialURL))
        _shouldAutoCalculateInitialURL = State(initialValue: initialURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                urlSection
                noticeSection
                errorSection
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBarOnScroll()
        .task {
            await autoCalculateInitialURLIfNeeded()
        }
        .sheet(item: $viewModel.recommendation) { result in
            NavigationStack {
                RecommendationResultView(result: result)
            }
        }
        .sheet(isPresented: $isShowingAddBaseline) {
            NavigationStack {
                AddClosetItemView(
                    prefillCategory: viewModel.category,
                    prefillDetailCategory: viewModel.detailCategory,
                    prefillGender: .unisex,
                    prefillBrand: viewModel.brand,
                    prefillProductName: viewModel.productName
                ) { item in
                    modelContext.insert(item)
                    try? modelContext.save()
                }
            }
        }
        .sheet(isPresented: $isShowingReferencePicker) {
            NavigationStack {
                TemporaryReferencePickerView(
                    candidates: temporaryReferenceCandidates,
                    productCategory: viewModel.category,
                    productDetailCategory: viewModel.detailCategory
                ) { item in
                    calculateAndSaveTemporaryRecommendation(selectedReferenceItem: item)
                    isShowingReferencePicker = false
                }
            }
        }
        .confirmationDialog(
            userFits.isEmpty ? "내 옷장에 기준 옷이 없습니다." : "내 옷장에 이 상품과 같은 기준 옷이 없습니다.",
            isPresented: $isShowingMissingBasisDialog,
            titleVisibility: .visible
        ) {
            Button("\(viewModel.detailCategory.rawValue) 등록하기") {
                isShowingAddBaseline = true
            }
            if !userFits.isEmpty {
                Button("비교할 옷 선택하기") {
                    isShowingReferencePicker = true
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text(missingBasisMessage)
        }
    }

    private var urlSection: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "상품 URL",
                    subtitle: "쇼핑몰 URL을 분석해서 내 옷장 기준으로 바로 사이즈를 계산합니다."
                )

                TextField("https://...", text: $viewModel.productURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.URL)
                    .submitLabel(.done)
                    .textFieldStyle(.roundedBorder)

                PrimaryButton(
                    title: viewModel.isLoadingProductInfo ? "계산 중" : "사이즈 계산",
                    systemImage: "sparkles",
                    isLoading: viewModel.isLoadingProductInfo
                ) {
                    Task {
                        await loadProductAndCalculate()
                    }
                }
                .disabled(viewModel.productURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoadingProductInfo)
                .opacity(viewModel.productURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)

                missingBasisCallout
            }
        }
    }

    @ViewBuilder
    private var missingBasisCallout: some View {
        if viewModel.needsDetailCategoryBasis(userFits: userFits) {
            VStack(alignment: .leading, spacing: 10) {
                Label(missingBasisMessage, systemImage: "tshirt")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    if userFits.isEmpty {
                        isShowingAddBaseline = true
                    } else {
                        isShowingReferencePicker = true
                    }
                } label: {
                    Label(userFits.isEmpty ? "기준 옷 등록하기" : "비교할 옷 선택하기", systemImage: userFits.isEmpty ? "plus.circle.fill" : "list.bullet.rectangle")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(Color(.systemBackground))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var missingBasisMessage: String {
        if userFits.isEmpty {
            return "내 옷장에 등록된 기준 옷이 없습니다. 정확한 추천을 위해 먼저 기준 옷을 등록해주세요."
        }

        return "내 옷장에 이 상품과 같은 기준 옷이 없습니다. 어떤 옷과 비교할까요?"
    }

    @ViewBuilder
    private var noticeSection: some View {
        if let parserNotice = viewModel.parserNotice {
            FitMatchCard {
                Label(parserNotice, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage = viewModel.errorMessage {
            FitMatchCard {
                Label(errorMessage, systemImage: "xmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
    }

    private func existingBrand(named name: String) -> Brand? {
        let normalizedName = name.normalizedBrandName
        guard !normalizedName.isEmpty else {
            return nil
        }

        return brands.first { $0.normalizedName == normalizedName }
    }

    private func loadProductAndCalculate() async {
        let didLoad = await viewModel.loadProductInfoFromURL()

        if didLoad && viewModel.needsDetailCategoryBasis(userFits: userFits) {
            isShowingMissingBasisDialog = true
        } else if didLoad {
            calculateAndSaveRecommendation()
        }
    }

    private func autoCalculateInitialURLIfNeeded() async {
        guard shouldAutoCalculateInitialURL, !didAutoCalculateInitialURL else {
            return
        }

        didAutoCalculateInitialURL = true
        await loadProductAndCalculate()
    }

    private func calculateAndSaveRecommendation(allowsGlobalFallback: Bool = false) {
        let brand = existingBrand(named: viewModel.brand) ?? viewModel.makeBrand()

        if !allowsGlobalFallback && viewModel.needsDetailCategoryBasis(userFits: userFits) {
            isShowingMissingBasisDialog = true
            return
        }

        if let brand, existingBrand(named: brand.name) == nil {
            modelContext.insert(brand)
        }

        if let history = viewModel.calculateRecommendation(
            userFits: userFits,
            brand: brand,
            allowsGlobalFallback: allowsGlobalFallback
        ) {
            saveUniqueHistory(history)
        }
    }

    private var temporaryReferenceCandidates: [UserFit] {
        let brand = existingBrand(named: viewModel.brand) ?? viewModel.makeBrand()
        return viewModel.temporaryComparisonCandidates(userFits: userFits, brand: brand)
    }

    private func calculateAndSaveTemporaryRecommendation(selectedReferenceItem: UserFit) {
        let brand = existingBrand(named: viewModel.brand) ?? viewModel.makeBrand()

        if let brand, existingBrand(named: brand.name) == nil {
            modelContext.insert(brand)
        }

        if let history = viewModel.calculateTemporaryRecommendation(
            selectedReferenceItem: selectedReferenceItem,
            brand: brand
        ) {
            saveUniqueHistory(history)
        }
    }

    private func saveUniqueHistory(_ history: RecommendationHistory) {
        duplicateHistories(for: history).forEach { duplicate in
            let duplicateProduct = duplicate.product
            modelContext.delete(duplicate)
            modelContext.delete(duplicateProduct)
        }

        modelContext.insert(history.product)
        modelContext.insert(history)
        try? modelContext.save()
    }

    private func duplicateHistories(for history: RecommendationHistory) -> [RecommendationHistory] {
        histories.filter { existing in
            isSameComparedProduct(existing.product, history.product)
        }
    }

    private func isSameComparedProduct(_ lhs: Product, _ rhs: Product) -> Bool {
        if let lhsURL = normalizedURL(lhs.sourceURLString),
           let rhsURL = normalizedURL(rhs.sourceURLString) {
            return lhsURL == rhsURL
        }

        if let lhsCode = normalizedText(lhs.productCode), !lhsCode.isEmpty,
           let rhsCode = normalizedText(rhs.productCode), !rhsCode.isEmpty {
            return lhsCode == rhsCode
        }

        let lhsBrand = lhs.brand?.normalizedName ?? lhs.displayName.normalizedBrandName
        let rhsBrand = rhs.brand?.normalizedName ?? rhs.displayName.normalizedBrandName
        return lhsBrand == rhsBrand && lhs.name.normalizedBrandName == rhs.name.normalizedBrandName
    }

    private func normalizedURL(_ value: String?) -> String? {
        guard var value = normalizedText(value)?.lowercased(), !value.isEmpty else {
            return nil
        }

        if value.hasSuffix("/") {
            value.removeLast()
        }

        return value
    }

    private func normalizedText(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeSourceSelection(for sourceType: ProductSourceType) {
        switch sourceType {
        case .officialStore:
            let selectedBrand = ProductSourceType.officialStoreNames.contains(viewModel.brand)
                ? viewModel.brand
                : ProductSourceType.officialStoreNames[0]
            viewModel.brand = selectedBrand
            viewModel.sourceName = "\(selectedBrand) 공식몰"
        case .marketplace:
            if !ProductSourceType.marketplaceNames.contains(viewModel.sourceName) {
                viewModel.sourceName = ProductSourceType.marketplaceNames[0]
            }
        case .manual:
            if viewModel.sourceName.isEmpty || ProductSourceType.marketplaceNames.contains(viewModel.sourceName) {
                viewModel.sourceName = "직접 입력"
            }
        }
    }
}

private struct TemporaryReferencePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let candidates: [UserFit]
    let productCategory: ClothingCategory
    let productDetailCategory: ClosetDetailCategory
    let onSelect: (UserFit) -> Void

    var body: some View {
        List {
            Section {
                Text("내 옷장에 이 상품과 같은 기준 옷이 없습니다. 어떤 옷과 비교할까요?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("비교할 기준 옷") {
                if candidates.isEmpty {
                    Text("선택할 수 있는 기준 옷이 없습니다.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(candidates) { item in
                        Button {
                            onSelect(item)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("출처: \(item.sourceName) · 브랜드: \(item.brandName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(item.category.rawValue) / \(item.detailCategory.rawValue) · \(item.sizeName)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if item.isRepresentative {
                                    Text("대표옷")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.red)
                                }
                                if item.category.serviceGroup == productCategory.serviceGroup {
                                    Text("같은 대분류 후보")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
        }
        .navigationTitle("임시 기준 옷 선택")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") {
                    dismiss()
                }
            }
        }
    }
}

private struct ClothingSizeEditor: View {
    @Binding var option: ClothingSizeForm
    let category: ClothingCategory
    let detailCategory: ClosetDetailCategory
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("사이즈명", text: $option.sizeName)
                    .font(.headline)

                if canRemove {
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }

            if measurementKinds.isEmpty {
                Text("선택한 카테고리는 실측 입력 없이 비교할 수 없습니다.")
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
                Text("둘레 표기만 있다면 2로 나눈 단면 값을 입력하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var measurementKinds: [MeasurementKind] {
        category.measurementKinds(detailCategory: detailCategory, gender: .unisex)
    }

    private func binding(for kind: MeasurementKind) -> Binding<String> {
        switch kind {
        case .shoulder:
            return $option.shoulder
        case .chest:
            return $option.chest
        case .totalLength:
            return $option.totalLength
        case .sleeveLength:
            return $option.sleeveLength
        case .waist:
            return $option.waist
        case .hip:
            return $option.hip
        case .thigh:
            return $option.thigh
        case .rise:
            return $option.rise
        case .hem:
            return $option.hem
        case .footLength:
            return $option.footLength
        case .underBust:
            return $option.underBust
        }
    }
}
