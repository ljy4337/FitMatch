import SwiftUI
import SwiftData

struct LinkClosetRegistrationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Brand.name) private var brands: [Brand]

    @State private var productURL = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var parsedProduct: Product?
    @State private var partialProduct: Product?
    @State private var parsedDetailCategory: ClosetDetailCategory = .other
    @State private var isShowingAddToClosetSheet = false
    @State private var isShowingManualAddSheet = false
    @State private var isShowingSavedAlert = false
    @FocusState private var isURLFocused: Bool

    private let parserService = ProductURLParserService()

    private var normalizedURLString: String {
        productURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canLoadProduct: Bool {
        ProductURLSupport.isSupportedProductURL(normalizedURLString) && !isLoading
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                urlCard
                parsedProductPreview
                errorCard
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("상품 링크로 추가")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingAddToClosetSheet) {
            if let parsedProduct {
                AddComparedProductToClosetSheet(
                    product: parsedProduct,
                    productDetailCategory: parsedDetailCategory,
                    recommendedSize: uniqueSizes(for: parsedProduct).first,
                    preselectedClassification: ParsedClosetClassification.resolve(
                        product: parsedProduct,
                        detailCategory: parsedDetailCategory
                    ),
                    isParsedProductReadOnly: true
                ) { _ in
                    isShowingSavedAlert = true
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $isShowingManualAddSheet) {
            if let partialProduct {
                NavigationStack {
                    AddClosetItemView(
                        prefillCategory: partialProduct.category,
                        prefillDetailCategory: parsedDetailCategory,
                        prefillGender: partialProduct.productTargetGender,
                        prefillSourceOption: closetSourceOption(for: partialProduct),
                        prefillBrand: partialProduct.brand?.name,
                        prefillProductName: partialProduct.name,
                        productImageURLString: partialProduct.imageURLString,
                        presentationContext: .linkedProduct
                    ) { item in
                        modelContext.insert(item)
                        try? modelContext.save()
                        isShowingSavedAlert = true
                    }
                }
                .presentationDragIndicator(.visible)
            }
        }
        .alert("내 옷장에 추가했어요.", isPresented: $isShowingSavedAlert) {
            Button("확인") {
                dismiss()
            }
        }
        .onChange(of: productURL) { _, _ in
            parsedProduct = nil
            partialProduct = nil
            errorMessage = nil
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
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.URL)
                        .submitLabel(.search)
                        .focused($isURLFocused)
                        .onSubmit {
                            if canLoadProduct {
                                Task {
                                    await loadProduct()
                                }
                            }
                        }
                }
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                PrimaryButton(
                    title: isLoading ? "불러오는 중" : "상품 정보 불러오기",
                    systemImage: "sparkles",
                    isLoading: isLoading
                ) {
                    Task {
                        await loadProduct()
                    }
                }
                .disabled(!canLoadProduct)
                .opacity(canLoadProduct ? 1 : 0.45)
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
                }
            }
        }
    }

    @ViewBuilder
    private var errorCard: some View {
        if let errorMessage {
            FitMatchCard {
                VStack(alignment: .leading, spacing: 16) {
                    Label(
                        partialProduct == nil ? errorMessage : "상품 정보는 불러왔어요",
                        systemImage: partialProduct == nil ? "exclamationmark.circle" : "checkmark.circle"
                    )
                    .font(.headline)
                    .foregroundStyle(partialProduct == nil ? .red : .primary)

                    if let partialProduct {
                        Text("사이즈 정보를 직접 입력해 내 옷장에 추가할 수 있습니다.")
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

                        PrimaryButton(title: "사이즈 직접 입력", systemImage: "square.and.pencil") {
                            isShowingManualAddSheet = true
                        }
                    }
                }
            }
        }
    }

    private func loadProduct() async {
        let trimmedURL = normalizedURLString
        guard ProductURLSupport.isSupportedProductURL(trimmedURL), !isLoading else {
            errorMessage = trimmedURL.isEmpty ? nil : "올바른 상품 URL을 입력해 주세요."
            return
        }

        isURLFocused = false
        errorMessage = nil
        parsedProduct = nil
        partialProduct = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let parsedInfo = try await parserService.parse(urlString: trimmedURL)
            let brand = existingBrand(named: parsedInfo.brandName) ?? Brand(name: parsedInfo.brandName)

            let sizes = ParsedProductSizeNormalizer.makeProductSizes(from: parsedInfo.sizes)

            let product = Product(
                name: parsedInfo.productName,
                brand: brand,
                category: parsedInfo.category,
                productCode: parsedInfo.productID,
                sourceURLString: parsedInfo.canonicalURLString ?? parsedInfo.sourceURL.absoluteString,
                imageURLString: parsedInfo.imageURLString,
                metadata: parsedInfo.productMetadata,
                sourceType: parsedInfo.sourceType,
                sourceName: parsedInfo.sourceName,
                sizes: sizes
            )

            parsedDetailCategory = parsedInfo.detailCategory
            if let canonical = ParsedClosetClassification.resolve(
                product: product,
                detailCategory: parsedInfo.detailCategory
            ) {
                product.categoryCode = canonical.categoryCode
                product.normalizedProductTypeCode = canonical.normalizedProductTypeCode
                product.garmentType = canonical.garmentFamily
                product.sleeveType = canonical.lengthType
                product.constructionType = canonical.constructionType
            }
            parsedProduct = product
        } catch let partialError as ProductURLParserPartialError {
            let parsedInfo = partialError.productInfo
            let brand = existingBrand(named: parsedInfo.brandName) ?? Brand(name: parsedInfo.brandName)
            let product = Product(
                name: parsedInfo.productName,
                brand: brand,
                category: parsedInfo.category,
                productCode: parsedInfo.productID,
                sourceURLString: parsedInfo.canonicalURLString ?? parsedInfo.sourceURL.absoluteString,
                imageURLString: parsedInfo.imageURLString,
                metadata: parsedInfo.productMetadata,
                sourceType: parsedInfo.sourceType,
                sourceName: parsedInfo.sourceName,
                sizes: []
            )
            parsedDetailCategory = parsedInfo.detailCategory
            partialProduct = product
            errorMessage = parsedInfo.parserNotice ?? partialError.errorDescription
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "상품 정보를 불러오지 못했습니다."
        }
    }

    private func existingBrand(named name: String) -> Brand? {
        let normalizedName = name.normalizedBrandName
        guard !normalizedName.isEmpty else {
            return nil
        }

        return brands.first { $0.normalizedName == normalizedName }
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

    private func closetSourceOption(for product: Product) -> ClosetProductSourceOption {
        if product.sourceName == "무신사" { return .musinsa }
        if product.sourceName.contains("유니클로") { return .uniqlo }
        return .manual
    }

}
