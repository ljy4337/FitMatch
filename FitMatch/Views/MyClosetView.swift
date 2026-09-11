import SwiftUI
import SwiftData

struct MyClosetView: View {
    var onLogout: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.fitMatchClosetSyncCoordinator) private var closetSync
    @Environment(\.fitMatchComparisonSyncCoordinator) private var comparisonSync
    @Query(sort: \UserFit.createdAt, order: .reverse) private var cachedUserFits: [UserFit]
    @Query(sort: \RecommendationHistory.createdAt, order: .reverse) private var histories: [RecommendationHistory]
    @AppStorage("FitMatch.closetViewLayout") private var closetViewLayoutRaw = ContentListLayout.list.rawValue
    @State private var activeSheet: ClosetActiveSheet?
    @State private var selectedComparisonGroup: FitMatchComparisonGroup?
    @State private var selectedBrand: String?
    @State private var sortOption: FitMatchClosetSortOption = .recent
    @State private var saveErrorMessage: String?
    @State private var isTopChromeVisible = true
    @State private var selectedClosetItemID: UUID?
    @State private var displayedItems: [UserFit] = []
    @State private var pendingDeleteItem: UserFit?
    @State private var deletingItemID: UUID?

    private var userFits: [UserFit] {
        FitMatchClosetPresentation.activeItems(from: cachedUserFits)
    }

    var body: some View {
        ZStack(alignment: .top) {
            closetContent
            closetTopChrome
                .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: Binding(
            get: { selectedClosetItemForDetail != nil },
            set: { if !$0 { selectedClosetItemID = nil } }
        )) {
            if let selectedClosetItemForDetail {
                ClosetItemDetailView(item: selectedClosetItemForDetail)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addMethod:
                AddClosetMethodSheet(
                    onLink: {
                        dismissActiveSheet()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            presentActiveSheet(.linkRegistration)
                        }
                    },
                    onManual: {
                        dismissActiveSheet()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            presentActiveSheet(.manualAdd)
                        }
                    }
                )
                .presentationDetents([.height(290)])
                .presentationDragIndicator(.visible)
            case .manualAdd:
                NavigationStack {
                    AddClosetItemView { item in
                        FitMatchClosetRegistrationPersistence.save(
                            item,
                            in: modelContext
                        )
                    }
                }
                .presentationDragIndicator(.visible)
            case .linkRegistration:
                NavigationStack {
                    LinkClosetRegistrationView()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
        .alert(
            "이 옷을 삭제할까요?",
            isPresented: Binding(
                get: { pendingDeleteItem != nil },
                set: { if !$0 { pendingDeleteItem = nil } }
            )
        ) {
            Button("취소", role: .cancel) {
                pendingDeleteItem = nil
            }
            Button("삭제", role: .destructive) {
                guard let item = pendingDeleteItem else { return }
                pendingDeleteItem = nil
                deleteItem(item)
            }
        } message: {
            Text("이 옷을 삭제하면 이 옷으로 비교한 기록도 목록에서 함께 삭제돼요. 그래도 삭제할까요?")
        }
        .onAppear {
            rebuildDisplayedItems()
        }
        .onChange(of: selectedComparisonGroup) { _, _ in
            rebuildDisplayedItems()
        }
        .onChange(of: selectedBrand) { _, _ in
            rebuildDisplayedItems()
        }
        .onChange(of: sortOption) { _, _ in
            rebuildDisplayedItems()
        }
        .onChange(of: closetItemsPresentationRevision) { _, _ in
            rebuildDisplayedItems()
        }
    }

    private var closetHeader: some View {
        ContentFilterBar(filters: closetFilterItems, layout: closetLayoutBinding)
    }

    @ViewBuilder
    private var closetTopChrome: some View {
        CollapsibleTopChrome(isVisible: isTopChromeVisible) {
            FitMatchNavigationHeader(onLogout: onLogout)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)
                .background(Color(.systemBackground))
        }
    }

    @ViewBuilder
    private var closetContent: some View {
        switch closetLayout {
        case .list:
            closetList
        case .grid:
            closetGrid
        }
    }

    private var closetList: some View {
        List {
            closetHeader
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())

            if userFits.isEmpty {
                EmptyClosetView {
                    presentActiveSheet(.addMethod)
                }
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 36, leading: 20, bottom: 24, trailing: 20))
            } else {
                ForEach(displayedItems) { item in
                    Button {
                        selectedClosetItemID = item.id
                    } label: {
                        ClosetItemCard(item: item)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        deleteSwipeButton(for: item)
                    }
                }

                if displayedItems.isEmpty {
                    EmptyFilterResultView()
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 24, leading: 20, bottom: 24, trailing: 20))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, FitMatchTopChromeMetrics.height, for: .scrollContent)
        .hidesBottomTabBarOnScroll(tab: .my, topChrome: $isTopChromeVisible)
    }

    private var closetGrid: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                closetHeader

                if userFits.isEmpty {
                    EmptyClosetView {
                        presentActiveSheet(.addMethod)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 36)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(displayedItems) { item in
                        NavigationLink {
                            ClosetItemDetailView(item: item)
                        } label: {
                            ClosetGridCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }

                    if displayedItems.isEmpty {
                        EmptyFilterResultView()
                            .gridCellColumns(2)
                            .padding(.top, 24)
                    }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
        }
        .contentMargins(.top, FitMatchTopChromeMetrics.height, for: .scrollContent)
        .hidesBottomTabBarOnScroll(tab: .my, topChrome: $isTopChromeVisible)
    }

    private var selectedClosetItemForDetail: UserFit? {
        guard let selectedClosetItemID else {
            return nil
        }

        return userFits.first { $0.id == selectedClosetItemID }
    }

    private func rebuildDisplayedItems() {
        displayedItems = FitMatchClosetPresentation.displayedItems(
            from: cachedUserFits,
            comparisonGroup: selectedComparisonGroup,
            brand: selectedBrand,
            sort: sortOption
        )
    }

    private var closetLayout: ContentListLayout {
        get { ContentListLayout(rawValue: closetViewLayoutRaw) ?? .list }
        nonmutating set { closetViewLayoutRaw = newValue.rawValue }
    }

    private var closetLayoutBinding: Binding<ContentListLayout> {
        Binding(
            get: { closetLayout },
            set: { closetLayout = $0 }
        )
    }

    private var closetFilterItems: [ContentFilterItem] {
        [
            ContentFilterItem(
                id: "comparison_group",
                selectedID: selectedComparisonGroup?.rawValue ?? "all",
                selectedTitle: selectedComparisonGroup?.displayName ?? "전체 그룹",
                options: [ContentFilterOption(id: "all", title: "전체")]
                    + availableComparisonGroups.map {
                        ContentFilterOption(id: $0.rawValue, title: $0.displayName)
                    },
                onSelect: { id in
                    selectedComparisonGroup = id == "all"
                        ? nil
                        : FitMatchComparisonGroup(rawValue: id)
                }
            ),
            ContentFilterItem(
                id: "brand",
                selectedID: selectedBrand ?? "all",
                selectedTitle: selectedBrand ?? "브랜드",
                options: [ContentFilterOption(id: "all", title: "전체 브랜드")]
                    + availableBrands.map { ContentFilterOption(id: $0, title: $0) },
                onSelect: { id in
                    selectedBrand = id == "all" ? nil : id
                }
            ),
            ContentFilterItem(
                id: "sort",
                selectedID: sortOption.rawValue,
                selectedTitle: sortOption.title,
                options: FitMatchClosetSortOption.allCases.map { ContentFilterOption(id: $0.rawValue, title: $0.title) },
                onSelect: { id in
                    sortOption = FitMatchClosetSortOption(rawValue: id) ?? .recent
                }
            )
        ]
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private var availableComparisonGroups: [FitMatchComparisonGroup] {
        FitMatchComparisonGroup.allCases.filter { group in
            userFits.contains { $0.comparisonGroup == group }
        }
    }

    private var availableBrands: [String] {
        Array(Set(userFits.map(\.brandName))).sorted()
    }

    private var closetItemsPresentationRevision: [String] {
        userFits.map { item in
            "\(item.id.uuidString)|\(item.comparisonGroupCode ?? "")|\(item.brandName)|\(item.updatedAt.timeIntervalSinceReferenceDate)"
        }
    }

    private func presentActiveSheet(_ sheet: ClosetActiveSheet) {
        #if DEBUG
        print("[MyClosetView] activeSheet -> \(sheet.logName)")
        #endif
        activeSheet = nil
        DispatchQueue.main.async {
            activeSheet = sheet
        }
    }

    private func dismissActiveSheet() {
        #if DEBUG
        print("[MyClosetView] activeSheet -> nil")
        #endif
        activeSheet = nil
    }

    private func deleteItem(_ item: UserFit) {
        guard deletingItemID == nil else { return }
        deletingItemID = item.id

        Task { @MainActor in
            defer { deletingItemID = nil }
            let outcome = await FitMatchClosetDeletionAction.delete(
                item: item,
                histories: histories,
                in: modelContext,
                comparisonSync: comparisonSync,
                closetSync: closetSync
            )
            rebuildDisplayedItems()
            saveErrorMessage = outcome.userVisibleMessage
        }
    }

    @ViewBuilder
    private func deleteSwipeButton(for item: UserFit) -> some View {
        Button(role: .destructive) {
            if historiesReferencing(item).isEmpty {
                deleteItem(item)
            } else {
                pendingDeleteItem = item
            }
        } label: {
            Label("삭제", systemImage: "trash")
        }
        .disabled(deletingItemID == item.id)
        .tint(.red)
    }

    private func historiesReferencing(_ item: UserFit) -> [RecommendationHistory] {
        histories.filter { $0.referencesClosetItem(clientItemID: item.id) }
    }
}

