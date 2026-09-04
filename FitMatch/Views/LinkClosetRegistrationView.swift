import SwiftUI
import SwiftData

struct LinkClosetRegistrationView: View {
    let onSaved: (() -> Void)?
    let prefersRepresentativeByDefault: Bool

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Brand.name) private var brands: [Brand]

    @State private var productURL = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var parsedProduct: Product?
    @State private var partialProduct: Product?
    @State private var parsedDetailCategory: ClosetDetailCategory = .other
    @State private var registrationServerContext: FitMatchClosetRegistrationServerContext?
    @State private var isShowingAddToClosetSheet = false
    @State private var recoveryViewModel: ShoppingProductViewModel?
    @State private var isShowingSizeTableRecovery = false
    @State private var recoveredSelectedSizeID: UUID?
    @State private var shouldCompleteAfterSheetDismissal = false
    @State private var isShowingSavedToast = false
    @State private var saveErrorMessage: String?
    @State private var isShowingEmptyPasteboardMessage = false
    @State private var emptyPasteboardShake = 0
    @State private var loadTask: Task<Void, Never>?
    @FocusState private var isURLFocused: Bool

    init(prefersRepresentativeByDefault: Bool = false, onSaved: (() -> Void)? = nil) {
        self.prefersRepresentativeByDefault = prefersRepresentativeByDefault
        self.onSaved = onSaved
    }

    private var normalizedURLString: String {
        productURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canLoadProduct: Bool {
        FitMatchProductLinkInput.validate(normalizedURLString).canStartLoad && !isLoading
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if isLoading {
                    loadingContent
                } else {
                    urlCard
                    parsedProductPreview
                    errorCard
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("상품 링크로 추가")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingAddToClosetSheet) {
            if let parsedProduct, let registrationServerContext {
                AddComparedProductToClosetSheet(
                    product: parsedProduct,
                    productDetailCategory: parsedDetailCategory,
                    recommendedSize: recoveredSelectedSizeID.flatMap { selectedID in
                        uniqueSizes(for: parsedProduct).first { $0.id == selectedID }
                    } ?? uniqueSizes(for: parsedProduct).first,
                    // The Sheet receives the server context and decides whether
                    // a tuple is auto-selected. Passing a parser classification
                    // here would make REVIEW_REQUIRED look user-confirmed.
                    preselectedClassification: nil,
                    isParsedProductReadOnly: true,
                    serverRegistrationContext: registrationServerContext,
                    startsAtRegistrationConfirmation: true,
                    prefersRepresentativeByDefault: prefersRepresentativeByDefault
                ) { _ in
                    shouldCompleteAfterSheetDismissal = true
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $isShowingSizeTableRecovery) {
            if let recoveryViewModel {
                NavigationStack {
                    SizeTableRecoveryView(
                        viewModel: recoveryViewModel,
                        purpose: .closetRegistration,
                        onCancel: {},
                        onComplete: {
                            completeRecoveredProduct(using: recoveryViewModel)
                        }
                    )
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: isShowingAddToClosetSheet) { _, isPresented in
            if !isPresented { completeSaveIfNeeded() }
        }
        .overlay(alignment: .top) {
            if isShowingSavedToast {
                FitMatchSuccessToast(message: "내 옷장에 추가했어요.")
                    .padding(.top, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .alert("저장 실패", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "")
        }
        .onChange(of: productURL) { _, _ in
            parsedProduct = nil
            partialProduct = nil
            registrationServerContext = nil
            recoveryViewModel = nil
            recoveredSelectedSizeID = nil
            errorMessage = nil
            if !normalizedURLString.isEmpty {
                isShowingEmptyPasteboardMessage = false
            }
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private func completeSaveIfNeeded() {
        guard shouldCompleteAfterSheetDismissal else { return }
        shouldCompleteAfterSheetDismissal = false
        withAnimation { isShowingSavedToast = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            onSaved?()
            dismiss()
        }
    }

    private var loadingContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text("상품 정보를 불러오고 있어요")
                    .font(.title2.weight(.black))
                Text("잠시만 기다려 주세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            FitMatchCard {
                VStack(alignment: .leading, spacing: 16) {
                    FitMatchLoadingRow(title: "상품 정보 불러오는 중", state: .done)
                    FitMatchLoadingRow(title: "사이즈표 확인 중", state: .loading)
                    FitMatchLoadingRow(title: "내 옷장 추가 준비 중", state: .waiting)

                    Text("평균 10~20초 소요됩니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
            }
        }
    }

    private var urlCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "상품 URL",
                    subtitle: "상품 링크를 불러온 뒤 보유한 사이즈를 선택해 내 옷장에 저장합니다."
                )

                HStack(spacing: 10) {
                    TextField("상품 URL을 붙여넣어 주세요", text: $productURL)
                        .accessibilityIdentifier("closet.linkURL")
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.URL)
                        .submitLabel(.search)
                        .focused($isURLFocused)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .onSubmit {
                            if canLoadProduct {
                                startLoadingProduct()
                            }
                        }

                    Button {
                        pasteProductURL()
                    } label: {
                        Text("붙여넣기")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Color.black, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture {
                    isURLFocused = true
                }

                if isShowingEmptyPasteboardMessage {
                    Text("복사된 상품 링크가 없어요. 링크를 복사한 후 다시 눌러 주세요.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .modifier(ClosetLinkPasteShakeEffect(animatableData: CGFloat(emptyPasteboardShake)))
                        .transition(.opacity)
                } else if !normalizedURLString.isEmpty && !ProductURLSupport.isSupportedProductURL(normalizedURLString) {
                    Text("지원하지 않는 상품 링크예요. 공식 상품 URL인지 확인해 주세요.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                PrimaryButton(
                    title: isLoading ? "불러오는 중" : "상품 정보 불러오기",
                    systemImage: "sparkles",
                    isLoading: isLoading
                ) {
                    startLoadingProduct()
                }
                .accessibilityIdentifier("closet.linkLoad")
                .disabled(!canLoadProduct)
            }
        }
    }

    @ViewBuilder
    private var parsedProductPreview: some View {
        if let parsedProduct {
            let sizes = uniqueSizes(for: parsedProduct)

            FitMatchCard {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "불러온 상품", subtitle: "\(sizes.count)개 사이즈를 찾았습니다.")

                    HStack(alignment: .top, spacing: 14) {
                        ProductThumbnailView(
                            imageURLString: parsedProduct.imageURLString,
                            category: parsedProduct.category,
                            width: 82,
                            height: 98,
                            cornerRadius: 16
                        )

                        VStack(alignment: .leading, spacing: 7) {
                            Text(parsedProduct.brand?.name ?? "브랜드 미상")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(parsedProduct.name)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("출처: \(parsedProduct.sourceDisplayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(sourceCategoryText(for: parsedProduct))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    PrimaryButton(title: "다음", systemImage: "chevron.right") {
                        isShowingAddToClosetSheet = true
                    }
                    .accessibilityIdentifier("closet.linkNext")
                }
            }
        }
    }

    @ViewBuilder
    private var errorCard: some View {
        if let errorMessage {
            FitMatchCard {
                VStack(alignment: .leading, spacing: 16) {
                    if isUnsupportedTopBottomSet {
                        Text(MusinsaParser.unsupportedTopBottomSetNotice)
                            .font(.title2.weight(.black))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Label(
                            (parsedProduct != nil || partialProduct != nil)
                                ? "상품 정보를 불러왔어요."
                                : errorMessage,
                            systemImage: (parsedProduct != nil || partialProduct != nil)
                                ? "checkmark.circle" : "exclamationmark.circle"
                        )
                        .font(.headline)
                        .foregroundStyle((parsedProduct != nil || partialProduct != nil) ? .primary : .red)
                    }

                    if parsedProduct != nil, !isUnsupportedTopBottomSet {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let partialProduct, !isUnsupportedTopBottomSet {
                        Text("판매 페이지에 사이즈표가 있지만 제공 형식이나 이미지 구성 때문에 자동으로 읽지 못했어요. 사이즈표를 확인한 뒤 직접 입력해 주세요.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(alignment: .top, spacing: 14) {
                            ProductThumbnailView(
                                imageURLString: partialProduct.imageURLString,
                                category: partialProduct.category,
                                width: 82,
                                height: 98,
                                cornerRadius: 16
                            )

                            VStack(alignment: .leading, spacing: 7) {
                                Text(partialProduct.brand?.name ?? "브랜드 미상")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                Text(partialProduct.name)
                                    .font(.headline.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(sourceCategoryText(for: partialProduct))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        PrimaryButton(title: "사이즈표 이미지 분석", systemImage: "viewfinder") {
                            isShowingSizeTableRecovery = true
                        }

                        Text("링크 상품은 서버가 확인한 상품·옵션·사이즈 식별자가 있어야 저장할 수 있어요. 서버 사이즈 정보를 다시 확인한 뒤 등록해 주세요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func loadProduct() async {
        guard !isLoading else {
            return
        }

        isURLFocused = false
        errorMessage = nil
        parsedProduct = nil
        partialProduct = nil
        registrationServerContext = nil
        isLoading = true
        defer { isLoading = false }

        let outcome = await FitMatchLinkClosetRegistrationAction.load(
            urlString: normalizedURLString,
            makeViewModel: { ShoppingProductViewModel(initialURL: $0) },
            existingBrand: existingBrand(named:)
        )
        switch outcome {
        case .blocked(let validation):
            errorMessage = validation == .empty ? nil : "올바른 상품 URL을 입력해 주세요."
            return
        case .cancelled:
            return
        case .loaded(let preparation):
            parsedProduct = preparation.parsedProduct
            partialProduct = preparation.partialProduct
            parsedDetailCategory = preparation.detailCategory
            registrationServerContext = preparation.serverRegistrationContext
            recoveryViewModel = preparation.recoveryViewModel
            errorMessage = preparation.errorMessage
        }
    }

    private func startLoadingProduct() {
        guard loadTask == nil, !isLoading else { return }
        loadTask = Task {
            await loadProduct()
            loadTask = nil
        }
    }

    private func pasteProductURL() {
        guard let value = UIPasteboard.general.string,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if !normalizedURLString.isEmpty {
                isShowingEmptyPasteboardMessage = false
                return
            }
            isShowingEmptyPasteboardMessage = true
            withAnimation(.linear(duration: 0.45)) {
                emptyPasteboardShake += 1
            }
            return
        }
        productURL = ProductURLSupport.extractedURLString(from: value) ?? value
        if ProductURLSupport.isSupportedProductURL(productURL) {
            isShowingEmptyPasteboardMessage = false
        }
        isURLFocused = false
    }

    private var isUnsupportedTopBottomSet: Bool {
        errorMessage == MusinsaParser.unsupportedTopBottomSetNotice
    }

    private func existingBrand(named name: String) -> Brand? {
        let normalizedName = name.normalizedBrandName
        guard !normalizedName.isEmpty else {
            return nil
        }

        return brands.first { $0.normalizedName == normalizedName }
    }

    private func completeRecoveredProduct(using viewModel: ShoppingProductViewModel) {
        let brand = existingBrand(named: viewModel.brand) ?? viewModel.makeBrand()
        guard let product = viewModel.makeProductForClosetRegistration(brand: brand) else {
            viewModel.recoveryErrorMessage = "선택한 사이즈 정보를 저장할 수 없습니다."
            return
        }

        let serverContext = viewModel.closetRegistrationServerContext
        let selectedSizeID = viewModel.recoverySelectedSizeID ?? product.sizes.first?.id
        guard let selectedSizeID,
              serverContext.identity(for: selectedSizeID) != nil else {
            // A recovered display size without a server-issued UUID is useful
            // parser evidence, but it cannot safely become a link-based
            // Closet row. Do not send it through the old local-only form.
            viewModel.recoveryErrorMessage = "서버 사이즈 정보를 다시 확인해 주세요."
            return
        }

        parsedProduct = product
        partialProduct = nil
        registrationServerContext = serverContext
        errorMessage = nil
        recoveredSelectedSizeID = viewModel.recoverySelectedSizeID
        isShowingSizeTableRecovery = false
        DispatchQueue.main.async {
            isShowingAddToClosetSheet = true
        }
    }

    private func uniqueSizes(for product: Product) -> [ProductSize] {
        let sortedSizes = product.sizes.sorted {
            if $0.displayOrder != $1.displayOrder {
                return $0.displayOrder < $1.displayOrder
            }
            return $0.name < $1.name
        }

        return ParsedProductSizeNormalizer.uniqueProductSizes(sortedSizes)
    }

    private func sourceCategoryText(for product: Product) -> String {
        let value = product.sourceCategoryPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "카테고리 정보 없음" : value
    }

}

/// Converts a parsed link into a Closet-registration input without creating a
/// second local classification authority. A fully measured product keeps the
/// exact server status on `Product`; measurement recovery is offered only when
/// the server has already confirmed the canonical tuple.
@MainActor
struct LinkClosetRegistrationPreparation {
    let parsedProduct: Product?
    let partialProduct: Product?
    let detailCategory: ClosetDetailCategory
    let serverRegistrationContext: FitMatchClosetRegistrationServerContext
    let recoveryViewModel: ShoppingProductViewModel?
    let errorMessage: String?

    static func make(
        from viewModel: ShoppingProductViewModel,
        brand: Brand?
    ) -> LinkClosetRegistrationPreparation {
        if let product = viewModel.makeProductForClosetRegistration(brand: brand) {
            return LinkClosetRegistrationPreparation(
                parsedProduct: product,
                partialProduct: nil,
                detailCategory: viewModel.detailCategory,
                serverRegistrationContext: viewModel.closetRegistrationServerContext,
                recoveryViewModel: nil,
                errorMessage: product.classificationAuthorityProvenance == .serverConfirmed
                    ? nil
                    : viewModel.errorMessage
            )
        }

        guard viewModel.hasLoadedProductInfo,
              viewModel.hasServerConfirmedAuthority,
              !viewModel.productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              case .confirmed(let authority) = viewModel.serverAuthorityState else {
            return LinkClosetRegistrationPreparation(
                parsedProduct: nil,
                partialProduct: nil,
                detailCategory: viewModel.detailCategory,
                serverRegistrationContext: viewModel.closetRegistrationServerContext,
                recoveryViewModel: nil,
                errorMessage: viewModel.errorMessage ?? "서버 상품 분류를 확인하지 못했습니다."
            )
        }

        let partial = Product(
            name: viewModel.productName,
            brand: brand,
            category: viewModel.category,
            productCode: viewModel.productCode,
            sourceURLString: viewModel.productCanonicalURLString ?? viewModel.productURL,
            imageURLString: viewModel.productImageURLString,
            metadata: viewModel.productMetadata,
            sourceType: viewModel.sourceType,
            sourceName: viewModel.sourceName,
            sizes: []
        )
        let classification = authority.classification
        partial.categoryCode = classification.categoryCode
        partial.normalizedProductTypeCode = classification.detailCode
        // `familyCode` is comparison policy, not the garment identity. The
        // partial registration path must preserve the server-issued garment
        // tuple without turning a shopping personal authority into Global.
        partial.garmentTypeRawValue = classification.garmentTypeCode
            ?? classification.detailCode
        partial.sleeveTypeRawValue = classification.lengthCode
        partial.canonicalPolicyVersion = classification.taxonomyPolicyVersion
            ?? classification.decisionVersion
        partial.markClassificationAuthority(
            viewModel.hasActiveUserExplicitClassification ? .localHint : .serverConfirmed,
            sourceIdentity: classification.classificationID?.uuidString
                ?? classification.method
        )

        return LinkClosetRegistrationPreparation(
            parsedProduct: nil,
            partialProduct: partial,
            detailCategory: viewModel.detailCategory,
            serverRegistrationContext: viewModel.closetRegistrationServerContext,
            recoveryViewModel: viewModel,
            errorMessage: viewModel.errorMessage
                ?? viewModel.parserNotice
                ?? "사이즈표를 찾지 못했습니다. 실측값을 확인해 주세요."
        )
    }
}

private struct ClosetLinkPasteShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = sin(animatableData * .pi * 6) * 7
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
