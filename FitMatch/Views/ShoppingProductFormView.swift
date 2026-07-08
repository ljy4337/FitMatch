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
    @FocusState private var isProductURLFocused: Bool

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
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            isProductURLFocused = false
        }
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
                } onRegister: {
                    presentAddBaselineAfterReferencePicker()
                }
            }
        }
        .sheet(isPresented: $isShowingMissingBasisDialog) {
            MissingBasisBottomSheet(
                productName: viewModel.productName,
                brandName: viewModel.brand,
                imageURLString: viewModel.productImageURLString,
                category: viewModel.category,
                detailCategory: viewModel.detailCategory,
                hasClosetItems: !userFits.isEmpty,
                message: missingBasisMessage,
                onRegister: presentAddBaselineAfterMissingBasis,
                onChooseReference: presentReferencePickerAfterMissingBasis
            )
            .presentationDetents([.height(390)])
            .presentationDragIndicator(.visible)
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
                    .focused($isProductURLFocused)
                    .onSubmit {
                        isProductURLFocused = false
                        Task {
                            await loadProductAndCalculate()
                        }
                    }

                PrimaryButton(
                    title: viewModel.isLoadingProductInfo ? "계산 중" : "사이즈 계산",
                    systemImage: "sparkles",
                    isLoading: viewModel.isLoadingProductInfo
                ) {
                    isProductURLFocused = false
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
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "tshirt.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                        .background(.primary.opacity(0.08), in: Circle())

                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(viewModel.detailCategory.rawValue) 기준 옷이 필요해요")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text(missingBasisMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if userFits.isEmpty {
                    ComparePrimaryActionButton(title: "내 옷장에 옷 등록하기", systemImage: "plus") {
                        isShowingAddBaseline = true
                    }
                } else {
                    ComparePrimaryActionButton(title: "비교할 옷 선택하기", systemImage: "list.bullet.rectangle") {
                        isShowingReferencePicker = true
                    }
                }
            }
            .padding(16)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.primary.opacity(0.08), lineWidth: 1)
            }
        }
    }

    private var missingBasisMessage: String {
        if userFits.isEmpty {
            return "내 옷장에 등록된 기준 옷이 없습니다. 정확한 추천을 위해 먼저 기준 옷을 등록해주세요."
        }

        return "내 옷장에 \(viewModel.detailCategory.rawValue) 기준 옷이 없습니다. 비교할 옷을 직접 선택해주세요."
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

    private func presentAddBaselineAfterMissingBasis() {
        isShowingMissingBasisDialog = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isShowingAddBaseline = true
        }
    }

    private func presentReferencePickerAfterMissingBasis() {
        isShowingMissingBasisDialog = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isShowingReferencePicker = true
        }
    }

    private func presentAddBaselineAfterReferencePicker() {
        isShowingReferencePicker = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isShowingAddBaseline = true
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
    let onRegister: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("어떤 옷과 비교할까요?")
                        .font(.title2.weight(.black))
                        .foregroundStyle(.primary)
                    Text("같은 \(productDetailCategory.rawValue) 기준 옷이 없어 내 옷장 후보 중 하나를 선택해야 합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                if candidates.isEmpty {
                    FitMatchCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("비교할 옷이 없습니다.")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.primary)
                            Text("내 옷장에 옷을 먼저 등록하면 상품과 비교할 수 있습니다.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            ComparePrimaryActionButton(title: "내 옷장에 옷 등록하기", systemImage: "plus") {
                                dismiss()
                                onRegister()
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                } else {
                    VStack(spacing: 12) {
                        ForEach(candidates) { item in
                            Button {
                                onSelect(item)
                                dismiss()
                            } label: {
                                TemporaryReferenceCard(
                                    item: item,
                                    isSameCategory: item.category.serviceGroup == productCategory.serviceGroup
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("임시 기준 옷 선택")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") {
                    dismiss()
                }
            }
        }
    }
}

private struct MissingBasisBottomSheet: View {
    @Environment(\.dismiss) private var dismiss
    let productName: String
    let brandName: String
    let imageURLString: String?
    let category: ClothingCategory
    let detailCategory: ClosetDetailCategory
    let hasClosetItems: Bool
    let message: String
    let onRegister: () -> Void
    let onChooseReference: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: hasClosetItems ? "tshirt.fill" : "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(.systemBackground))
                .frame(width: 52, height: 52)
                .background(.primary, in: Circle())

            VStack(spacing: 8) {
                Text(hasClosetItems ? "비교할 옷을 선택해 주세요" : "내 옷장이 비어 있어요")
                    .font(.title2.weight(.black))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(hasClosetItems ? "\(detailCategory.rawValue) 기준 옷이 없어 내 옷장에서 직접 비교할 옷을 선택해야 합니다." : "먼저 내 옷장에 잘 맞는 옷을 등록하면 사이즈를 비교할 수 있습니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                ProductThumbnailView(
                    imageURLString: imageURLString,
                    width: 58,
                    height: 72,
                    cornerRadius: 14
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(productTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text("\(category.rawValue) / \(detailCategory.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(spacing: 10) {
                if hasClosetItems {
                    ComparePrimaryActionButton(title: "비교할 옷 선택하기", systemImage: "list.bullet.rectangle") {
                        onChooseReference()
                    }
                } else {
                    ComparePrimaryActionButton(title: "내 옷장에 옷 등록하기", systemImage: "plus") {
                        onRegister()
                    }
                }

                Button {
                    dismiss()
                } label: {
                    Text("나중에 하기")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .background(Color(.systemBackground))
    }

    private var productTitle: String {
        let name = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        let brand = brandName.trimmingCharacters(in: .whitespacesAndNewlines)

        if name.isEmpty {
            return brand.isEmpty ? "분석한 상품" : brand
        }

        return brand.isEmpty ? name : "\(brand) \(name)"
    }
}

private struct ComparePrimaryActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct TemporaryReferenceCard: View {
    let item: UserFit
    let isSameCategory: Bool

    var body: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.displayName)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text("\(item.brandName) · \(item.sizeName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text("\(item.category.rawValue) / \(item.detailCategory.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    if item.isRepresentative {
                        Text("기준 옷")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.primary.opacity(0.08), in: Capsule())
                    }

                    if isSameCategory {
                        Text("같은 대분류")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.blue.opacity(0.1), in: Capsule())
                    }
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