private extension String {
    var normalizedForBasis: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private enum ClosetActiveSheet: Identifiable {
    case addMethod
    case manualAdd
    case linkRegistration

    var id: String {
        logName
    }

    var logName: String {
        switch self {
        case .addMethod:
            return "addMethod"
        case .manualAdd:
            return "manualAdd"
        case .linkRegistration:
            return "linkRegistration"
        }
    }
}

private struct ClosetDashboardTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.headline.weight(.black))
                .foregroundStyle(.primary)
                .monospacedDigit()
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(isSelected ? Color(.systemBackground) : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.primary : Color(.secondarySystemGroupedBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyFilterResultView: View {
    var body: some View {
        ContentUnavailableView(
            "조건에 맞는 옷이 없어요.",
            systemImage: "line.3.horizontal.decrease.circle",
            description: Text("검색어나 필터를 조정해 주세요.")
        )
    }
}

struct AddClosetMethodSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onLink: () -> Void
    let onManual: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("내 옷 추가")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Text("상품 링크로 불러오거나 직접 입력할 수 있어요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                AddClosetMethodRow(
                    title: "상품 링크로 불러오기",
                    subtitle: "URL로 사이즈표를 불러온 뒤 내 옷장에 저장",
                    systemImage: "link",
                    isPrimary: true
                ) {
                    onLink()
                }

                AddClosetMethodRow(
                    title: "직접 입력하기",
                    subtitle: "브랜드, 카테고리, 실측값을 직접 입력",
                    systemImage: "square.and.pencil",
                    isPrimary: false
                ) {
                    onManual()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Color(.systemGroupedBackground))
    }
}

