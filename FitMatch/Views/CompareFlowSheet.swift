import SwiftUI
import SwiftData
import UIKit

struct CompareFlowSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \UserFit.createdAt, order: .reverse) private var userFits: [UserFit]
    @Query(sort: \Brand.name) private var brands: [Brand]
    @Query(sort: \RecommendationHistory.createdAt, order: .reverse) private var histories: [RecommendationHistory]

    let initialURL: String?
    let recentClipboardCandidate: SmartClipboardCandidate?

    @StateObject private var viewModel: ShoppingProductViewModel
    @State private var step: CompareFlowStep = .start
    @State private var productURL = ""
    @State private var errorMessage: String?
    @State private var selectedReferenceItemID: UUID?
    @State private var statusMessage: String?
    @State private var productForClosetRegistration: Product?
    @State private var registrationContext: CompareProductRegistrationContext?
    @State private var isShowingProductRegistration = false
    @FocusState private var isURLFocused: Bool

    init(initialURL: String? = nil, recentClipboardCandidate: SmartClipboardCandidate? = nil) {
        self.initialURL = initialURL
        self.recentClipboardCandidate = recentClipboardCandidate
        _viewModel = StateObject(wrappedValue: ShoppingProductViewModel(initialURL: initialURL))
        _productURL = State(initialValue: initialURL ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch step {
                case .start:
                    startContent
                case .loading:
                    loadingContent
                case .missingReference:
                    missingReferenceContent
                case .closetSelection:
                    closetSelectionContent
                case .confirmReference:
                    confirmReferenceContent
                case .result(let history):
                    resultContent(history)
                case .error:
                    errorContent
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 30)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            isURLFocused = false
        }
        .task {
            if let initialURL, !initialURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await startCompare(with: initialURL)
            }
        }
        .sheet(isPresented: $isShowingProductRegistration) {
            if let productForClosetRegistration {
                AddComparedProductToClosetSheet(
                    product: productForClosetRegistration,
                    productDetailCategory: viewModel.detailCategory,
                    recommendedSize: nil
                ) { savedItem in
                    handleRegisteredClosetItem(savedItem)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

private extension CompareFlowSheet {
    var startContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sheetHeader(title: "상품 비교 시작", subtitle: "새 상품을 내 옷과 비교해보세요.")

            if let recentClipboardCandidate {
                recentClipboardCard(recentClipboardCandidate)
            }

            directURLInputCard
            shoppingShortcutCard
        }
    }

    var loadingContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sheetHeader(title: "상품을 분석하고 있어요", subtitle: "잠시만 기다려 주세요.")

            FitMatchCard {
                VStack(alignment: .leading, spacing: 16) {
                    CompareLoadingRow(title: "상품 정보 불러오는 중", state: .done)
                    CompareLoadingRow(title: "사이즈표 확인 중", state: .done)
                    CompareLoadingRow(title: "내 옷과 비교 준비 중", state: .loading)

                    Text("평균 10~20초 소요됩니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
            }
        }
    }

    var missingReferenceContent: some View {
        VStack(spacing: 20) {
            Image(systemName: categorySymbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 86, height: 86)
                .background(Color(.secondarySystemGroupedBackground), in: Circle())

            VStack(spacing: 8) {
                Text("비교 가능한 상품이 없습니다.")
                    .font(.title2.weight(.black))
                    .multilineTextAlignment(.center)

                Text("정확한 비교를 위해 상품을 먼저 등록해 주세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 11) {
                PrimaryButton(title: "상품 등록", systemImage: "plus") {
                    presentProductRegistration(context: .missingReference)
                }

                SecondaryButton(title: "옷장 속 다른 옷과 비교", systemImage: "list.bullet.rectangle") {
                    setStep(.closetSelection)
                }
                .disabled(sameCategoryCandidates.isEmpty)
                .opacity(sameCategoryCandidates.isEmpty ? 0.45 : 1)
            }
        }
        .padding(.top, 12)
    }

    var closetSelectionContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sheetHeader(title: "어떤 옷과 비교할까요?", subtitle: "자동 선택하지 않고, 사용자가 직접 비교 기준 옷을 고릅니다.")

            if sameCategoryCandidates.isEmpty {
                FitMatchCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("비교 가능한 상품이 없습니다.")
                            .font(.headline.weight(.bold))
                        Text("상품을 먼저 등록하면 비교할 수 있습니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        PrimaryButton(title: "상품 등록", systemImage: "plus") {
                            presentProductRegistration(context: .missingReference)
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(sameCategoryCandidates) { item in
                        Button {
                            selectedReferenceItemID = item.id
                            setStep(.confirmReference)
                        } label: {
                            ClosetReferenceChoiceCard(item: item, targetDetailCategory: viewModel.detailCategory)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    var confirmReferenceContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.primary)

            VStack(spacing: 8) {
                Text("선택한 옷으로 비교할까요?")
                    .font(.title2.weight(.black))
                Text("같은 종류의 옷이 아니면 결과의 정확도가 낮아질 수 있습니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let selectedReferenceItem {
                FitMatchCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(selectedReferenceItem.displayName)
                            .font(.headline.weight(.bold))
                        Text("\(selectedReferenceItem.category.rawValue) / \(selectedReferenceItem.detailCategory.rawValue) · \(selectedReferenceItem.sizeName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(spacing: 11) {
                PrimaryButton(title: "계속 비교", systemImage: "sparkles") {
                    if let selectedReferenceItem {
                        calculateAndSaveTemporaryRecommendation(selectedReferenceItem: selectedReferenceItem)
                    }
                }

                SecondaryButton(title: "취소", systemImage: "xmark") {
                    selectedReferenceItemID = nil
                    setStep(.closetSelection)
                }
            }
        }
        .padding(.top, 12)
    }

    func resultContent(_ history: RecommendationHistory) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            productCompactCard(history.product)

            FitMatchCard {
                VStack(spacing: 14) {
                    Text("추천 사이즈")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    Text(history.recommendedSize.name.displaySizeNameForCompareFlow)
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("핏 매칭률 \(history.recommendationScore)%")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.green)

                    Text("내 옷장 기준으로 가장 가까운 사이즈예요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            comparisonSummaryCard(history)
            measurementTableCard(history)

            VStack(spacing: 11) {
                PrimaryButton(title: "쇼핑몰로 이동", systemImage: "bag") {
                    openShoppingURL(history.product.sourceURLString)
                }

                SecondaryButton(title: "내 옷장에 추가", systemImage: "plus") {
                    presentProductRegistration(product: history.product, context: .result)
                }
            }
        }
    }

    var errorContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("상품 정보를 불러오지 못했어요.")
                    .font(.title2.weight(.black))
                Text(errorMessage ?? "URL을 다시 확인해 주세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            PrimaryButton(title: "다시 입력하기", systemImage: "arrow.clockwise") {
                setStep(.start)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }
}

private extension CompareFlowSheet {
    var directURLInputCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                CompareSheetSectionTitle(
                    title: "직접 링크 입력",
                    subtitle: "상품 URL을 붙여넣고 바로 비교합니다."
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
                            isURLFocused = false
                            Task { await startCompare(with: productURL) }
                        }

                    Button {
                        productURL = UIPasteboard.general.string ?? productURL
                    } label: {
                        Text("붙여넣기")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(Color(.systemBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .frame(height: 50)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(.separator).opacity(0.12), lineWidth: 0.5)
                }

                PrimaryButton(title: "비교하기", systemImage: "sparkles") {
                    isURLFocused = false
                    Task { await startCompare(with: productURL) }
                }
                .disabled(productURL.trimmedForCompareFlow.isEmpty)
                .opacity(productURL.trimmedForCompareFlow.isEmpty ? 0.35 : 1)
            }
        }
    }

    var shoppingShortcutCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                CompareSheetSectionTitle(title: "쇼핑몰 바로가기")

                HStack(alignment: .top, spacing: 10) {
                    ShoppingShortcutButton(title: "무신사", systemImage: "m.circle.fill", status: "상품추가", isEnabled: true) {
                        openMusinsa()
                    }

                    ShoppingShortcutButton(title: "29CM", systemImage: "29.circle", status: "준비중", isEnabled: false) {}
                    ShoppingShortcutButton(title: "유니클로", systemImage: "u.circle", status: "준비중", isEnabled: false) {}
                }
            }
        }
    }

    func recentClipboardCard(_ candidate: SmartClipboardCandidate) -> some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                CompareSheetSectionTitle(title: "최근 복사한 링크")

                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "link.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: 42)
                        .background(Color(.secondarySystemGroupedBackground), in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.providerName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text(URL(string: candidate.urlString)?.host ?? candidate.urlString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                PrimaryButton(title: "바로 비교하기", systemImage: "sparkles") {
                    Task { await startCompare(with: candidate.urlString) }
                }
            }
        }
    }

    func productCompactCard(_ product: Product) -> some View {
        FitMatchCard {
            productCompactRow(product: product)
        }
    }

    func productCompactRow(product: Product) -> some View {
        HStack(alignment: .top, spacing: 13) {
            ProductThumbnailView(
                imageURLString: product.imageURLString,
                category: product.category,
                width: 72,
                height: 88,
                cornerRadius: 16
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(product.brand?.name ?? "브랜드 미상")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(product.name)
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)
                Text("출처: \(product.sourceDisplayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(product.category.rawValue) / \(viewModel.detailCategory.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func sheetHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.title2.weight(.black))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }
}

private extension CompareFlowSheet {
    var currentProduct: Product? {
        makeProduct(insertBrandIfNeeded: false)
    }

    var sameDetailItems: [UserFit] {
        let targetGroup = viewModel.category.serviceGroup
        return userFits.filter {
            $0.category.serviceGroup == targetGroup
                && $0.detailCategory == viewModel.detailCategory
        }
    }

    var sameCategoryCandidates: [UserFit] {
        let targetGroup = viewModel.category.serviceGroup
        return userFits
            .filter { $0.category.serviceGroup == targetGroup }
            .sorted {
                if $0.detailCategory == viewModel.detailCategory && $1.detailCategory != viewModel.detailCategory {
                    return true
                }
                if $0.detailCategory != viewModel.detailCategory && $1.detailCategory == viewModel.detailCategory {
                    return false
                }
                if $0.isRepresentative != $1.isRepresentative {
                    return $0.isRepresentative
                }
                return $0.updatedAt > $1.updatedAt
            }
    }

    var selectedReferenceItem: UserFit? {
        guard let selectedReferenceItemID else { return nil }
        return userFits.first { $0.id == selectedReferenceItemID }
    }

    var categorySymbol: String {
        switch viewModel.category.serviceGroup {
        case .top: return "tshirt"
        case .bottom, .pants: return "figure.walk"
        case .outer: return "jacket"
        case .dress: return "figure.dress.line.vertical.figure"
        case .underwear: return "rectangle.on.rectangle"
        case .shirt, .knit: return "tshirt"
        case .shoes: return "shoeprints.fill"
        case .accessory: return "watch.analog"
        case .other: return "tshirt"
        }
    }

}

private extension CompareFlowSheet {
    func startCompare(with urlString: String) async {
        let trimmedURL = urlString.trimmedForCompareFlow
        guard !trimmedURL.isEmpty else { return }

        productURL = trimmedURL
        viewModel.productURL = trimmedURL
        errorMessage = nil
        statusMessage = nil
        setStep(.loading)

        let didLoad = await viewModel.loadProductInfoFromURL()
        guard didLoad else {
            errorMessage = viewModel.errorMessage ?? "상품 정보를 불러오지 못했어요. URL을 다시 확인해 주세요."
            setStep(.error)
            return
        }

        guard let product = makeProduct(insertBrandIfNeeded: false), !product.sizes.isEmpty else {
            errorMessage = "사이즈표를 불러오지 못했어요. URL을 다시 확인해 주세요."
            setStep(.error)
            return
        }

        print("[CompareFlowSheet] productName: \(product.name)")
        print("[CompareFlowSheet] category: \(viewModel.category.rawValue)")
        print("[CompareFlowSheet] detailCategory: \(viewModel.detailCategory.rawValue)")
        print("[CompareFlowSheet] sameDetailItemCount: \(sameDetailItems.count)")

        if sameDetailItems.isEmpty {
            setStep(.missingReference)
            return
        }

        calculateAndSaveRecommendation()
    }

    func calculateAndSaveRecommendation() {
        let brand = existingBrand(named: viewModel.brand) ?? viewModel.makeBrand()
        if let brand, existingBrand(named: brand.name) == nil {
            modelContext.insert(brand)
        }

        guard let product = makeProduct(insertBrandIfNeeded: true) else {
            errorMessage = "상품명과 사이즈표를 확인해 주세요."
            setStep(.error)
            return
        }

        let scopedFits = sameDetailItems.isEmpty ? userFits : sameDetailItems
        guard let history = RecommendationService().recommend(
            product: product,
            userFits: scopedFits,
            productDetailCategory: viewModel.detailCategory,
            allowsGlobalFallback: true
        ) else {
            errorMessage = "비교할 수 있는 실측 정보가 부족합니다."
            setStep(.error)
            return
        }

        do {
            try saveUniqueHistory(history)
            setStep(.result(history))
        } catch {
            errorMessage = "추천 결과를 저장하지 못했습니다. 다시 시도해 주세요."
            setStep(.error)
        }
    }

    func calculateAndSaveTemporaryRecommendation(selectedReferenceItem: UserFit) {
        let brand = existingBrand(named: viewModel.brand) ?? viewModel.makeBrand()
        if let brand, existingBrand(named: brand.name) == nil {
            modelContext.insert(brand)
        }

        guard let product = makeProduct(insertBrandIfNeeded: true),
              let history = RecommendationService().recommend(
                product: product,
                selectedReferenceItem: selectedReferenceItem,
                productDetailCategory: viewModel.detailCategory
              ) else {
            errorMessage = "비교할 수 있는 실측 정보가 부족합니다."
            setStep(.error)
            return
        }

        do {
            try saveUniqueHistory(history)
            setStep(.result(history))
        } catch {
            errorMessage = "추천 결과를 저장하지 못했습니다. 다시 시도해 주세요."
            setStep(.error)
        }
    }

    func makeProduct(insertBrandIfNeeded: Bool) -> Product? {
        let brand = existingBrand(named: viewModel.brand) ?? viewModel.makeBrand()
        if insertBrandIfNeeded, let brand, existingBrand(named: brand.name) == nil {
            modelContext.insert(brand)
        }
        return viewModel.makeProductForClosetRegistration(brand: brand)
    }

    func presentProductRegistration(product: Product? = nil, context: CompareProductRegistrationContext) {
        guard let product = product ?? currentProduct else {
            errorMessage = "상품 정보를 다시 불러와 주세요."
            setStep(.error)
            return
        }

        productForClosetRegistration = product
        registrationContext = context
        isShowingProductRegistration = true
    }

    func handleRegisteredClosetItem(_ item: UserFit) {
        let context = registrationContext
        productForClosetRegistration = nil
        registrationContext = nil
        statusMessage = "내 옷장에 추가했어요."

        switch context {
        case .missingReference:
            selectedReferenceItemID = item.id
            setStep(.confirmReference)
        case .result, .none:
            break
        }
    }

    func existingBrand(named name: String) -> Brand? {
        let normalizedName = name.normalizedBrandName
        guard !normalizedName.isEmpty else { return nil }
        return brands.first { $0.normalizedName == normalizedName }
    }

    func saveUniqueHistory(_ history: RecommendationHistory) throws {
        duplicateHistories(for: history).forEach { duplicate in
            modelContext.delete(duplicate)
        }

        modelContext.insert(history.product)
        modelContext.insert(history)
        try modelContext.save()
    }

    func duplicateHistories(for history: RecommendationHistory) -> [RecommendationHistory] {
        histories.filter { existing in
            isSameComparedProduct(existing.product, history.product)
        }
    }

    func isSameComparedProduct(_ lhs: Product, _ rhs: Product) -> Bool {
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

    func setStep(_ newStep: CompareFlowStep) {
        print("[CompareFlowSheet] step -> \(newStep.logName)")
        withAnimation(.snappy(duration: 0.22)) {
            step = newStep
        }
    }

    func measurementKinds(for history: RecommendationHistory) -> [MeasurementKind] {
        history.product.category
            .measurementKinds(detailCategory: history.productDetailCategory, gender: .unisex)
            .filter {
                history.recommendedSize.measurements.value(for: $0) > 0
                    || history.userFit.measurements.value(for: $0) > 0
            }
    }

    func formatMeasurement(_ value: Double) -> String {
        guard value > 0 else { return "-" }
        if value.rounded() == value { return "\(Int(value))cm" }
        return String(format: "%.1fcm", value)
    }

    func formatDifference(_ value: Double) -> String {
        if value == 0 { return "0cm" }
        let sign = value > 0 ? "+" : ""
        if value.rounded() == value { return "\(sign)\(Int(value))cm" }
        return "\(sign)\(String(format: "%.1f", value))cm"
    }

    func normalizedURL(_ value: String?) -> String? {
        guard var value = normalizedText(value)?.lowercased(), !value.isEmpty else { return nil }
        if value.hasSuffix("/") { value.removeLast() }
        return value
    }

    func normalizedText(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func openShoppingURL(_ urlString: String?) {
        guard let urlString, let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }

    func openMusinsa() {
        guard let url = URL(string: "https://musinsa.onelink.me/PvkC/51vm2j7p") else { return }
        UIApplication.shared.open(url)
    }
}

private extension CompareFlowSheet {
    func comparisonSummaryCard(_ history: RecommendationHistory) -> some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "비교 기준")
                Text(history.userFit.displayName)
                    .font(.headline.weight(.bold))
                Text("\(history.userFit.category.rawValue) / \(history.userFit.detailCategory.rawValue) · \(history.userFit.sizeName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("실측 \(measurementKinds(for: history).count)개 비교")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.primary.opacity(0.08), in: Capsule())
            }
        }
    }

    func measurementTableCard(_ history: RecommendationHistory) -> some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "비교 상세")

                VStack(spacing: 0) {
                    HStack {
                        Text("항목")
                        Spacer()
                        Text("내 기준 옷")
                        Spacer()
                        Text("추천 상품")
                        Spacer()
                        Text("차이")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)

                    ForEach(measurementKinds(for: history), id: \.id) { kind in
                        HStack {
                            Text(kind.title)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(formatMeasurement(history.userFit.measurements.value(for: kind)))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(formatMeasurement(history.recommendedSize.measurements.value(for: kind)))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(formatDifference(history.measurementDifferences.value(for: kind)))
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .padding(.vertical, 8)

                        if kind != measurementKinds(for: history).last {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private enum CompareFlowStep: Equatable {
    case start
    case loading
    case missingReference
    case closetSelection
    case confirmReference
    case result(RecommendationHistory)
    case error

    static func == (lhs: CompareFlowStep, rhs: CompareFlowStep) -> Bool {
        lhs.logName == rhs.logName
    }

    var logName: String {
        switch self {
        case .start: return "start"
        case .loading: return "loading"
        case .missingReference: return "missingReference"
        case .closetSelection: return "closetSelection"
        case .confirmReference: return "confirmReference"
        case .result: return "result"
        case .error: return "error"
        }
    }
}

private enum CompareProductRegistrationContext {
    case missingReference
    case result
}

private enum CompareLoadingState {
    case done
    case loading
}

private struct CompareLoadingRow: View {
    let title: String
    let state: CompareLoadingState

    var body: some View {
        HStack(spacing: 12) {
            Group {
                switch state {
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.primary)
                case .loading:
                    ProgressView()
                }
            }
            .frame(width: 24, height: 24)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }
}

private struct ShoppingShortcutButton: View {
    let title: String
    let systemImage: String
    let status: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(isEnabled ? Color(.systemBackground) : .secondary)
                    .frame(width: 44, height: 44)
                    .background(isEnabled ? Color.black : Color(.secondarySystemGroupedBackground), in: Circle())

                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(status)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isEnabled ? Color(.systemBackground) : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isEnabled ? Color.black : Color(.secondarySystemGroupedBackground), in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .padding(.horizontal, 8)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isEnabled ? Color.black.opacity(0.12) : Color(.separator).opacity(0.14), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.62)
    }
}

private struct CompareSheetSectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ClosetReferenceChoiceCard: View {
    let item: UserFit
    let targetDetailCategory: ClosetDetailCategory

    var body: some View {
        FitMatchCard {
            HStack(alignment: .top, spacing: 12) {
                ProductThumbnailView(
                    imageURLString: item.sourceProduct?.imageURLString,
                    category: item.category,
                    width: 58,
                    height: 70,
                    cornerRadius: 14
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.displayName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text("\(item.category.rawValue) / \(item.detailCategory.rawValue) · \(item.sizeName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 7) {
                        if item.isRepresentative {
                            Text("기준 옷")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.primary.opacity(0.08), in: Capsule())
                        }

                        if item.detailCategory == targetDetailCategory {
                            Text("같은 상세")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.primary.opacity(0.08), in: Capsule())
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private extension String {
    var trimmedForCompareFlow: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var displaySizeNameForCompareFlow: String {
        let value = trimmedForCompareFlow
        guard value.contains("/") else { return value }
        return value
            .split(separator: "/")
            .last
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? value
    }
}
