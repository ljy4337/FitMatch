import Foundation
import SwiftUI
import SwiftData

struct AddComparedProductToClosetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserFit.createdAt, order: .reverse) private var userFits: [UserFit]

    let product: Product
    let productDetailCategory: ClosetDetailCategory
    let recommendedSize: ProductSize?
    let isParsedProductReadOnly: Bool
    var onSaved: ((UserFit) -> Void)?

    @State private var step: AddComparedProductStep
    @State private var selectedSizeID: UUID?
    @State private var brandName: String
    @State private var productName: String
    @State private var selectedGender: UserGender
    @State private var selectedCategory: ClothingCategory
    @State private var selectedDetailCategory: ClosetDetailCategory
    @State private var hasSelectedClosetCategory = false
    @State private var hasSelectedClosetDetailCategory = false
    @State private var isBasisItem = false
    @State private var alertMessage: String?

    init(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        recommendedSize: ProductSize?,
        isParsedProductReadOnly: Bool = false,
        onSaved: ((UserFit) -> Void)? = nil
    ) {
        self.product = product
        self.productDetailCategory = productDetailCategory
        self.recommendedSize = recommendedSize
        self.isParsedProductReadOnly = isParsedProductReadOnly
        self.onSaved = onSaved
        _step = State(initialValue: isParsedProductReadOnly ? .productInfo : .size)
        _brandName = State(initialValue: product.brand?.name ?? "")
        _productName = State(initialValue: product.name)
        _selectedGender = State(initialValue: product.productTargetGender)
        _selectedCategory = State(initialValue: product.category.serviceGroup)
        _selectedDetailCategory = State(initialValue: productDetailCategory)
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

    private var availableCategories: [ClothingCategory] {
        ClothingCategory.closetCategories(for: selectedGender).filter { $0 != .other }
    }

    private var availableDetailCategories: [ClosetDetailCategory] {
        ClosetDetailCategory
            .options(for: selectedCategory, gender: selectedGender)
            .filter { $0 != .other }
    }

    private var availableGenders: [UserGender] {
        [.men, .women, .kids, .baby, .unisex, .unknown]
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
            .alert("내 옷장 추가", isPresented: Binding(
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
                subtitle: "실제로 가지고 있는 사이즈를 선택하세요."
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
                        imageURLString: product.imageURLString,
                        category: product.category,
                        width: 104,
                        height: 128,
                        cornerRadius: 18
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("이 옷을 내 옷장에 등록합니다")
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
                subtitle: "쇼핑몰에서 불러온 정보입니다. 다음 단계에서 내 옷장 분류를 선택합니다."
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
                        imageURLString: product.imageURLString,
                        category: product.category,
                        width: 104,
                        height: 128,
                        cornerRadius: 18
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("이 옷을 내 옷장에 등록합니다")
                            .font(.title3.weight(.black))
                            .foregroundStyle(.primary)
                        Text(product.name)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(product.brand?.name ?? "브랜드 미상")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text("\(selectedCategory.rawValue) / \(selectedDetailCategory.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if isParsedProductReadOnly {
                            Text(sourceCategoryText ?? "카테고리 정보 없음")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            AddComparedSectionCard(
                title: isParsedProductReadOnly ? "내 옷장 분류" : "등록 정보",
                subtitle: isParsedProductReadOnly ? "내 옷장에 저장할 성별, 카테고리, 사이즈를 선택하세요." : "자동 입력된 정보를 확인하고 저장하세요."
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
                    imageURLString: product.imageURLString,
                    category: product.category,
                    width: 72,
                    height: 86,
                    cornerRadius: 18
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("내 옷장에 추가")
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

            RegistrationMenuRow(title: "성별", value: selectedGender.rawValue) {
                ForEach(availableGenders) { gender in
                    Button(gender.rawValue) {
                        selectedGender = gender
                        normalizeCategory()
                        normalizeDetailCategory()
                    }
                }
            }

            RegistrationMenuRow(title: "카테고리", value: selectedCategory.rawValue) {
                ForEach(availableCategories) { category in
                    Button(category.rawValue) {
                        selectedCategory = category
                    }
                }
            }

            RegistrationMenuRow(title: "상세 카테고리", value: selectedDetailCategory.rawValue) {
                ForEach(availableDetailCategories) { detailCategory in
                    Button(detailCategory.rawValue) {
                        selectedDetailCategory = detailCategory
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
            ReadOnlyRegistrationInfoRow(title: "상품 대상", value: selectedGender.rawValue, emptyText: "미분류")
            ReadOnlyRegistrationInfoRow(title: "카테고리", value: sourceCategoryText, emptyText: "카테고리 정보 없음")
        }
    }

    private var closetCategorySelectionRows: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let sourceCategoryText {
                ReadOnlyRegistrationInfoRow(title: "참고 카테고리", value: sourceCategoryText, emptyText: "카테고리 정보 없음")
            }

            RegistrationMenuRow(title: "성별", value: selectedGender.rawValue) {
                ForEach(availableGenders) { gender in
                    Button(gender.rawValue) {
                        selectedGender = gender
                        hasSelectedClosetCategory = false
                        hasSelectedClosetDetailCategory = false
                        normalizeCategory()
                    }
                }
            }

            RegistrationMenuRow(title: "대분류", value: hasSelectedClosetCategory ? selectedCategory.rawValue : "선택") {
                ForEach(availableCategories) { category in
                    Button(category.rawValue) {
                        selectedCategory = category
                        hasSelectedClosetCategory = true
                        hasSelectedClosetDetailCategory = false
                        normalizeDetailCategory()
                    }
                }
            }

            RegistrationMenuRow(title: "세부 카테고리", value: hasSelectedClosetDetailCategory ? selectedDetailCategory.rawValue : "선택") {
                if hasSelectedClosetCategory {
                    ForEach(availableDetailCategories) { detailCategory in
                        Button(detailCategory.rawValue) {
                            selectedDetailCategory = detailCategory
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
                                Text(kind.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(formatMeasurement(selectedSize.measurements.value(for: kind)))
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
            .buttonStyle(.plain)
            .disabled(!isBottomButtonEnabled)
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
            return "내 옷장에 추가"
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
        if isParsedProductReadOnly {
            return selectedSize != nil
                && hasSelectedClosetCategory
                && hasSelectedClosetDetailCategory
                && !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return selectedSize != nil
            && !brandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveSelectedSize() {
        guard let selectedSize else {
            return
        }

        if isDuplicate(size: selectedSize) {
            alertMessage = "이미 내 옷장에 등록된 사이즈입니다."
            return
        }

        let item = UserFit(
            sourceType: product.sourceType,
            sourceName: product.sourceDisplayName,
            sourceCategoryPath: product.sourceCategoryPath,
            sourceCategoryDepth1: product.sourceCategoryDepth1,
            sourceCategoryDepth2: product.sourceCategoryDepth2,
            sourceCategoryDepth3: product.sourceCategoryDepth3,
            sourceCategoryDepth4: product.sourceCategoryDepth4,
            brandName: savedBrandName,
            gender: selectedGender,
            productName: savedProductName,
            category: selectedCategory.serviceGroup,
            detailCategory: selectedDetailCategory,
            sizeName: selectedSize.name.displaySizeName,
            measurements: selectedSize.measurements,
            fitMemo: "비교 상품에서 추가",
            fitPreference: .regular,
            satisfaction: 0,
            isRepresentative: isBasisItem,
            sourceProduct: product,
            sourceProductSize: selectedSize
        )

        print("[AddComparedProductToClosetSheet] final UserFit source category saved")
        print("[AddComparedProductToClosetSheet] raw source category: \(product.sourceCategoryPath ?? "nil")")
        print("[AddComparedProductToClosetSheet] parsed gender: \(selectedGender.rawValue)")
        print("[AddComparedProductToClosetSheet] sourceCategoryDepth1: \(item.sourceCategoryDepth1 ?? "nil")")
        print("[AddComparedProductToClosetSheet] sourceCategoryDepth2: \(item.sourceCategoryDepth2 ?? "nil")")
        print("[AddComparedProductToClosetSheet] sourceCategoryDepth3: \(item.sourceCategoryDepth3 ?? "nil")")
        print("[AddComparedProductToClosetSheet] sourceCategoryDepth4: \(item.sourceCategoryDepth4 ?? "nil")")
        print("[AddComparedProductToClosetSheet] sourceCategoryPath: \(item.sourceCategoryPath ?? "nil")")

        if isBasisItem {
            userFits
                .filter {
                    $0.sourceName.normalizedForClosetRegistration == product.sourceDisplayName.normalizedForClosetRegistration
                        && $0.sourceCategoryNameForMatching.normalizedForClosetRegistration == product.sourceCategoryNameForMatching.normalizedForClosetRegistration
                        && $0.isRepresentative
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
            alertMessage = "내 옷장에 저장하지 못했습니다. 다시 시도해 주세요."
            return
        }
        onSaved?(item)
        dismiss()
    }

    private func normalizeDetailCategory() {
        if !availableDetailCategories.contains(selectedDetailCategory) {
            selectedDetailCategory = availableDetailCategories.first ?? .shortSleeve
        }
    }

    private func normalizeCategory() {
        if !availableCategories.contains(selectedCategory) {
            selectedCategory = availableCategories.first ?? .top
        }
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
            .filter { size.measurements.value(for: $0) > 0 }
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
        guard value.contains("/") else {
            return value
        }

        return value
            .split(separator: "/")
            .last
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? value
    }
}
