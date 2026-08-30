import Foundation
import SwiftUI
import SwiftData

struct AddComparedProductToClosetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserFit.createdAt, order: .reverse) private var cachedUserFits: [UserFit]

    private var userFits: [UserFit] {
        cachedUserFits.filter(\.isActiveClosetItem)
    }

    let product: Product
    let productDetailCategory: ClosetDetailCategory
    let recommendedSize: ProductSize?
    let preselectedCategory: ClothingCategory?
    let preselectedClassification: ParsedClosetClassification?
    let isParsedProductReadOnly: Bool
    var onSaved: ((UserFit) -> Void)?

    @State private var step: AddComparedProductStep
    @State private var selectedSizeID: UUID?
    @State private var brandName: String
    @State private var productName: String
    @State private var selectedGender: UserGender
    @State private var selectedGenderCode: String
    @State private var selectedCategory: ClothingCategory
    @State private var selectedCategoryCode: String
    @State private var selectedDetailCategory: ClosetDetailCategory
    @State private var selectedDetailCategoryCode: String
    @State private var hasSelectedClosetCategory = false
    @State private var hasSelectedClosetDetailCategory = false
    @State private var didExplicitlyChangeClassification = false
    @State private var isBasisItem = false
    @State private var isSaving = false
    @State private var alertMessage: String?

    init(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        recommendedSize: ProductSize?,
        preselectedCategory: ClothingCategory? = nil,
        preselectedClassification: ParsedClosetClassification? = nil,
        isParsedProductReadOnly: Bool = false,
        startsAtRegistrationConfirmation: Bool = false,
        prefersRepresentativeByDefault: Bool = false,
        onSaved: ((UserFit) -> Void)? = nil
    ) {
        self.product = product
        self.productDetailCategory = productDetailCategory
        self.recommendedSize = recommendedSize
        self.preselectedCategory = preselectedCategory
        self.preselectedClassification = preselectedClassification
        self.isParsedProductReadOnly = isParsedProductReadOnly
        self.onSaved = onSaved
        _step = State(initialValue: startsAtRegistrationConfirmation ? .confirm : (isParsedProductReadOnly ? .productInfo : .size))
        _isBasisItem = State(initialValue: prefersRepresentativeByDefault)
        _brandName = State(initialValue: product.brand?.name ?? "")
        _productName = State(initialValue: product.name)
        _selectedGender = State(initialValue: product.productTargetGender)
        _selectedGenderCode = State(initialValue: product.productTargetGender.taxonomyCode)
        let hasServerAuthority = product.classificationAuthorityProvenance == .serverConfirmed
        let suppliedCanonical = !hasServerAuthority && preselectedClassification?.isValid == true
            ? preselectedClassification
            : nil
        let inferredCanonical = hasServerAuthority
            ? nil
            : ParsedClosetClassification.resolve(
                product: product,
                detailCategory: productDetailCategory
            )
        // Some entry points (notably the result screen) do not carry the
        // parser's canonical classification. Rebuild it from the persisted
        // source path so a comparison detail such as "데님" is stored as the
        // valid closet taxonomy detail "긴바지" instead of falling back to 기타.
        let canonical = suppliedCanonical ?? inferredCanonical
        let initialCategory = canonical?.category
            ?? (hasServerAuthority ? product.category : preselectedCategory)
            ?? product.category.serviceGroup
        let initialCategoryCode = canonical?.categoryCode
            ?? (hasServerAuthority ? product.resolvedCategoryCode : nil)
            ?? initialCategory.taxonomyCode
        let initialDetail = canonical?.detailCategory ?? productDetailCategory
        let initialDetailCode = canonical?.detailCode
            ?? (hasServerAuthority ? product.normalizedProductTypeCode : nil)
            ?? FitMatchTaxonomyProvider.shared.detailCode(
                for: initialDetail.rawValue, categoryCode: initialCategoryCode
            ) ?? ""
        let hasValidCanonicalSelection = FitMatchTaxonomyProvider.shared.isValidDetail(
            initialDetailCode, for: initialCategoryCode
        )
        _selectedCategory = State(initialValue: initialCategory)
        _selectedCategoryCode = State(initialValue: initialCategoryCode)
        _selectedDetailCategory = State(initialValue: initialDetail)
        _selectedDetailCategoryCode = State(initialValue: initialDetailCode)
        _selectedSizeID = State(initialValue: Self.initialSelectedSizeID(recommendedSize: recommendedSize, productSizes: product.sizes))
        // Reversible previous initialization used only preselectedCategory != nil.
        // Canonical taxonomy validity now controls whether parsed selections appear selected.
        _hasSelectedClosetCategory = State(initialValue: hasValidCanonicalSelection)
        _hasSelectedClosetDetailCategory = State(initialValue: hasValidCanonicalSelection)
    }

    private var availableSizes: [ProductSize] {
        let sortedSizes = product.sizes.sorted {
            if $0.displayOrder != $1.displayOrder {
                return $0.displayOrder < $1.displayOrder
            }
            return $0.name < $1.name
        }

        return ParsedProductSizeNormalizer.uniqueProductSizes(sortedSizes)
    }

    private static func initialSelectedSizeID(recommendedSize: ProductSize?, productSizes: [ProductSize]) -> UUID? {
        guard let recommendedSize else {
            return nil
        }

        let sortedSizes = productSizes.sorted {
            if $0.displayOrder != $1.displayOrder {
                return $0.displayOrder < $1.displayOrder
            }
            return $0.name < $1.name
        }
        let availableSizes = ParsedProductSizeNormalizer.uniqueProductSizes(sortedSizes)

        if availableSizes.contains(where: { $0.id == recommendedSize.id }) {
            return recommendedSize.id
        }

        let normalizedRecommendedName = recommendedSize.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return availableSizes.first {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedRecommendedName
        }?.id
    }

    private var selectedSize: ProductSize? {
        guard let selectedSizeID else {
            return nil
        }

        return availableSizes.first { $0.id == selectedSizeID }
    }

    private var sizeSelectionGridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 96), spacing: 12),
            GridItem(.flexible(minimum: 96), spacing: 12)
        ]
    }

    private var availableCategories: [TaxonomyCategory] {
        FitMatchTaxonomyProvider.shared.activeCategories
    }

    private var availableDetailCategories: [TaxonomyOption] {
        FitMatchTaxonomyProvider.shared.activeDetails(categoryCode: selectedCategoryCode)
    }

    private var availableGenders: [TaxonomyOption] {
        FitMatchTaxonomyProvider.shared.selectableGenders
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch step {
                    case .productInfo:
                        productInfoStep
                    case .size:
                        sizeStep
                    case .confirm:
                        confirmStep
                    }
                }
                .padding(20)
                .padding(.bottom, 112)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                bottomActionBar
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onChange(of: selectedCategory) { _, _ in
                if !isParsedProductReadOnly {
                    normalizeDetailCategory()
                }
            }
            .onAppear {
                if !isParsedProductReadOnly {
                    normalizeDetailCategory()
                }
                normalizeSelectedSize()
            }
            .alert("보유한 옷 등록", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("확인") {
                    alertMessage = nil
                }
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private var sizeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            productCompactHeader

            AddComparedSectionCard(
                title: "사이즈 선택",
                subtitle: "실제로 가지고 있는 사이즈를 선택해 주세요."
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    if availableSizes.isEmpty {
                        Text("불러온 사이즈표가 없습니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ProductSizeSelectionGrid(
                            sizes: availableSizes,
                            selectedSizeID: $selectedSizeID
                        )
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    private var productInfoStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            CardView(radius: 26, padding: 20) {
                HStack(alignment: .top, spacing: 14) {
                    ProductThumbnailView(
                        imageURLString: product.imageURLStringForDisplay,
                        category: product.category,
                        width: 104,
                        height: 128,
                        cornerRadius: 18
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("실제로 보유한 옷으로 등록합니다")
                            .font(.title3.weight(.black))
                            .foregroundStyle(.primary)
                        Text(product.brand?.name ?? "정보 없음")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(product.name.isEmpty ? "정보 없음" : product.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(availableSizes.isEmpty ? "사이즈 정보를 찾을 수 없습니다." : "\(availableSizes.count)개 사이즈를 찾았습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            AddComparedSectionCard(
                title: "상품 확인",
                subtitle: "쇼핑몰에서 불러온 정보예요. 실제 가지고 있는 상품인 경우에만 계속해 주세요."
            ) {
                parsedProductReadOnlyRows
            }
        }
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            CardView(radius: 26, padding: 20) {
                HStack(alignment: .top, spacing: 14) {
                    ProductThumbnailView(
                        imageURLString: product.imageURLStringForDisplay,
                        category: product.category,
                        width: 104,
                        height: 128,
                        cornerRadius: 18
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("실제로 보유한 옷으로 등록합니다")
                            .font(.title3.weight(.black))
                            .foregroundStyle(.primary)
                        Text(product.name)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(product.brand?.name ?? "브랜드 미상")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        if isParsedProductReadOnly {
                            Text("쇼핑몰 카테고리: \(sourceCategoryText ?? "카테고리 정보 없음")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        } else {
                            Text("\(selectedCategoryDisplayName) / \(selectedDetailDisplayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            AddComparedSectionCard(
                title: isParsedProductReadOnly ? "보유한 옷 정보" : "등록 정보",
                subtitle: isParsedProductReadOnly ? "실제로 가지고 있는 사이즈와 분류를 선택해 주세요. 구매를 고민 중인 상품은 등록하지 마세요." : "자동 입력된 정보를 확인하고 저장하세요."
            ) {
                registrationInformationFields
            }

            selectedMeasurementSummary
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private var productCompactHeader: some View {
        CardView(radius: 26, padding: 20) {
            HStack(alignment: .center, spacing: 16) {
                ProductThumbnailView(
                    imageURLString: product.imageURLStringForDisplay,
                    category: product.category,
                    width: 72,
                    height: 86,
                    cornerRadius: 18
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("보유한 옷으로 등록")
                        .font(.title2.weight(.black))
                        .foregroundStyle(.primary)
                    Text(product.brand?.name ?? "브랜드 미상")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    Text(product.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var registrationInformationFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isParsedProductReadOnly {
                closetCategorySelectionRows
            } else {
                editableRegistrationRows
            }

            if availableSizes.isEmpty {
                Text("사이즈 정보를 찾을 수 없습니다.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                RegistrationMenuRow(title: "사이즈", value: selectedSize?.name.displaySizeName ?? "선택") {
                    ForEach(availableSizes) { size in
                        Button(size.name.displaySizeName) {
                            selectedSizeID = size.id
                        }
                    }
                }
            }

            BasisToggleRow(isOn: $isBasisItem)
        }
    }

    private var editableRegistrationRows: some View {
        VStack(alignment: .leading, spacing: 14) {
            RegistrationTextField(title: "브랜드", placeholder: "브랜드명", text: $brandName)
            RegistrationTextField(title: "상품명", placeholder: "상품명", text: $productName)

            RegistrationMenuRow(title: "성별", value: selectedGenderDisplayName) {
                ForEach(availableGenders) { gender in
                    Button(gender.displayName) {
                        selectedGenderCode = gender.code
                        selectedGender = UserGender.fromTaxonomyCode(gender.code)
                        didExplicitlyChangeClassification = true
                        normalizeCategory()
                        normalizeDetailCategory()
                    }
                }
            }

            RegistrationMenuRow(title: "카테고리", value: selectedCategoryDisplayName) {
                ForEach(availableCategories) { category in
                    Button(category.displayName) {
                        selectedCategoryCode = category.code
                        selectedCategory = ClothingCategory.fromTaxonomyCode(category.code)
                        didExplicitlyChangeClassification = true
                        normalizeDetailCategory()
                    }
                }
            }

            RegistrationMenuRow(title: "상세 카테고리", value: selectedDetailDisplayName) {
                ForEach(availableDetailCategories) { detailCategory in
                    Button(detailCategory.displayName) {
                        selectedDetailCategoryCode = detailCategory.code
                        selectedDetailCategory = ClosetDetailCategory.fromTaxonomyCode(detailCategory.code)
                        didExplicitlyChangeClassification = true
                    }
                }
            }
        }
    }

    private var parsedProductReadOnlyRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            ReadOnlyRegistrationInfoRow(title: "쇼핑몰", value: product.sourceDisplayName, emptyText: "정보 없음")
            ReadOnlyRegistrationInfoRow(title: "브랜드", value: product.brand?.name, emptyText: "정보 없음", isSelectable: true)
            ReadOnlyRegistrationInfoRow(title: "상품명", value: product.name, emptyText: "정보 없음", isSelectable: true)
            ReadOnlyRegistrationInfoRow(title: "성별", value: selectedGenderDisplayName, emptyText: "선택 필요")
            ReadOnlyRegistrationInfoRow(title: "쇼핑몰 카테고리", value: sourceCategoryText, emptyText: "카테고리 정보 없음")
        }
    }

    private var closetCategorySelectionRows: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let sourceCategoryText {
                ReadOnlyRegistrationInfoRow(title: "쇼핑몰 카테고리", value: sourceCategoryText, emptyText: "카테고리 정보 없음")
            }

            RegistrationMenuRow(title: "성별", value: selectedGenderDisplayName) {
                ForEach(availableGenders) { gender in
                    Button(gender.displayName) {
                        selectedGenderCode = gender.code
                        selectedGender = UserGender.fromTaxonomyCode(gender.code)
                        didExplicitlyChangeClassification = true
                        hasSelectedClosetCategory = false
                        hasSelectedClosetDetailCategory = false
                        normalizeCategory()
                    }
                }
            }

            RegistrationMenuRow(title: "대분류", value: hasSelectedClosetCategory ? selectedCategoryDisplayName : "선택") {
                ForEach(availableCategories) { category in
                    Button(category.displayName) {
                        selectedCategoryCode = category.code
                        selectedCategory = ClothingCategory.fromTaxonomyCode(category.code)
                        didExplicitlyChangeClassification = true
                        hasSelectedClosetCategory = true
                        hasSelectedClosetDetailCategory = false
                        normalizeDetailCategory()
                    }
                }
            }

            RegistrationMenuRow(title: "세부 카테고리", value: hasSelectedClosetDetailCategory ? selectedDetailDisplayName : "선택") {
                if hasSelectedClosetCategory {
                    ForEach(availableDetailCategories) { detailCategory in
                        Button(detailCategory.displayName) {
                            selectedDetailCategoryCode = detailCategory.code
                            selectedDetailCategory = ClosetDetailCategory.fromTaxonomyCode(detailCategory.code)
                            didExplicitlyChangeClassification = true
                            hasSelectedClosetDetailCategory = true
                        }
                    }
                } else {
                    Text("대분류를 먼저 선택해 주세요.")
                }
            }
        }
    }

    @ViewBuilder
    private var selectedMeasurementSummary: some View {
        if let selectedSize {
            AddComparedSectionCard(
                title: "선택한 사이즈 실측",
                subtitle: "\(selectedSize.name.displaySizeName) 기준으로 자동 저장됩니다."
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(spacing: 10) {
                        ForEach(visibleMeasurementKinds(for: selectedSize), id: \.id) { kind in
                            HStack(spacing: 12) {
                                Text(MeasurementResolver.title(
                                    for: kind,
                                    records: selectedSize.measurementRecords
                                ))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(formatMeasurement(
                                    MeasurementResolver.value(
                                        for: kind,
                                        measurements: selectedSize.measurements,
                                        records: selectedSize.measurementRecords
                                    ) ?? 0
                                ))
                                    .font(.headline.weight(.black))
                                    .foregroundStyle(.primary)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private var bottomActionBar: some View {
        VStack(spacing: 10) {
            if let guideText = bottomGuideText {
                Label(guideText, systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                switch step {
                case .productInfo:
                    withAnimation(.snappy(duration: 0.22)) {
                        step = .confirm
                    }
                case .size:
                    normalizeSelectedSize()
                    withAnimation(.snappy(duration: 0.22)) {
                        step = .confirm
                    }
                case .confirm:
                    guard !isSaving else { return }
                    isSaving = true
                    saveSelectedSize()
                }
            } label: {
                Label(bottomButtonTitle, systemImage: step == .confirm ? "plus" : "chevron.right")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(isBottomButtonEnabled ? Color(.systemBackground) : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        isBottomButtonEnabled ? Color.black : Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
            }
            .accessibilityIdentifier("closet.confirmAction")
            .buttonStyle(.plain)
            .disabled(!isBottomButtonEnabled || isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.regularMaterial)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var bottomButtonTitle: String {
        switch step {
        case .productInfo:
            return "다음"
        case .size:
            return "다음"
        case .confirm:
            return isSaving ? "저장 중" : "보유한 옷으로 등록"
        }
    }

    private var isBottomButtonEnabled: Bool {
        switch step {
        case .productInfo:
            return true
        case .size:
            return selectedSize != nil
        case .confirm:
            return canSave
        }
    }

    private var bottomGuideText: String? {
        switch step {
        case .productInfo:
            return nil
        case .size:
            return selectedSize == nil ? "등록할 사이즈를 선택해 주세요." : nil
        case .confirm:
            if isParsedProductReadOnly {
                if selectedGenderCode == "unknown" {
                    return "성별을 선택해 주세요."
                }
                if !hasSelectedClosetCategory {
                    return "대분류를 선택해 주세요."
                }
                if !hasSelectedClosetDetailCategory {
                    return "세부 카테고리를 선택해 주세요."
                }
                if selectedSize == nil {
                    return "저장할 사이즈를 선택해 주세요."
                }
                return productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "상품명을 확인할 수 없습니다." : nil
            }
            if brandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "브랜드명을 입력해 주세요."
            }
            if productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "상품명을 입력해 주세요."
            }
            return nil
        }
    }

    private var canSave: Bool {
        let hasValidClassification = FitMatchTaxonomyProvider.shared.isActiveCategory(selectedCategoryCode)
            && FitMatchTaxonomyProvider.shared.isValidDetail(selectedDetailCategoryCode, for: selectedCategoryCode)
            && ParsedClosetClassification.isConsistent(
                category: selectedCategory,
                detailCategory: selectedDetailCategory,
                categoryCode: selectedCategoryCode,
                detailCode: selectedDetailCategoryCode
            )
        if isParsedProductReadOnly {
            return selectedSize != nil
                && selectedGenderCode != "unknown"
                && hasSelectedClosetCategory
                && hasSelectedClosetDetailCategory
                && hasValidClassification
                && !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return selectedSize != nil
            && selectedGenderCode != "unknown"
            && !brandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hasValidClassification
    }

    private func saveSelectedSize() {
        guard let selectedSize else {
            return
        }

        if isDuplicate(size: selectedSize) {
            alertMessage = "이미 내 옷장에 등록된 사이즈입니다."
            return
        }

        let storedProducts: [Product]
        do {
            storedProducts = try modelContext.fetch(FetchDescriptor<Product>())
        } catch {
            alertMessage = "저장된 상품 정보를 확인하지 못했습니다. 다시 시도해 주세요."
            isSaving = false
            return
        }

        // ProductSize.id is a size-chart identifier, not a retailer-product
        // identity. Resolve an existing row by the retailer product first so
        // saving "M" never attaches this closet item to another product's M.
        let storedProduct = storedProducts.first {
            Self.isSameRetailerProduct($0, product)
        }
        let sourceProduct = storedProduct ?? product
        storedProduct?.refreshExternalPresentation(from: product)

        let selectedSizeKey = ParsedProductSizeNormalizer.normalizedSizeKey(for: selectedSize.name)
        let sourceSize = storedProduct?.sizes.first {
            ParsedProductSizeNormalizer.normalizedSizeKey(for: $0.name) == selectedSizeKey
        } ?? selectedSize

        if sourceProduct.modelContext == nil {
            modelContext.insert(sourceProduct)
        }
        if sourceSize.product !== sourceProduct {
            sourceSize.product = sourceProduct
        }

        let item = UserFit(
            sourceType: sourceProduct.sourceType,
            sourceName: sourceProduct.sourceDisplayName,
            sourceCategoryPath: sourceProduct.sourceCategoryPath,
            sourceCategoryDepth1: sourceProduct.sourceCategoryDepth1,
            sourceCategoryDepth2: sourceProduct.sourceCategoryDepth2,
            sourceCategoryDepth3: sourceProduct.sourceCategoryDepth3,
            sourceCategoryDepth4: sourceProduct.sourceCategoryDepth4,
            brandName: savedBrandName,
            gender: selectedGender,
            productName: savedProductName,
            category: selectedCategory.serviceGroup,
            detailCategory: selectedDetailCategory,
            sizeName: sourceSize.name.displaySizeName,
            measurements: sourceSize.measurements,
            fitMemo: "비교 상품에서 추가",
            fitPreference: .regular,
            satisfaction: 0,
            isRepresentative: isBasisItem,
            sourceProduct: sourceProduct,
            sourceProductSize: sourceSize
        )
        item.genderCode = selectedGenderCode
        item.categoryCode = selectedCategoryCode
        item.detailCategoryCode = selectedDetailCategoryCode
        let savedAuthority = FitMatchClosetClassificationEditPolicy.resultingAuthority(
            current: product.classificationAuthorityProvenance,
            isSourced: FitMatchClosetClassificationEditPolicy.isSourced(product),
            isExplicitSet: FitMatchClosetClassificationEditPolicy.isExplicitSet(product),
            didExplicitlyChangeClassification: didExplicitlyChangeClassification
        )
        if savedAuthority == .userExplicit {
            // Only a real picker interaction is a user authority. Prefilled or
            // inferred values remain hints and can never impersonate consent.
            let savedClassification = ParsedClosetClassification.resolve(
                category: selectedCategory.serviceGroup,
                detailCategory: selectedDetailCategory,
                sourceDepths: [],
                sourcePath: nil,
                productName: savedProductName
            )
            item.normalizedProductTypeCode = savedClassification?.normalizedProductTypeCode
            if let savedClassification {
                item.garmentType = savedClassification.garmentFamily
                item.sleeveType = savedClassification.lengthType
                item.constructionType = savedClassification.constructionType
            }
            item.markClassificationAuthority(.userExplicit)
        } else if savedAuthority == .serverConfirmed {
            item.normalizedProductTypeCode = product.normalizedProductTypeCode
            item.garmentTypeRawValue = product.garmentTypeRawValue
            item.sleeveTypeRawValue = product.sleeveTypeRawValue
            item.constructionTypeRawValue = product.constructionTypeRawValue
            item.canonicalPolicyVersion = product.canonicalPolicyVersion
            item.markClassificationAuthority(
                .serverConfirmed,
                sourceIdentity: product.canonicalSourceIdentity
            )
        } else {
            switch savedAuthority {
            case .serverReviewRequired:
                item.markClassificationAuthority(
                    .serverReviewRequired,
                    sourceIdentity: product.canonicalSourceIdentity
                )
            case .serverNotComparable:
                item.markClassificationAuthority(
                    .serverNotComparable,
                    sourceIdentity: product.canonicalSourceIdentity
                )
            case .serverUnavailable:
                item.markClassificationAuthority(
                    .serverUnavailable,
                    sourceIdentity: product.canonicalSourceIdentity
                )
            default:
                item.markClassificationAuthority(.localHint)
            }
        }
        item.replaceMeasurementRecords(with: sourceSize.measurementRecords)
        if item.classificationAuthorityProvenance == .userExplicit {
            _ = ComparisonProfileMatcher().profile(for: item)
        }

        #if DEBUG
        print("[AddComparedProductToClosetSheet] final UserFit source category saved")
        print("[AddComparedProductToClosetSheet] raw source category: \(product.sourceCategoryPath ?? "nil")")
        print("[AddComparedProductToClosetSheet] parsed gender: \(selectedGender.rawValue)")
        print("[AddComparedProductToClosetSheet] closet category: \(item.category.rawValue) / \(item.detailCategory.rawValue)")
        print("[AddComparedProductToClosetSheet] closet taxonomy: \(item.categoryCode ?? "nil") / \(item.detailCategoryCode ?? "nil")")
        print("[AddComparedProductToClosetSheet] sourceCategoryDepth1: \(item.sourceCategoryDepth1 ?? "nil")")
        print("[AddComparedProductToClosetSheet] sourceCategoryDepth2: \(item.sourceCategoryDepth2 ?? "nil")")
        print("[AddComparedProductToClosetSheet] sourceCategoryDepth3: \(item.sourceCategoryDepth3 ?? "nil")")
        print("[AddComparedProductToClosetSheet] sourceCategoryDepth4: \(item.sourceCategoryDepth4 ?? "nil")")
        print("[AddComparedProductToClosetSheet] sourceCategoryPath: \(item.sourceCategoryPath ?? "nil")")
        #endif

        if isBasisItem,
           item.classificationAuthorityProvenance?.isComparisonAuthority == true {
            userFits
                .filter {
                    $0.isRepresentative && ReferenceGarmentPolicy.conflicts($0, item)
                }
                .forEach {
                    $0.isRepresentative = false
                    $0.updatedAt = Date()
                }
        }

        modelContext.insert(item)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            alertMessage = "내 옷장에 저장하지 못했습니다. 다시 시도해 주세요."
            isSaving = false
            return
        }
        if item.classificationAuthorityProvenance == .userExplicit {
            SourceCategoryHistoryMatcher.saveMapping(
                for: sourceProduct,
                category: selectedCategory,
                detailCategory: selectedDetailCategory
            )
        }
        FitMatchMetricsRecorder.shared.record(
            .closetCreated(
                origin: .comparedProduct,
                category: FitMatchMetricMajorCategory(category: item.category)
            )
        )
        onSaved?(item)
        dismiss()
    }

    private func normalizeDetailCategory() {
        if !availableDetailCategories.contains(where: { $0.code == selectedDetailCategoryCode }),
           let first = availableDetailCategories.first {
            selectedDetailCategoryCode = first.code
            selectedDetailCategory = ClosetDetailCategory.fromTaxonomyCode(first.code)
        }
    }

    /// Retailer products must be matched before their sizes. A size label such
    /// as M is not globally unique across products.
    static func isSameRetailerProduct(_ lhs: Product, _ rhs: Product) -> Bool {
        if let lhsURL = normalizedSourceURL(lhs.sourceURLString),
           let rhsURL = normalizedSourceURL(rhs.sourceURLString) {
            return lhsURL == rhsURL
        }

        guard let lhsCode = normalizedText(lhs.productCode), !lhsCode.isEmpty,
              let rhsCode = normalizedText(rhs.productCode), !rhsCode.isEmpty,
              lhsCode == rhsCode else {
            return false
        }

        let lhsPlatform = normalizedText(lhs.sourcePlatformCode)
        let rhsPlatform = normalizedText(rhs.sourcePlatformCode)
        return lhsPlatform == nil || rhsPlatform == nil || lhsPlatform == rhsPlatform
    }

    private static func normalizedSourceURL(_ value: String?) -> String? {
        guard var value = normalizedText(value)?.lowercased(), !value.isEmpty else {
            return nil
        }
        if value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    private static func normalizedText(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeCategory() {
        if !availableCategories.contains(where: { $0.code == selectedCategoryCode }),
           let first = availableCategories.first {
            selectedCategoryCode = first.code
            selectedCategory = ClothingCategory.fromTaxonomyCode(first.code)
        }
    }

    private var selectedGenderDisplayName: String {
        guard selectedGender != .unknown else { return "선택 필요" }
        return FitMatchTaxonomyProvider.shared.displayName(forGender: selectedGenderCode) ?? selectedGender.rawValue
    }

    private var selectedCategoryDisplayName: String {
        FitMatchTaxonomyProvider.shared.displayName(forCategory: selectedCategoryCode) ?? selectedCategory.rawValue
    }

    private var selectedDetailDisplayName: String {
        FitMatchTaxonomyProvider.shared.displayName(
            forDetail: selectedDetailCategoryCode,
            categoryCode: selectedCategoryCode
        ) ?? selectedDetailCategory.rawValue
    }

    private func normalizeSelectedSize() {
        guard let selectedSizeID else {
            if availableSizes.count == 1 {
                self.selectedSizeID = availableSizes.first?.id
            }
            return
        }

        if !availableSizes.contains(where: { $0.id == selectedSizeID }) {
            self.selectedSizeID = nil
        }
    }

    private func isDuplicate(size: ProductSize) -> Bool {
        userFits.contains { item in
            if item.sourceProductSize?.id == size.id {
                return true
            }

            if let sourceURL = product.sourceURLString,
               let itemURL = item.sourceProduct?.sourceURLString,
               sourceURL == itemURL,
               item.sizeName == size.name.displaySizeName {
                return true
            }

            if let productCode = product.productCode,
               let itemProductCode = item.sourceProduct?.productCode,
               productCode == itemProductCode,
               item.sizeName == size.name.displaySizeName {
                return true
            }

            if product.sourceURLString != nil,
               item.sourceProduct == nil,
               item.productName == product.name,
               item.sizeName == size.name.displaySizeName,
               item.sourceName == product.sourceDisplayName,
               item.brandName == product.brand?.name {
                return true
            }

            return false
        }
    }

    private func visibleMeasurementKinds(for size: ProductSize) -> [MeasurementKind] {
        selectedCategory
            .measurementKinds(detailCategory: selectedDetailCategory, gender: selectedGender)
            .filter {
                MeasurementResolver.value(
                    for: $0,
                    measurements: size.measurements,
                    records: size.measurementRecords
                ) != nil
            }
    }

    private func formatMeasurement(_ value: Double) -> String {
        guard value > 0 else {
            return "-"
        }

        if value.rounded() == value {
            return "\(Int(value))cm"
        }

        return String(format: "%.1fcm", value)
    }

    private var savedBrandName: String {
        if isParsedProductReadOnly {
            return product.brand?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        return brandName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var savedProductName: String {
        if isParsedProductReadOnly {
            return product.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return productName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sourceCategoryText: String? {
        if let sourceCategoryPath = product.sourceCategoryPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceCategoryPath.isEmpty {
            return sourceCategoryPath
        }

        return nil
    }
}

private extension String {
    var normalizedForClosetRegistration: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private enum AddComparedProductStep {
    case productInfo
    case size
    case confirm
}

private struct AddComparedSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        CardView(radius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline.weight(.black))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                content
            }
        }
    }
}

private struct RegistrationTextField: View {
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

private struct RegistrationMenuRow<Content: View>: View {
    let title: String
    let value: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)

                    Text(value)
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
        }
        .buttonStyle(.plain)
    }
}

private struct ReadOnlyRegistrationInfoRow: View {
    let title: String
    let value: String?
    let emptyText: String
    var isSelectable = false

    private var displayValue: String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? emptyText : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)

            valueText
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.055), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var valueText: some View {
        let text = Text(displayValue)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

        if isSelectable {
            text.textSelection(.enabled)
        } else {
            text
        }
    }
}

private struct BasisToggleRow: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "tshirt.fill" : "tshirt")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(isOn ? Color(.systemBackground) : .primary)
                    .frame(width: 38, height: 38)
                    .background(isOn ? Color.black : Color(.secondarySystemGroupedBackground), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("기준 옷으로 등록")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("같은 종류 상품 비교 시 우선 사용됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(isOn ? "ON" : "OFF")
                    .font(.caption.weight(.black))
                    .foregroundStyle(isOn ? .white : .secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(isOn ? Color.black : Color(.secondarySystemGroupedBackground), in: Capsule())
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color.primary.opacity(0.055), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private extension String {
    var displaySizeName: String {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        let finalComponent = value
            .split(separator: "/")
            .last
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? value
        return SizeTokenNormalizer.displayName(for: finalComponent)
    }
}
