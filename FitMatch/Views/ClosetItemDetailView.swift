import SwiftUI
import SwiftData

struct ClosetItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.fitMatchClosetSyncCoordinator) private var closetSync
    @Environment(\.fitMatchComparisonSyncCoordinator) private var comparisonSync
    @EnvironmentObject private var authSession: FitMatchAuthSessionStore
    @EnvironmentObject private var tabBarVisibilityController: TabBarVisibilityController
    @Query(sort: \UserFit.updatedAt, order: .reverse) private var cachedUserFits: [UserFit]

    private var userFits: [UserFit] {
        cachedUserFits.filter(\.isActiveClosetItem)
    }
    @Query(sort: \RecommendationHistory.createdAt, order: .reverse) private var histories: [RecommendationHistory]
    @State private var isShowingEdit = false
    @State private var saveErrorMessage: String?

    let item: UserFit
    private let diagnosticsStartedAt: TimeInterval

    init(item: UserFit) {
        self.item = item
        self.diagnosticsStartedAt = DetailPerformanceDiagnostics.now()
    }

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
        .diagnosesScrollPerformance(screen: "closet_item_detail")
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
                        hasComparisonHistory: hasComparisonHistory,
                        onDelete: {
                            await deleteItemAndDismiss()
                        },
                        prepareLinkedSizeOptions: linkedSizeOptionsPreparation
                    ) { draft, confirmsReferenceReplacement in
                        guard let userID = authSession.authenticatedUserID,
                              let closetSync else {
                            return .failed(
                                "로그인 상태가 변경되어 수정 결과를 안전하게 확인할 수 없습니다."
                            )
                        }
                        return await closetSync.saveLinkedClosetEdit(
                            draft,
                            userID: userID,
                            modelContext: modelContext,
                            confirmsReferenceReplacement: confirmsReferenceReplacement
                        )
                    }
                } else {
                    AddClosetItemView(
                        item: item,
                        hasComparisonHistory: hasComparisonHistory,
                        onDelete: {
                            await deleteItemAndDismiss()
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
        .onAppear {
            logInitialPerformance()
            tabBarVisibilityController.hide(reason: .navigationDetail, source: "closet detail")
        }
        .onDisappear {
            tabBarVisibilityController.release(reason: .navigationDetail, source: "closet detail disappear")
        }
    }

    private var linkedSizeOptionsPreparation: (() async throws -> FitMatchLinkedClosetSizeEditPreparation)? {
        guard item.isImportedFromURL else { return nil }
        return {
            guard let userID = authSession.authenticatedUserID,
                  let closetSync else {
                throw FitMatchLinkedClosetSizeEditPreparationError.authenticationChanged
            }
            return try await closetSync.prepareLinkedClosetSizeEdit(
                item: item,
                userID: userID
            )
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
                        cornerRadius: 22,
                        diagnosticContext: "closet_item_detail"
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
                    }

                    HStack(spacing: 8) {
                        ClosetDetailChip(title: comparisonGroupDisplayName)
                        ClosetDetailChip(title: item.sizeName)
                        ClosetDetailChip(title: item.fitPreference.rawValue)
                    }
                }
            }
        }
    }

    private var quickSummaryCard: some View {
        HStack(spacing: 10) {
            ClosetSummaryTile(title: "비교 그룹", value: comparisonGroupDisplayName)
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
                    DetailInfoRow(title: "비교 그룹", value: comparisonGroupDisplayName)
                    DetailInfoRow(title: "원본 카테고리", value: item.sourceCategoryDisplayText)
                }
            }
        }
    }

    private var comparisonGroupDisplayName: String {
        item.comparisonGroup?.displayName ?? "미지정"
    }

    private var measurementCard: some View {
        let sourceRows = MeasurementResolver.sourceDisplayRows(
            records: item.measurementRecords
        )
        return FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: sourceRows.isEmpty ? "실측값" : "플랫폼 사이즈표")

                LazyVGrid(columns: measurementGridColumns, spacing: 10) {
                    if sourceRows.isEmpty {
                        ForEach(item.category.measurementKinds(detailCategory: item.detailCategory, gender: item.gender)) { kind in
                            MeasurementValueTile(
                                title: MeasurementResolver.title(
                                    for: kind,
                                    records: item.measurementRecords
                                ),
                                value: measurementText(for: kind)
                            )
                        }
                    } else {
                        ForEach(sourceRows) { row in
                            MeasurementValueTile(title: row.title, value: row.valueText)
                        }
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
        item.sourceProduct?.imageURLStringForDisplay?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sourceDescription: String {
        item.sourceName == item.sourceType.displayName
            ? item.sourceName
            : "\(item.sourceName) · \(item.sourceType.displayName)"
    }

    private func measurementText(for kind: MeasurementKind) -> String {
        MeasurementResolver.value(
            for: kind,
            measurements: item.measurements,
            records: item.measurementRecords
        )?.cmText ?? "-"
    }

    private func applyChanges(from editedItem: UserFit) -> Bool {
        return applyChangesImmediately(from: editedItem)
    }

    @discardableResult
    private func applyChangesImmediately(from editedItem: UserFit) -> Bool {
        switch FitMatchClosetItemEditAction.saveManual(
            item: item,
            editedItem: editedItem,
            activeClosetItems: userFits,
            in: modelContext
        ) {
        case .saved:
            return true
        case .persistenceFailed:
            saveErrorMessage = "수정 내용을 저장하지 못했습니다."
            return false
        }
    }

    private func deleteItemAndDismiss() async -> Bool {
        let outcome = await FitMatchClosetDeletionAction.delete(
            item: item,
            histories: histories,
            in: modelContext,
            comparisonSync: comparisonSync,
            closetSync: closetSync
        )
        if case .deleted = outcome {
            dismiss()
            return true
        }
        saveErrorMessage = outcome.userVisibleMessage
        return false
    }

    private var hasComparisonHistory: Bool {
        histories.contains { $0.referencesClosetItem(clientItemID: item.id) }
    }

    private func logInitialPerformance() {
        DetailPerformanceDiagnostics.log(
            screen: "closet_item_detail",
            event: "on_appear",
            startedAt: diagnosticsStartedAt,
            metadata: "user_fits=\(userFits.count) histories=\(histories.count) measurements=\(item.measurementRecords.count) imported=\(item.isImportedFromURL)"
        )
        DispatchQueue.main.async {
            DetailPerformanceDiagnostics.log(
                screen: "closet_item_detail",
                event: "next_main_runloop",
                startedAt: diagnosticsStartedAt
            )
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            DetailPerformanceDiagnostics.log(
                screen: "closet_item_detail",
                event: "settled_250ms",
                startedAt: diagnosticsStartedAt
            )
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
    let hasComparisonHistory: Bool
    let onDelete: () async -> Bool
    let prepareLinkedSizeOptions: (() async throws -> FitMatchLinkedClosetSizeEditPreparation)?
    let onSave: (FitMatchLinkedClosetEditDraft, Bool) async
        -> FitMatchLinkedClosetEditSaveOutcome

    @State private var selectedSizeID: UUID?
    @State private var selectedCategory: ClothingCategory
    @State private var selectedDetailCategory: ClosetDetailCategory
    @State private var selectedCategoryCode: String
    @State private var selectedDetailCategoryCode: String
    @State private var didExplicitlyChangeClassification = false
    @State private var selectedComparisonGroup: FitMatchComparisonGroup
    @State private var isShowingDeleteAlert = false
    @State private var isShowingSaveError = false
    @State private var isDeleting = false
    @State private var isPreparingLinkedSizeOptions = false
    @State private var linkedSizePreparation: FitMatchLinkedClosetSizeEditPreparation?
    @State private var linkedSizePreparationMessage: String?
    @State private var isSaving = false
    @State private var isReconcilingAcceptedServerEdit = false
    @State private var saveErrorMessage: String?

    init(
        item: UserFit,
        hasComparisonHistory: Bool,
        onDelete: @escaping () async -> Bool,
        prepareLinkedSizeOptions: (() async throws -> FitMatchLinkedClosetSizeEditPreparation)? = nil,
        onSave: @escaping (FitMatchLinkedClosetEditDraft, Bool) async
            -> FitMatchLinkedClosetEditSaveOutcome
    ) {
        self.item = item
        self.hasComparisonHistory = hasComparisonHistory
        self.onDelete = onDelete
        self.prepareLinkedSizeOptions = prepareLinkedSizeOptions
        self.onSave = onSave
        let sizes = Self.availableSizes(for: item)
        // A server-linked edit deliberately starts empty until the remote row
        // and fresh runtime establish an exact current product_size_id. The
        // legacy/local-only editor retains its historical presentation path.
        let initialID: UUID? = prepareLinkedSizeOptions == nil
            ? (item.sourceProductSize?.id
                ?? sizes.first { $0.name.fitMatchDisplaySizeName == item.sizeName }?.id
                ?? (sizes.count == 1 ? sizes.first?.id : nil))
            : nil
        _selectedSizeID = State(initialValue: initialID)
        _selectedCategory = State(initialValue: item.category)
        _selectedDetailCategory = State(initialValue: item.detailCategory)
        _selectedCategoryCode = State(initialValue: item.resolvedCategoryCode ?? item.category.taxonomyCode)
        _selectedDetailCategoryCode = State(initialValue: item.resolvedDetailCategoryCode ?? "")
        _selectedComparisonGroup = State(initialValue: item.comparisonGroup
            ?? FitMatchComparisonGroup.legacyFallback(
                category: item.category,
                detailCategory: item.detailCategory
            )
            ?? .tops)
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
        .disabled(isSubmissionInputLocked)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("내 옷 정보 수정")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            normalizeCategorySelection()
        }
        .task(id: item.id) {
            await loadLinkedSizeOptionsIfNeeded()
        }
        .safeAreaInset(edge: .bottom) {
            bottomSaveBar
        }
        .alert("이 옷을 삭제할까요?", isPresented: $isShowingDeleteAlert) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                deleteCurrentItem()
            }
        } message: {
            Text("이 옷을 삭제하면 이 옷으로 비교한 기록도 목록에서 함께 삭제돼요. 그래도 삭제할까요?")
        }
        .alert("저장하지 못했습니다", isPresented: $isShowingSaveError) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "입력한 내용은 유지됩니다. 잠시 후 다시 시도해 주세요.")
        }
        .interactiveDismissDisabled(isSubmissionInputLocked)
    }

    private var categorySelectionCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "비교 그룹",
                    subtitle: "이 옷과 함께 비교할 상품 그룹입니다."
                )
                AddClosetSelectionMenu(
                    title: "비교 그룹",
                    value: selectedComparisonGroup.displayName,
                    options: FitMatchComparisonGroup.allCases,
                    optionTitle: \.displayName,
                    selection: $selectedComparisonGroup
                )
            }
        }
    }

    private var headerCard: some View {
        CardView(radius: 26, padding: 20) {
            HStack(alignment: .center, spacing: 16) {
                ProductThumbnailView(
                    imageURLString: item.sourceProduct?.imageURLStringForDisplay,
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
                    DetailInfoRow(
                        title: "저장된 비교 그룹",
                        value: item.comparisonGroup?.displayName ?? "미지정"
                    )
                    DetailInfoRow(title: "원본 카테고리", value: item.sourceCategoryDisplayText)
                }
            }
        }
    }

    private var sizeSelectionCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "보유 사이즈")
                if isPreparingLinkedSizeOptions {
                    ProgressView("서버 사이즈 확인 중")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let linkedSizePreparationMessage {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(linkedSizePreparationMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("다시 시도") {
                            Task { @MainActor in
                                await loadLinkedSizeOptionsIfNeeded()
                            }
                        }
                        .font(.subheadline.weight(.bold))
                        .disabled(isSubmissionInputLocked)
                    }
                } else if availableSizes.isEmpty {
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
                                value: MeasurementResolver.value(
                                    for: kind,
                                    measurements: selectedSize.measurements,
                                    records: selectedSize.measurementRecords
                                )?.cmText ?? "-"
                            )
                        }
                    }
                }
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            if hasComparisonHistory {
                isShowingDeleteAlert = true
            } else {
                deleteCurrentItem()
            }
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
        .disabled(isDeleting)
    }

    private func deleteCurrentItem() {
        guard !isDeleting else { return }
        isDeleting = true
        Task { @MainActor in
            defer { isDeleting = false }
            if await onDelete() {
                dismiss()
            } else {
                isShowingSaveError = true
            }
        }
    }

    private var bottomSaveBar: some View {
        VStack(spacing: 10) {
            if isReconcilingAcceptedServerEdit {
                Label(
                    "서버 수정 결과를 확인하는 중입니다. 등록 결과를 다시 확인해 주세요.",
                    systemImage: "info.circle"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let linkedSizePreparationMessage {
                Label(linkedSizePreparationMessage, systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if selectedSize == nil {
                Label("저장할 사이즈를 선택해 주세요.", systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                guard let draft = currentLinkedEditDraft else {
                    saveErrorMessage = "서버의 최신 사이즈 정보를 확인하지 못했습니다. 다시 시도해 주세요."
                    isShowingSaveError = true
                    return
                }
                submitLinkedEdit(draft)
            } label: {
                Text(isSaving ? "저장 중" : (
                    isReconcilingAcceptedServerEdit
                        ? "등록 결과 다시 확인"
                        : "수정 저장"
                ))
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
            .disabled(
                selectedSize == nil
                    || isPreparingLinkedSizeOptions
                    || (prepareLinkedSizeOptions != nil && linkedSizePreparation == nil)
                    || isSaving
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.regularMaterial)
    }

    private var isSubmissionInputLocked: Bool {
        isSaving || isReconcilingAcceptedServerEdit
    }

    private var currentLinkedEditDraft: FitMatchLinkedClosetEditDraft? {
        guard let linkedSizePreparation,
              let selectedSizeID,
              linkedSizePreparation.option(displaySizeID: selectedSizeID) != nil else {
            return nil
        }
        return FitMatchLinkedClosetEditDraft(
            item: item,
            preparation: linkedSizePreparation,
            selectedDisplaySizeID: selectedSizeID,
            category: selectedCategory,
            detailCategory: selectedDetailCategory,
            categoryCode: selectedCategoryCode,
            detailCode: selectedDetailCategoryCode,
            didExplicitlyChangeClassification: didExplicitlyChangeClassification,
            comparisonGroupCode: selectedComparisonGroup.rawValue
        )
    }

    private func submitLinkedEdit(_ draft: FitMatchLinkedClosetEditDraft) {
        guard !isSaving else { return }
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            let outcome = await onSave(draft, false)
            switch outcome {
            case .saved:
                isReconcilingAcceptedServerEdit = false
                dismiss()
            case .needsReferenceConfirmation:
                saveErrorMessage = "이전 옷장 설정을 정리하지 못했습니다. 다시 시도해 주세요."
                isShowingSaveError = true
            case .reconciliationRequired(let message):
                isReconcilingAcceptedServerEdit = true
                saveErrorMessage = message
                // Keep the editor on screen and lock the immutable accepted
                // request. The bottom action remains enabled for read-back.
            case .failed(let message):
                isReconcilingAcceptedServerEdit = false
                saveErrorMessage = message
                isShowingSaveError = true
            }
        }
    }

    private var availableSizes: [ProductSize] {
        if let linkedSizePreparation {
            return linkedSizePreparation.options.map(\.productSize)
        }
        if prepareLinkedSizeOptions != nil {
            return []
        }
        return Self.availableSizes(for: item)
    }

    private var availableCategories: [TaxonomyCategory] {
        FitMatchTaxonomyProvider.shared.activeCategories
    }

    private var availableDetailCategories: [TaxonomyOption] {
        FitMatchTaxonomyProvider.shared.activeDetails(categoryCode: selectedCategoryCode)
    }

    private var selectedCategoryOption: TaxonomyCategory? {
        availableCategories.first { $0.code == selectedCategoryCode }
    }

    private var selectedDetailOption: TaxonomyOption? {
        availableDetailCategories.first { $0.code == selectedDetailCategoryCode }
    }

    private func normalizeDetailCategory() {
        if selectedDetailOption == nil, let first = availableDetailCategories.first {
            selectedDetailCategoryCode = first.code
            selectedDetailCategory = ClosetDetailCategory.fromTaxonomyCode(first.code)
        }
    }

    private func normalizeCategorySelection() {
        if selectedCategoryOption == nil, let first = availableCategories.first {
            selectedCategoryCode = first.code
            selectedCategory = ClothingCategory.fromTaxonomyCode(first.code)
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

    private func loadLinkedSizeOptionsIfNeeded() async {
        guard let prepareLinkedSizeOptions,
              !isPreparingLinkedSizeOptions,
              linkedSizePreparation == nil else {
            return
        }
        isPreparingLinkedSizeOptions = true
        linkedSizePreparationMessage = nil
        defer { isPreparingLinkedSizeOptions = false }
        do {
            let preparation = try await prepareLinkedSizeOptions()
            guard preparation.clientItemID == item.id,
                  preparation.option(displaySizeID: preparation.initialDisplaySizeID) != nil else {
                throw FitMatchLinkedClosetSizeEditPreparationError.runtimeIdentityUnavailable
            }
            linkedSizePreparation = preparation
            selectedSizeID = preparation.initialDisplaySizeID
        } catch {
            linkedSizePreparationMessage = (error as? LocalizedError)?.errorDescription
                ?? "서버의 최신 사이즈 정보를 확인하지 못했습니다. 새로고침 후 다시 시도해 주세요."
            selectedSizeID = nil
        }
    }

    private var measurementGridColumns: [GridItem] {
        let columnCount = item.category.serviceGroup == .bottom ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: columnCount)
    }

    private func visibleMeasurementKinds(for size: ProductSize) -> [MeasurementKind] {
        item.category
            .measurementKinds(detailCategory: item.detailCategory, gender: item.gender)
            .filter {
                MeasurementResolver.value(
                    for: $0,
                    measurements: size.measurements,
                    records: size.measurementRecords
                ) != nil
            }
    }

    private func measurementText(_ value: Double) -> String {
        value > 0 ? value.cmText : "-"
    }
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
