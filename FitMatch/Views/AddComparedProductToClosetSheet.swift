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
    var onSaved: (() -> Void)?

    @State private var step: AddComparedProductStep = .size
    @State private var selectedSizeID: UUID?
    @State private var brandName: String
    @State private var productName: String
    @State private var selectedCategory: ClothingCategory
    @State private var selectedDetailCategory: ClosetDetailCategory
    @State private var isBasisItem = false
    @State private var alertMessage: String?

    init(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        recommendedSize: ProductSize?,
        onSaved: (() -> Void)? = nil
    ) {
        self.product = product
        self.productDetailCategory = productDetailCategory
        self.recommendedSize = recommendedSize
        self.onSaved = onSaved
        _brandName = State(initialValue: product.brand?.name ?? "")
        _productName = State(initialValue: product.name)
        _selectedCategory = State(initialValue: product.category.serviceGroup)
        _selectedDetailCategory = State(initialValue: productDetailCategory)
    }

    private var sortedSizes: [ProductSize] {
        product.sizes.sorted {
            if $0.displayOrder != $1.displayOrder {
                return $0.displayOrder < $1.displayOrder
            }
            return $0.name < $1.name
        }
    }

    private var selectedSize: ProductSize? {
        guard let selectedSizeID else {
            return nil
        }

        return sortedSizes.first { $0.id == selectedSizeID }
    }

    private var availableCategories: [ClothingCategory] {
        [.top, .bottom, .outer, .dress, .underwear, .shoes, .accessory]
    }

    private var availableDetailCategories: [ClosetDetailCategory] {
        ClosetDetailCategory
            .options(for: selectedCategory, gender: .unisex)
            .filter { $0 != .other }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch step {
                    case .size:
                        sizeStep
                    case .confirm:
                        confirmStep
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("내 옷장에 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .size ? "취소" : "이전") {
                        if step == .size {
                            dismiss()
                        } else {
                            withAnimation(.snappy(duration: 0.22)) {
                                step = .size
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomAction
                    .padding(20)
                    .background(.regularMaterial)
            }
            .onChange(of: selectedCategory) { _, _ in
                normalizeDetailCategory()
            }
            .onAppear {
                normalizeDetailCategory()
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

            FitMatchCard {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(
                        title: "어떤 사이즈를 가지고 있나요?",
                        subtitle: "내 옷장에 등록할 사이즈를 직접 선택하세요."
                    )

                    if sortedSizes.isEmpty {
                        Text("불러온 사이즈표가 없습니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
                            ForEach(sortedSizes) { size in
                                Button {
                                    selectedSizeID = size.id
                                } label: {
                                    Text(size.name.displaySizeName)
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(selectedSizeID == size.id ? .white : .primary)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 54)
                                        .background(selectedSizeID == size.id ? Color.black : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            FitMatchCard {
                VStack(alignment: .leading, spacing: 16) {
                    ProductThumbnailView(
                        imageURLString: product.imageURLString,
                        width: 300,
                        height: 260,
                        cornerRadius: 20
                    )
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("이 옷을 내 옷장에 등록합니다")
                            .font(.title3.weight(.black))
                            .foregroundStyle(.primary)
                        Text("자동으로 불러온 정보를 확인하고 필요한 항목만 수정하세요.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            FitMatchCard {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "등록 정보")

                    TextField("브랜드", text: $brandName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)

                    TextField("상품명", text: $productName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)

                    Picker("카테고리", selection: $selectedCategory) {
                        ForEach(availableCategories) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }

                    Picker("상세 카테고리", selection: $selectedDetailCategory) {
                        ForEach(availableDetailCategories) { detailCategory in
                            Text(detailCategory.rawValue).tag(detailCategory)
                        }
                    }

                    Picker("사이즈", selection: Binding(
                        get: { selectedSizeID ?? sortedSizes.first?.id ?? UUID() },
                        set: { selectedSizeID = $0 }
                    )) {
                        ForEach(sortedSizes) { size in
                            Text(size.name.displaySizeName).tag(size.id)
                        }
                    }

                    Toggle("기준 옷으로 등록", isOn: $isBasisItem)
                        .font(.subheadline.weight(.semibold))
                }
            }

            selectedMeasurementSummary
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private var productCompactHeader: some View {
        FitMatchCard {
            HStack(alignment: .top, spacing: 14) {
                ProductThumbnailView(
                    imageURLString: product.imageURLString,
                    width: 82,
                    height: 98,
                    cornerRadius: 16
                )

                VStack(alignment: .leading, spacing: 7) {
                    Text(product.brand?.name ?? "브랜드 미상")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(product.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("출처: \(product.sourceDisplayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(product.category.rawValue) / \(productDetailCategory.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var selectedMeasurementSummary: some View {
        if let selectedSize {
            FitMatchCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "선택한 사이즈 실측", subtitle: "\(selectedSize.name.displaySizeName) 기준으로 자동 저장됩니다.")

                    VStack(spacing: 10) {
                        ForEach(visibleMeasurementKinds(for: selectedSize), id: \.id) { kind in
                            HStack {
                                Text(kind.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(formatMeasurement(selectedSize.measurements.value(for: kind)))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var bottomAction: some View {
        Group {
            switch step {
            case .size:
                PrimaryButton(title: "다음", systemImage: "chevron.right") {
                    withAnimation(.snappy(duration: 0.22)) {
                        step = .confirm
                    }
                }
                .disabled(selectedSize == nil)
                .opacity(selectedSize == nil ? 0.35 : 1)
            case .confirm:
                PrimaryButton(title: "내 옷장에 추가", systemImage: "plus") {
                    saveSelectedSize()
                }
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.35)
            }
        }
    }

    private var canSave: Bool {
        selectedSize != nil
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
            brandName: brandName.trimmingCharacters(in: .whitespacesAndNewlines),
            gender: .unisex,
            productName: productName.trimmingCharacters(in: .whitespacesAndNewlines),
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

        if isBasisItem {
            userFits
                .filter { $0.detailCategory == selectedDetailCategory && $0.isRepresentative }
                .forEach {
                    $0.isRepresentative = false
                    $0.updatedAt = Date()
                }
        }

        modelContext.insert(item)
        try? modelContext.save()
        onSaved?()
        dismiss()
    }

    private func normalizeDetailCategory() {
        if !availableDetailCategories.contains(selectedDetailCategory) {
            selectedDetailCategory = availableDetailCategories.first ?? .shortSleeve
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
            .measurementKinds(detailCategory: selectedDetailCategory, gender: .unisex)
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
}

private enum AddComparedProductStep {
    case size
    case confirm
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