private struct AddClosetMethodRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(isPrimary ? Color(.systemBackground) : .primary)
                    .frame(width: 38, height: 38)
                    .background(isPrimary ? Color.primary : Color(.secondarySystemGroupedBackground), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyClosetView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack {
            Spacer(minLength: 0)

            VStack(spacing: 18) {
                Image(systemName: "hanger")
                    .font(.system(size: 82, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 132, height: 132)

                VStack(spacing: 6) {
                    Text("아직 등록된 옷이 없어요.")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("잘 맞는 옷을 먼저 추가해 주세요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                EmptyStateActionButton(title: "내 옷장에 추가", action: onAdd)
                    .padding(.top, 2)
            }
            .offset(y: -24)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}

private struct ClosetItemCard: View {
    let item: UserFit

    var body: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    ProductThumbnailView(
                        imageURLString: item.imageURLStringForDisplay,
                        category: item.category,
                        width: 72,
                        height: 88,
                        cornerRadius: 16
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(brandDisplayText)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text(item.productName)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .truncationMode(.tail)

                        Text("\(item.comparisonGroup?.displayName ?? "미지정") / \(item.sizeName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)
                }

                ClosetMeasurementGrid(item: item)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var brandDisplayText: String {
        let brand = item.brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayBrand = brand.isEmpty ? "브랜드 미상" : brand
        return isMusinsaItem ? "\(displayBrand) (무신사)" : displayBrand
    }

    private var isMusinsaItem: Bool {
        if item.sourcePlatformCode?.lowercased() == "musinsa"
            || item.sourceProduct?.sourcePlatformCode?.lowercased() == "musinsa" {
            return true
        }

        return item.sourceName.lowercased().contains("무신사")
            || item.sourceProduct?.sourceURLString?.lowercased().contains("musinsa") == true
    }

    // TODO: Legacy UI, 삭제 금지. body의 새 카드 대신 연결하면 기존 목록 카드로 즉시 원복할 수 있습니다.
    private var closetItemCardLegacy: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    ProductThumbnailView(
                        imageURLString: item.imageURLStringForDisplay,
                        category: item.category,
                        width: 72,
                        height: 88,
                        cornerRadius: 16
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.displayName)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)

                        if let sourceClassificationText {
                            Text(sourceClassificationText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Text(item.taxonomyDisplayMetadata)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        Text(item.fitPreference.rawValue)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.primary.opacity(0.08), in: Capsule())
                    }
                }

                MeasurementSummaryView(
                    measurements: item.measurements,
                    category: item.category,
                    detailCategory: item.detailCategory,
                    gender: item.gender
                )
            }
        }
    }

    private var sourceClassificationText: String? {
        guard item.sourceType != .manual else { return nil }

        let sourceName = item.sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let platformName = sourceName.isEmpty || sourceName == item.sourceType.displayName
            ? item.brandName.trimmingCharacters(in: .whitespacesAndNewlines)
            : sourceName
        guard !platformName.isEmpty else { return nil }

        let sourceCategoryPath = (item.sourceCategoryPath ?? item.sourceProduct?.sourceCategoryPath)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sourceCategoryPath, !sourceCategoryPath.isEmpty else {
            return platformName
        }

        return "\(platformName) (\(sourceCategoryPath))"
    }
}

