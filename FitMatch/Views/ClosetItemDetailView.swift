import SwiftUI
import SwiftData

struct ClosetItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var tabBarVisibilityController: TabBarVisibilityController
    @Query(sort: \UserFit.updatedAt, order: .reverse) private var userFits: [UserFit]
    @Query(sort: \RecommendationHistory.createdAt, order: .reverse) private var histories: [RecommendationHistory]
    @State private var isShowingEdit = false
    @State private var saveErrorMessage: String?
    @State private var pendingReferenceChange: PendingClosetEdit?

    let item: UserFit

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroCard
                quickSummaryCard
                basicInfoCard
                measurementCard

                if !item.fitMemo.isEmpty {
                    memoCard
                }
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("내 옷 정보")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("편집") {
                    isShowingEdit = true
                }
                .font(.subheadline.weight(.bold))
            }
        }
        .sheet(isPresented: $isShowingEdit) {
            NavigationStack {
                if item.isImportedFromURL {
                    ImportedClosetItemEditView(
                        item: item,
                        onDelete: {
                            deleteItemAndDismiss()
                        }
                    ) { selectedSize, category, detailCategory in
                        saveImportedChanges(
                            selectedSize,
                            category: category,
                            detailCategory: detailCategory
                        )
                    }
                } else {
                    AddClosetItemView(
                        item: item,
                        onDelete: {
                            deleteItemAndDismiss()
                        }
                    ) { editedItem in
                        applyChanges(from: editedItem)
                    }
                }
            }
            .presentationDragIndicator(.visible)
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
        .alert(
            "\(pendingReferenceChange?.detailCategory.rawValue ?? "이 분류") 기준 옷을 변경할까요?",
            isPresented: Binding(
                get: { pendingReferenceChange != nil },
                set: { if !$0 { pendingReferenceChange = nil } }
            )
        ) {
            Button("취소", role: .cancel) {
                pendingReferenceChange = nil
            }
            Button("변경") {
                applyPendingReferenceChange()
            }
        } message: {
            Text("같은 분류의 기존 기준 옷은 자동으로 해제됩니다.")
        }
        .onAppear {
            tabBarVisibilityController.hide(reason: .navigationDetail, source: "closet detail")
        }
        .onDisappear {
            tabBarVisibilityController.release(reason: .navigationDetail, source: "closet detail disappear")
        }
    }

    private var heroCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                if let imageURLString, !imageURLString.isEmpty {
                    ProductThumbnailView(
                        imageURLString: imageURLString,
                        category: item.category,
                        width: 320,
                        height: 260,
                        cornerRadius: 22
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    ClosetDetailPlaceholderImage(category: item.category)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.brandName)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(item.productName)
                                .font(.title3.weight(.black))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        if item.isRepresentative {
                            Text("기준 옷")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color(.systemBackground))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(Color.primary, in: Capsule())
                        }
                    }

                    HStack(spacing: 8) {
                        ClosetDetailChip(title: item.detailCategory.rawValue)
                        ClosetDetailChip(title: item.sizeName)
                        ClosetDetailChip(title: item.fitPreference.rawValue)
                    }
                }
            }
        }
    }

    private var quickSummaryCard: some View {
        HStack(spacing: 10) {
            ClosetSummaryTile(title: "카테고리", value: item.category.rawValue)
            ClosetSummaryTile(title: "사이즈", value: item.sizeName)
            ClosetSummaryTile(title: "핏", value: item.fitPreference.rawValue)
        }
    }

    private var basicInfoCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "기본 정보")

                VStack(spacing: 11) {
                    DetailInfoRow(title: "브랜드", value: item.brandName)
                    DetailInfoRow(title: "상품명", value: item.productName)
                    DetailInfoRow(title: "출처", value: sourceDescription)
                    DetailInfoRow(title: "성별", value: item.gender.rawValue)
                    DetailInfoRow(title: "분류", value: "\(item.category.rawValue) / \(item.detailCategory.rawValue)")
                    DetailInfoRow(title: "원본 카테고리", value: item.sourceCategoryDisplayText)
                }
            }
        }
    }

    private var measurementCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "실측값")

                LazyVGrid(columns: measurementGridColumns, spacing: 10) {
                    ForEach(item.category.measurementKinds(detailCategory: item.detailCategory, gender: item.gender)) { kind in
                        MeasurementValueTile(
                            title: kind.title,
                            value: measurementText(for: kind)
                        )
                    }
                }
            }
        }
    }

    private var measurementGridColumns: [GridItem] {
        let columnCount = item.category.serviceGroup == .bottom ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: columnCount)
    }

    private var memoCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "핏 메모")
                Text(item.fitMemo)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var imageURLString: String? {
        item.sourceProduct?.imageURLString?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sourceDescription: String {
        item.sourceName == item.sourceType.displayName
            ? item.sourceName
            : "\(item.sourceName) · \(item.sourceType.displayName)"
    }

    private func measurementText(for kind: MeasurementKind) -> String {
        let value = item.measurements.value(for: kind)
        return value > 0 ? value.cmText : "-"
    }

    private func applyChanges(from editedItem: UserFit) {
        if editedItem.isRepresentative,
           hasAnotherReference(
                category: editedItem.category,
                detailCategory: editedItem.detailCategory
           ) {
            pendingReferenceChange = PendingClosetEdit(
                editedItem: editedItem,
                selectedSize: nil,
                category: editedItem.category,
                detailCategory: editedItem.detailCategory
            )
            return
        }

        applyChangesImmediately(from: editedItem)
    }

    private func applyChangesImmediately(from editedItem: UserFit) {
        item.sourceType = editedItem.sourceType
        item.sourceName = editedItem.sourceName
        item.brandName = editedItem.brandName
        item.gender = editedItem.gender
        item.productName = editedItem.productName
        item.category = editedItem.category
        item.detailCategory = editedItem.detailCategory
        item.sizeName = editedItem.sizeName
        item.measurements = editedItem.measurements
        item.fitMemo = editedItem.fitMemo
        item.fitPreference = editedItem.fitPreference
        item.satisfaction = editedItem.satisfaction
        item.isRepresentative = editedItem.isRepresentative
        if item.isRepresentative {
            userFits
                .filter {
                    $0.id != item.id
                        && $0.category == item.category
                        && $0.detailCategory == item.detailCategory
                        && $0.isRepresentative
                }
                .forEach {
                    $0.isRepresentative = false
                    $0.updatedAt = Date()
                }
        }
        item.updatedAt = Date()
        do {
            try modelContext.save()
        } catch {
            saveErrorMessage = "수정 내용을 저장하지 못했습니다."
        }
    }

    private func saveImportedChanges(
        _ selectedSize: ProductSize,
        category: ClothingCategory,
        detailCategory: ClosetDetailCategory
    ) {
        if item.isRepresentative,
           hasAnotherReference(category: category, detailCategory: detailCategory) {
            pendingReferenceChange = PendingClosetEdit(
                editedItem: nil,
                selectedSize: selectedSize,
                category: category,
                detailCategory: detailCategory
            )
            return
        }

        applyImportedChanges(selectedSize, category: category, detailCategory: detailCategory)
    }

    private func applyImportedChanges(
        _ selectedSize: ProductSize,
        category: ClothingCategory,
        detailCategory: ClosetDetailCategory
    ) {
        item.category = category
        item.detailCategory = detailCategory
        item.sizeName = selectedSize.name.fitMatchDisplaySizeName
        item.measurements = selectedSize.measurements
        item.sourceProductSize = selectedSize
        item.updatedAt = Date()
        do {
            try modelContext.save()
        } catch {
            saveErrorMessage = "수정 내용을 저장하지 못했습니다."
        }
    }

    private func hasAnotherReference(
        category: ClothingCategory,
        detailCategory: ClosetDetailCategory
    ) -> Bool {
        userFits.contains {
            $0.id != item.id
                && $0.category == category
                && $0.detailCategory == detailCategory
                && $0.isRepresentative
        }
    }

    private func applyPendingReferenceChange() {
        guard let pendingReferenceChange else { return }

        userFits
            .filter {
                $0.id != item.id
                    && $0.category == pendingReferenceChange.category
                    && $0.detailCategory == pendingReferenceChange.detailCategory
                    && $0.isRepresentative
            }
            .forEach {
                $0.isRepresentative = false
                $0.updatedAt = Date()
            }

        if let editedItem = pendingReferenceChange.editedItem {
            applyChangesImmediately(from: editedItem)
        } else if let selectedSize = pendingReferenceChange.selectedSize {
            applyImportedChanges(
                selectedSize,
                category: pendingReferenceChange.category,
                detailCategory: pendingReferenceChange.detailCategory
            )
        }
        self.pendingReferenceChange = nil
    }

    private func deleteItemAndDismiss() {
        histories
            .filter { $0.userFit.id == item.id }
            .forEach { modelContext.delete($0) }

        modelContext.delete(item)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveErrorMessage = "옷장 항목을 삭제하지 못했습니다."
        }
    }
}

