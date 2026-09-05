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
    /// Present only for the link registration flow. Its exact runtime UUID map
    /// is consumed by the server-first action and never reconstructed from a
    /// size label in this View.
    let serverRegistrationContext: FitMatchClosetRegistrationServerContext?
    /// A Result may be displaying an exact server size which is no longer
    /// registerable in a freshly fetched runtime.  In that case the caller
    /// asks the sheet to leave the selection empty rather than silently
    /// choosing the sole remaining/recommended size.
    let requiresExplicitSizeSelection: Bool
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
    @State private var didExplicitlyChangeAudience = false
    @State private var didExplicitlySelectClosetClassification = false
    @State private var isBasisItem = false
    @State private var isSaving = false
    @State private var submissionAction = FitMatchComparedProductClosetSubmissionAction()
    @State private var pendingServerSubmission:
        FitMatchComparedProductClosetRegistration.ServerFirstSubmission?
    @State private var alertMessage: String?
    @State private var savedItemAwaitingAcknowledgement: UserFit?

    /// Only a server-confirmed tuple may be preselected without becoming a
    /// Closet override.  Retain that exact starting tuple so re-selecting the
    /// same values does not manufacture USER_EXPLICIT, while an audience
    /// change followed by a newly confirmed category/detail does.
    private let automaticServerAudienceCode: String?
    private let automaticServerCategoryCode: String?
    private let automaticServerDetailCategoryCode: String?

    init(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        recommendedSize: ProductSize?,
        preselectedCategory: ClothingCategory? = nil,
        preselectedClassification: ParsedClosetClassification? = nil,
        isParsedProductReadOnly: Bool = false,
        serverRegistrationContext: FitMatchClosetRegistrationServerContext? = nil,
        startsAtRegistrationConfirmation: Bool = false,
        prefersRepresentativeByDefault: Bool = false,
        requiresExplicitSizeSelection: Bool = false,
        onSaved: ((UserFit) -> Void)? = nil
    ) {
        self.product = product
        self.productDetailCategory = productDetailCategory
        self.recommendedSize = recommendedSize
        self.preselectedCategory = preselectedCategory
        self.preselectedClassification = preselectedClassification
        self.isParsedProductReadOnly = isParsedProductReadOnly
        self.serverRegistrationContext = serverRegistrationContext
        self.requiresExplicitSizeSelection = requiresExplicitSizeSelection
        self.onSaved = onSaved
        _step = State(initialValue: startsAtRegistrationConfirmation ? .confirm : (isParsedProductReadOnly ? .productInfo : .size))
        _isBasisItem = State(initialValue: prefersRepresentativeByDefault)
        _brandName = State(initialValue: product.brand?.name ?? "")
        _productName = State(initialValue: product.name)
        _selectedGender = State(initialValue: product.productTargetGender)
        _selectedGenderCode = State(initialValue: product.productTargetGender.taxonomyCode)
        let requiresExplicitClosetClassification = serverRegistrationContext?
            .classificationState == .reviewRequired
        let hasServerAuthority = serverRegistrationContext?.classificationState == .confirmed
            || product.classificationAuthorityProvenance == .serverConfirmed
        automaticServerAudienceCode = hasServerAuthority
            ? product.productTargetGender.taxonomyCode
            : nil
        let suppliedCanonical = !hasServerAuthority
            && !requiresExplicitClosetClassification
            && preselectedClassification?.isValid == true
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
        let initialCategory = requiresExplicitClosetClassification ? .other : (canonical?.category
            ?? (hasServerAuthority ? product.category : preselectedCategory)
            ?? product.category.serviceGroup)
        let initialCategoryCode = requiresExplicitClosetClassification ? "" : (canonical?.categoryCode
            ?? (hasServerAuthority ? product.resolvedCategoryCode : nil)
            ?? initialCategory.taxonomyCode)
        let initialDetail = requiresExplicitClosetClassification
            ? .other
            : (canonical?.detailCategory ?? productDetailCategory)
        let initialDetailCode = requiresExplicitClosetClassification ? "" : (canonical?.detailCode
            ?? (hasServerAuthority ? product.normalizedProductTypeCode : nil)
            ?? FitMatchTaxonomyProvider.shared.detailCode(
                for: initialDetail.rawValue, categoryCode: initialCategoryCode
            ) ?? "")
        let hasValidCanonicalSelection = FitMatchTaxonomyProvider.shared.isValidDetail(
            initialDetailCode, for: initialCategoryCode
        )
        automaticServerCategoryCode = hasServerAuthority && hasValidCanonicalSelection
            ? initialCategoryCode
            : nil
        automaticServerDetailCategoryCode = hasServerAuthority && hasValidCanonicalSelection
            ? initialDetailCode
            : nil
        _selectedCategory = State(initialValue: initialCategory)
        _selectedCategoryCode = State(initialValue: initialCategoryCode)
        _selectedDetailCategory = State(initialValue: initialDetail)
        _selectedDetailCategoryCode = State(initialValue: initialDetailCode)
        let selectableProductSizes = Self.selectableSizes(
            productSizes: product.sizes,
            serverRegistrationContext: serverRegistrationContext
        )
        _selectedSizeID = State(initialValue: Self.initialSelectedSizeID(
            recommendedSize: recommendedSize,
            productSizes: selectableProductSizes,
            allowsLabelFallback: serverRegistrationContext == nil
        ))
        // Reversible previous initialization used only preselectedCategory != nil.
        // Canonical taxonomy validity now controls whether parsed selections appear selected.
        _hasSelectedClosetCategory = State(initialValue:
            !requiresExplicitClosetClassification && hasValidCanonicalSelection
        )
        _hasSelectedClosetDetailCategory = State(initialValue:
            !requiresExplicitClosetClassification && hasValidCanonicalSelection
        )
    }

    private var availableSizes: [ProductSize] {
        Self.selectableSizes(
            productSizes: product.sizes,
            serverRegistrationContext: serverRegistrationContext
        )
    }

    private var unavailableSizeMessage: String {
        isServerFirstLinkedRegistration
            ? "실측 정보가 있는 서버 사이즈를 다시 확인해 주세요."
            : "사이즈 정보를 찾을 수 없습니다."
    }

    /// Filters only the link-registration presentation. The Product keeps all
    /// runtime sizes and exact IDs for observation, comparison, and later
    /// reconciliation; unavailable-for-Closet sizes are never deleted.
    static func selectableSizes(
        productSizes: [ProductSize],
        serverRegistrationContext: FitMatchClosetRegistrationServerContext?
    ) -> [ProductSize] {
        let sortedSizes = productSizes.sorted {
            if $0.displayOrder != $1.displayOrder {
                return $0.displayOrder < $1.displayOrder
            }
            return $0.name < $1.name
        }

        // A normal legacy product view can coalesce duplicate presentation
        // labels. A linked server-first registration cannot: two visible "M"
        // rows may carry different exact variant/product-size UUIDs.
        guard let serverRegistrationContext else {
            return ParsedProductSizeNormalizer.uniqueProductSizes(sortedSizes)
        }
        return sortedSizes.filter {
            serverRegistrationContext.isRegisterable(displaySizeID: $0.id)
        }
    }

    static func initialSelectedSizeID(
        recommendedSize: ProductSize?,
        productSizes: [ProductSize],
        allowsLabelFallback: Bool
    ) -> UUID? {
        guard let recommendedSize else {
            return nil
        }

        let sortedSizes = productSizes.sorted {
            if $0.displayOrder != $1.displayOrder {
                return $0.displayOrder < $1.displayOrder
            }
            return $0.name < $1.name
        }
        let availableSizes = allowsLabelFallback
            ? ParsedProductSizeNormalizer.uniqueProductSizes(sortedSizes)
            : sortedSizes

        if availableSizes.contains(where: { $0.id == recommendedSize.id }) {
            return recommendedSize.id
        }

        guard allowsLabelFallback else {
            return nil
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
                    let savedItem = savedItemAwaitingAcknowledgement
                    alertMessage = nil
                    savedItemAwaitingAcknowledgement = nil
                    if let savedItem {
                        onSaved?(savedItem)
                        dismiss()
                    }
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
                        Text(unavailableSizeMessage)
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
                        Text(availableSizes.isEmpty
                            ? unavailableSizeMessage
                            : "\(availableSizes.count)개 사이즈를 찾았습니다.")
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
                Text(unavailableSizeMessage)
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
                        selectAudience(gender)
                    }
                }
            }

            RegistrationMenuRow(title: "카테고리", value: selectedCategoryDisplayName) {
                ForEach(availableCategories) { category in
                    Button(category.displayName) {
                        selectCategory(category)
                    }
                }
            }

            RegistrationMenuRow(title: "상세 카테고리", value: selectedDetailDisplayName) {
                ForEach(availableDetailCategories) { detailCategory in
                    Button(detailCategory.displayName) {
                        selectDetailCategory(detailCategory)
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
                        selectAudience(gender)
                    }
                }
            }

            RegistrationMenuRow(title: "대분류", value: hasSelectedClosetCategory ? selectedCategoryDisplayName : "선택") {
                ForEach(availableCategories) { category in
                    Button(category.displayName) {
                        selectCategory(category)
                    }
                }
            }

            RegistrationMenuRow(title: "세부 카테고리", value: hasSelectedClosetDetailCategory ? selectedDetailDisplayName : "선택") {
                if hasSelectedClosetCategory {
                    ForEach(availableDetailCategories) { detailCategory in
                        Button(detailCategory.displayName) {
                            selectDetailCategory(detailCategory)
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
                    guard validateBeforeSave() else { return }
                    isSaving = true
                    Task { @MainActor in
                        await saveSelectedSize()
                    }
                }
            } label: {
                Label(bottomButtonTitle, systemImage: step == .confirm ? "plus" : "chevron.right")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(isSaving ? Color.secondary : Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        isSaving ? Color(.secondarySystemGroupedBackground) : Color.black,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
            }
            .accessibilityIdentifier("closet.confirmAction")
            .buttonStyle(.plain)
            // Missing fields are deliberately handled by the ordered alert
            // validation above. A disabled button hides the reason and makes
            // a REVIEW_REQUIRED registration look like a load failure.
            .disabled(isSaving)
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

    private var bottomGuideText: String? {
        switch step {
        case .productInfo:
            return nil
        case .size:
            return selectedSize == nil ? "등록할 사이즈를 선택해 주세요." : nil
        case .confirm:
            return validationMessage ?? serverRegistrationContext?.registrationBlockMessage
        }
    }

    /// The button remains actionable so the user gets one concrete reason at a
    /// time.  Keep this ordering stable: UI tests and, more importantly, the
    /// registration contract rely on validation finishing before *any* local
    /// or remote mutation is constructed.
    private var validationMessage: String? {
        let provider = FitMatchTaxonomyProvider.shared
        let normalizedGenderCode = selectedGenderCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard selectedGender != .unknown,
              !normalizedGenderCode.isEmpty,
              normalizedGenderCode != "unknown" else {
            return "성별을 선택해 주세요."
        }

        let hasValidCategory = provider.isActiveCategory(selectedCategoryCode)
        guard (!isParsedProductReadOnly || hasSelectedClosetCategory),
              hasValidCategory else {
            return "대분류를 선택해 주세요."
        }

        let hasValidDetail = provider.isValidDetail(
            selectedDetailCategoryCode,
            for: selectedCategoryCode
        ) && ParsedClosetClassification.isConsistent(
            category: selectedCategory,
            detailCategory: selectedDetailCategory,
            categoryCode: selectedCategoryCode,
            detailCode: selectedDetailCategoryCode
        )
        guard (!isParsedProductReadOnly || hasSelectedClosetDetailCategory),
              hasValidDetail else {
            return "세부 카테고리를 선택해 주세요."
        }

        guard let selectedSize else {
            return "실제로 보유한 사이즈를 선택해 주세요."
        }

        if let serverRegistrationContext,
           !serverRegistrationContext.isRegisterable(displaySizeID: selectedSize.id) {
            return "선택한 사이즈는 실측 정보가 없어 내 옷장에 등록할 수 없습니다."
        }

        guard !savedProductName.isEmpty else {
            return "상품명을 확인할 수 없습니다."
        }
        return nil
    }

    private func validateBeforeSave() -> Bool {
        if let validationMessage {
            alertMessage = validationMessage
            return false
        }
        if let blockMessage = serverRegistrationContext?.registrationBlockMessage {
            alertMessage = blockMessage
            return false
        }
        return true
    }

    private func saveSelectedSize() async {
        guard let selectedSize else {
            isSaving = false
            return
        }

        let request = FitMatchComparedProductClosetRegistration.SaveRequest(
            clientItemID: pendingServerSubmission?.localRequest.clientItemID ?? UUID(),
            product: product,
            selectedSize: selectedSize,
            serverIdentity: serverRegistrationContext?.identity(for: selectedSize.id),
            hasMeasurementEligibilityProof: serverRegistrationContext?
                .isRegisterable(displaySizeID: selectedSize.id),
            activeClosetItems: userFits,
            brandName: savedBrandName,
            gender: selectedGender,
            genderCode: selectedGenderCode,
            productName: savedProductName,
            category: selectedCategory.serviceGroup,
            categoryCode: selectedCategoryCode,
            detailCategory: selectedDetailCategory,
            detailCategoryCode: selectedDetailCategoryCode,
            isRepresentative: isBasisItem,
            didExplicitlyChangeClassification: didExplicitlyChangeClassification,
            didExplicitlyChangeAudience: didExplicitlyChangeAudience,
            didExplicitlySelectClosetClassification:
                didExplicitlySelectClosetClassification
        )

        if serverRegistrationContext != nil {
            let submission: FitMatchComparedProductClosetRegistration.ServerFirstSubmission
            if let pendingServerSubmission {
                // A timeout can have reached the server after the client lost
                // its response.  Retry the immutable request, not the newly
                // edited UI values and never a freshly allocated UUID.
                submission = pendingServerSubmission
            } else {
                do {
                    submission = try FitMatchComparedProductClosetRegistration
                        .prepareServerFirstSubmission(request)
                    pendingServerSubmission = submission
                } catch {
                    alertMessage = (error as? LocalizedError)?.errorDescription
                        ?? "서버 등록 요청을 준비하지 못했습니다."
                    isSaving = false
                    return
                }
            }

            let submissionOutcome = await submissionAction.submitServerFirst(
                submission,
                in: modelContext
            )
            guard case .completed(let outcome) = submissionOutcome else {
                isSaving = false
                return
            }
            handleServerFirstOutcome(outcome)
            return
        }

        let submissionOutcome = await submissionAction.submit {
            FitMatchComparedProductClosetRegistration.save(
                request,
                in: modelContext
            )
        }
        guard case .completed(let outcome) = submissionOutcome else {
            // The visible button is disabled while the first task owns the
            // action. Keep its progress state intact rather than falsely
            // reporting a second save result.
            return
        }

        guard case .saved(let item) = outcome else {
            alertMessage = outcome.userVisibleMessage
            // A duplicate or recoverable persistence error must not leave the
            // production sheet in its disabled "저장 중" state. This is also
            // the same action used by the headless double-submit regression.
            isSaving = false
            return
        }

        finishSuccessfulSave(item)
    }

    private func handleServerFirstOutcome(
        _ outcome: FitMatchComparedProductClosetRegistration.SaveOutcome
    ) {
        switch outcome {
        case .saved(let item):
            pendingServerSubmission = nil
            finishSuccessfulSave(item)
        case .savedWithoutReference(let item, let message):
            // The server already owns the Closet row. Do not report a full
            // success until the user has seen that reference selection was
            // rejected; the local row accurately remains non-representative.
            pendingServerSubmission = nil
            isSaving = false
            savedItemAwaitingAcknowledgement = item
            alertMessage = message
        case .duplicate, .storageLookupFailed, .persistenceFailed,
             .serverRejected, .serverAcceptedLocalPersistenceFailed:
            alertMessage = outcome.userVisibleMessage
            // Retain `pendingServerSubmission` for transport ambiguity and
            // local-persistence recovery. Its client_item_id is the only safe
            // identity to retry until this sheet is dismissed.
            isSaving = false
        }
    }

    private func finishSuccessfulSave(_ item: UserFit) {
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
        onSaved?(item)
        dismiss()
    }

    private var isServerFirstLinkedRegistration: Bool {
        serverRegistrationContext != nil
    }

    private func selectAudience(_ gender: TaxonomyOption) {
        let changed = selectedGenderCode != gender.code
        selectedGenderCode = gender.code
        selectedGender = UserGender.fromTaxonomyCode(gender.code)
        if changed {
            didExplicitlyChangeAudience = true
        }

        guard changed else { return }
        if isServerFirstLinkedRegistration {
            // An audience change cannot silently retain a server-auto tuple.
            // The user must actively review both canonical Closet dimensions
            // before an override can be built.
            resetClosetClassificationSelection()
            return
        }

        if isParsedProductReadOnly {
            hasSelectedClosetCategory = false
            hasSelectedClosetDetailCategory = false
        }
        normalizeCategory()
        normalizeDetailCategory()
    }

    private func selectCategory(_ category: TaxonomyCategory) {
        selectedCategoryCode = category.code
        selectedCategory = ClothingCategory.fromTaxonomyCode(category.code)
        didExplicitlyChangeClassification = true
        hasSelectedClosetCategory = true
        hasSelectedClosetDetailCategory = false
        selectedDetailCategory = .other
        selectedDetailCategoryCode = ""

        if !isServerFirstLinkedRegistration {
            normalizeDetailCategory()
        }
        refreshExplicitClassificationIntent()
    }

    private func selectDetailCategory(_ detailCategory: TaxonomyOption) {
        selectedDetailCategoryCode = detailCategory.code
        selectedDetailCategory = ClosetDetailCategory.fromTaxonomyCode(detailCategory.code)
        didExplicitlyChangeClassification = true
        hasSelectedClosetDetailCategory = true
        refreshExplicitClassificationIntent()
    }

    private func resetClosetClassificationSelection() {
        selectedCategory = .other
        selectedCategoryCode = ""
        selectedDetailCategory = .other
        selectedDetailCategoryCode = ""
        hasSelectedClosetCategory = false
        hasSelectedClosetDetailCategory = false
        didExplicitlySelectClosetClassification = false
    }

    private func refreshExplicitClassificationIntent() {
        guard isServerFirstLinkedRegistration else { return }
        guard hasSelectedClosetCategory, hasSelectedClosetDetailCategory else {
            didExplicitlySelectClosetClassification = false
            return
        }

        switch serverRegistrationContext?.classificationState {
        case .reviewRequired:
            didExplicitlySelectClosetClassification = true
        case .confirmed:
            let selectedAudience = FitMatchCanonicalAudience.code(from: selectedGenderCode)
            let automaticAudience = FitMatchCanonicalAudience.code(
                from: automaticServerAudienceCode
            )
            didExplicitlySelectClosetClassification = selectedAudience != automaticAudience
                || selectedCategoryCode != automaticServerCategoryCode
                || selectedDetailCategoryCode != automaticServerDetailCategoryCode
        case .notApplicable, .unavailable, .none:
            didExplicitlySelectClosetClassification = false
        }
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
        FitMatchComparedProductClosetRegistration.isSameRetailerProduct(lhs, rhs)
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
            if availableSizes.count == 1,
               !requiresExplicitSizeSelection {
                self.selectedSizeID = availableSizes.first?.id
            }
            return
        }

        if !availableSizes.contains(where: { $0.id == selectedSizeID }) {
            self.selectedSizeID = nil
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