private struct ClosetMeasurementGrid: View {
    let item: UserFit

    var body: some View {
        let snapshot = MeasurementResolver.snapshot(
            measurements: item.measurements,
            records: item.measurementRecords
        )
        let sourceRows = MeasurementResolver.sourceDisplayRows(
            records: item.measurementRecords
        )
        if sourceRows.isEmpty {
            let visibleKinds = orderedKinds.filter { snapshot.value(for: $0) != nil }
            let rows = stride(from: 0, to: visibleKinds.count, by: 2).map {
                Array(visibleKinds[$0..<min($0 + 2, visibleKinds.count)])
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        measurementCell(row[0], snapshot: snapshot)

                        if row.count > 1 {
                            measurementCell(row[1], snapshot: snapshot)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .gridCellUnsizedAxes(.vertical)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let rows = stride(from: 0, to: sourceRows.count, by: 2).map {
                Array(sourceRows[$0..<min($0 + 2, sourceRows.count)])
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        sourceMeasurementCell(row[0])
                        if row.count > 1 {
                            sourceMeasurementCell(row[1])
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .gridCellUnsizedAxes(.vertical)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var orderedKinds: [MeasurementKind] {
        switch item.category.serviceGroup {
        case .top:
            return [.totalLength, .shoulder, .chest, .sleeveLength]
        case .bottom:
            return [.totalLength, .waist, .hip, .thigh, .rise, .hem]
        case .outer:
            return [.totalLength, .shoulder, .chest, .sleeveLength, .hem]
        default:
            return item.category.measurementKinds(
                detailCategory: item.detailCategory,
                gender: item.gender
            )
        }
    }

    private func measurementCell(
        _ kind: MeasurementKind,
        snapshot: MeasurementResolver.GarmentSnapshot
    ) -> some View {
        HStack(spacing: 8) {
            Text(snapshot.title(for: kind))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            Text(snapshot.value(for: kind)?.cmText ?? "-")
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func sourceMeasurementCell(
        _ row: MeasurementResolver.SourceDisplayRow
    ) -> some View {
        HStack(spacing: 8) {
            Text(row.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            Text(row.valueText)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ClosetGridCard: View {
    let item: UserFit

    var body: some View {
        CardView(radius: 20, padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    ProductThumbnailView(
                        imageURLString: item.imageURLStringForDisplay,
                        category: item.category,
                        width: 126,
                        height: 142,
                        cornerRadius: 16
                    )
                    .frame(maxWidth: .infinity)

                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.brandName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(item.productName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(item.sizeName) · \(item.comparisonGroup?.displayName ?? "미지정")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
