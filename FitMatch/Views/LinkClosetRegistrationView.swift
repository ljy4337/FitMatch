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
    @State private var parsedDetailCategory: ClosetDetailCategory = .other
    @State private var isShowingAddToClosetSheet = false
    @State private var isShowingSavedAlert = false
    @FocusState private var isURLFocused: Bool

    private let parserService = ProductURLParserService()

    private var normalizedURLString: String {
        productURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canLoadProduct: Bool {
        isValidHTTPURL(normalizedURLString) && !isLoading
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
                    recommendedSize: uniqueSizes(for: parsedProduct).first
                ) {
                    isShowingSavedAlert = true
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .alert("내 옷장에 추가했어요.", isPresented: $isShowingSavedAlert) {
            Button("확인") {
                dismiss()
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

                    Button("붙여넣기") {
                        productURL = UIPasteboard.general.string ?? productURL
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
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
                            Text("\(parsedProduct.category.rawValue) / \(parsedDetailCategory.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    PrimaryButton(title: "보유한 사이즈 선택", systemImage: "tag") {
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
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
    }

    private func loadProduct() async {
        let trimmedURL = normalizedURLString
        guard isValidHTTPURL(trimmedURL), !isLoading else {
            errorMessage = trimmedURL.isEmpty ? nil : "올바른 상품 URL을 입력해 주세요."
            return
        }

        isURLFocused = false
        errorMessage = nil
        parsedProduct = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let parsedInfo = try await parserService.parse(urlString: trimmedURL)
            let brand = existingBrand(named: parsedInfo.brandName) ?? Brand(name: parsedInfo.brandName)
            if existingBrand(named: brand.name) == nil {
                modelContext.insert(brand)
            }

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
            parsedProduct = product
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

    private func isValidHTTPURL(_ value: String) -> Bool {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            return false
        }

        return true
    }
}