private extension String {
    var normalizedForClosetDetail: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct ClosetDetailPlaceholderImage: View {
    let category: ClothingCategory

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 82, height: 82)
                .background(Color(.systemBackground), in: Circle())

            Text("이미지 없음")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var iconName: String {
        switch category.serviceGroup {
        case .shoes:
            return "shoe.2"
        case .accessory:
            return "watch.analog"
        default:
            return "tshirt"
        }
    }
}

private struct ClosetDetailChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
    }
}

private struct ClosetSummaryTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 7) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.black))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct DetailInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct ImportedClosetItemEditView: View {
    @Environment(\.dismiss) private var dismiss
    let item: UserFit
    let onDelete: () -> Void
    let onSave: (ProductSize, ClothingCategory, ClosetDetailCategory) -> Void

    @State private var selectedSizeID: UUID?
    @State private var selectedCategory: ClothingCategory
    @State private var selectedDetailCategory: ClosetDetailCategory
    @State private var isShowingDeleteAlert = false

    init(
        item: UserFit,
        onDelete: @escaping () -> Void,
        onSave: @escaping (ProductSize, ClothingCategory, ClosetDetailCategory) -> Void
    ) {
        self.item = item
        self.onDelete = onDelete
        self.onSave = onSave
        let sizes = Self.availableSizes(for: item)
        let initialID = item.sourceProductSize?.id
            ?? sizes.first { $0.name.fitMatchDisplaySizeName == item.sizeName }?.id
            ?? (sizes.count == 1 ? sizes.first?.id : nil)
        _selectedSizeID = State(initialValue: initialID)
        _selectedCategory = State(initialValue: item.category)
        _selectedDetailCategory = State(initialValue: item.detailCategory)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                productInfoCard
                categorySelectionCard
                sizeSelectionCard
                measurementSummaryCard
                deleteButton
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("내 옷 정보 수정")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            normalizeCategorySelection()
        }
        .safeAreaInset(edge: .bottom) {
            bottomSaveBar
        }
        .alert("이 옷을 삭제할까요?", isPresented: $isShowingDeleteAlert) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                onDelete()
                dismiss()
            }
        } message: {
            Text("삭제한 옷 정보는 복구할 수 없습니다.")
        }
    }

    private var categorySelectionCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "내 옷장 분류",
                    subtitle: "추천 비교에 사용할 카테고리입니다."
                )
                AddClosetSelectionMenu(
                    title: "대분류",
                    value: selectedCategory.rawValue,
                    options: availableCategories,
                    optionTitle: \.rawValue,
                    selection: $selectedCategory
                ) { _ in
                    normalizeDetailCategory()
                }
                AddClosetSelectionMenu(
                    title: "세부 카테고리",
                    value: selectedDetailCategory.rawValue,
                    options: availableDetailCategories,
                    optionTitle: \.rawValue,
                    selection: $selectedDetailCategory
                )
            }
        }
    }

    private var headerCard: some View {
        CardView(radius: 26, padding: 20) {
            HStack(alignment: .center, spacing: 16) {
                ProductThumbnailView(
                    imageURLString: item.sourceProduct?.imageURLString,
                    category: item.category,
                    width: 72,
                    height: 88,
                    cornerRadius: 18
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("상품 사이즈 수정")
                        .font(.title2.weight(.black))
                        .foregroundStyle(.primary)
                    Text("쇼핑몰 사이즈표 원본은 수정하지 않고, 내가 가진 사이즈만 변경합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var productInfoCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "상품 정보")
                VStack(spacing: 11) {
                    DetailInfoRow(title: "쇼핑몰", value: item.sourceName)
                    DetailInfoRow(title: "브랜드", value: item.brandName)
                    DetailInfoRow(title: "상품명", value: item.productName)
                    DetailInfoRow(title: "분류", value: "\(item.category.rawValue) / \(item.detailCategory.rawValue)")
                    DetailInfoRow(title: "원본 카테고리", value: item.sourceCategoryDisplayText)
                }
            }
        }
    }

    private var sizeSelectionCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "보유 사이즈")
                if availableSizes.isEmpty {
                    Text("선택할 수 있는 원본 사이즈표가 없습니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ProductSizeSelectionGrid(sizes: availableSizes, selectedSizeID: $selectedSizeID)
                }
            }
        }
    }

    @ViewBuilder
    private var measurementSummaryCard: some View {
        if let selectedSize {
            FitMatchCard {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "선택한 사이즈 실측")
                    LazyVGrid(columns: measurementGridColumns, spacing: 10) {
                        ForEach(visibleMeasurementKinds(for: selectedSize)) { kind in
                            MeasurementValueTile(
                                title: kind.title,
                                value: measurementText(selectedSize.measurements.value(for: kind))
                            )
                        }
                    }
                }
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            isShowingDeleteAlert = true
        } label: {
            Text("삭제")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var bottomSaveBar: some View {
        VStack(spacing: 10) {
            if selectedSize == nil {
                Label("저장할 사이즈를 선택해 주세요.", systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                guard let selectedSize else { return }
                onSave(selectedSize, selectedCategory, selectedDetailCategory)
                dismiss()
            } label: {
                Text("수정 저장")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(selectedSize == nil ? .secondary : Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        selectedSize == nil ? Color(.secondarySystemGroupedBackground) : Color.primary,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(selectedSize == nil)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.regularMaterial)
    }

    private var availableSizes: [ProductSize] {
        Self.availableSizes(for: item)
    }

    private var availableCategories: [ClothingCategory] {
        ClothingCategory.closetCategories(for: item.gender).filter { $0 != .other }
    }

    private var availableDetailCategories: [ClosetDetailCategory] {
        ClosetDetailCategory.options(for: selectedCategory, gender: item.gender)
            .filter { $0 != .other }
    }

    private func normalizeDetailCategory() {
        if !availableDetailCategories.contains(selectedDetailCategory) {
            selectedDetailCategory = availableDetailCategories.first ?? .other
        }
    }

    private func normalizeCategorySelection() {
        if !availableCategories.contains(selectedCategory) {
            selectedCategory = availableCategories.first ?? .top
        }
        normalizeDetailCategory()
    }

    private static func availableSizes(for item: UserFit) -> [ProductSize] {
        let sourceSizes = item.sourceProduct?.sizes ?? []
        let sizes = sourceSizes.isEmpty
            ? [item.sourceProductSize].compactMap { $0 }
            : sourceSizes
        return ParsedProductSizeNormalizer.uniqueProductSizes(sizes.sorted {
            if $0.displayOrder != $1.displayOrder {
                return $0.displayOrder < $1.displayOrder
            }
            return $0.name < $1.name
        })
    }

    private var selectedSize: ProductSize? {
        guard let selectedSizeID else { return nil }
        return availableSizes.first { $0.id == selectedSizeID }
    }

    private var measurementGridColumns: [GridItem] {
        let columnCount = item.category.serviceGroup == .bottom ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: columnCount)
    }

    private func visibleMeasurementKinds(for size: ProductSize) -> [MeasurementKind] {
        item.category
            .measurementKinds(detailCategory: item.detailCategory, gender: item.gender)
            .filter { size.measurements.value(for: $0) > 0 }
    }

    private func measurementText(_ value: Double) -> String {
        value > 0 ? value.cmText : "-"
    }
}

private struct PendingClosetEdit {
    let editedItem: UserFit?
    let selectedSize: ProductSize?
    let category: ClothingCategory
    let detailCategory: ClosetDetailCategory
}

private struct MeasurementValueTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
