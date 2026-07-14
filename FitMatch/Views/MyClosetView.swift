import SwiftUI
import SwiftData

struct MyClosetView: View {
    var onLogout: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserFit.createdAt, order: .reverse) private var userFits: [UserFit]
    @Query(sort: \RecommendationHistory.createdAt, order: .reverse) private var histories: [RecommendationHistory]
    @AppStorage("FitMatch.closetViewLayout") private var closetViewLayoutRaw = ContentListLayout.list.rawValue
    @State private var activeSheet: ClosetActiveSheet?
    @State private var pendingBasisItem: UserFit?
    @State private var existingBasisItem: UserFit?
    @State private var isShowingBasisChangeAlert = false
    @State private var selectedCategory: ClothingCategory?
    @State private var selectedBrand: String?
    @State private var sortOption: ClosetSortOption = .recent
    @State private var saveErrorMessage: String?
    @State private var isTopChromeVisible = true
    @State private var selectedClosetItemID: UUID?
    @State private var displayedItems: [UserFit] = []

    var body: some View {
        VStack(spacing: 0) {
            closetTopChrome
            closetContent
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
                        modelContext.insert(item)
                        do {
                            try modelContext.save()
                        } catch {
                            saveErrorMessage = "내 옷장에 저장하지 못했습니다. 다시 시도해 주세요."
                        }
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
        .alert(basisAlertTitle, isPresented: $isShowingBasisChangeAlert) {
            Button("취소", role: .cancel) {
                clearPendingBasisChange()
            }

            Button(existingBasisItem == nil ? "설정" : "변경") {
                isShowingBasisChangeAlert = false
                applyPendingBasisChange()
            }
        } message: {
            Text(basisAlertMessage)
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
            rebuildDisplayedItems()
        }
        .onChange(of: selectedCategory) { _, _ in
            rebuildDisplayedItems()
        }
        .onChange(of: selectedBrand) { _, _ in
            rebuildDisplayedItems()
        }
        .onChange(of: sortOption) { _, _ in
            rebuildDisplayedItems()
        }
        .onChange(of: userFits.count) { _, _ in
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
                    ForEach(displayedItems) { item in
                        Button {
                            selectedClosetItemID = item.id
                        } label: {
                            ClosetItemCard(item: item) {
                                toggleRepresentative(item)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .contextMenu {
                            Button {
                                toggleRepresentative(item)
                            } label: {
                                Label(
                                    item.isRepresentative ? "기준 옷 해제" : "기준 옷으로 설정",
                                    systemImage: item.isRepresentative ? "tshirt" : "tshirt.fill"
                                )
                            }

                            Button(role: .destructive) {
                                deleteItem(item)
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                    }

                    if displayedItems.isEmpty {
                        EmptyFilterResultView()
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                    }
                }
            }
        }
        .contentMargins(.bottom, FitMatchScrollContentMetrics.bottomClearance, for: .scrollContent)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isTopChromeVisible)
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
        .contentMargins(.bottom, FitMatchScrollContentMetrics.bottomClearance, for: .scrollContent)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isTopChromeVisible)
        .hidesBottomTabBarOnScroll(tab: .my, topChrome: $isTopChromeVisible)
    }

    private var selectedClosetItemForDetail: UserFit? {
        guard let selectedClosetItemID else {
            return nil
        }

        return userFits.first { $0.id == selectedClosetItemID }
    }

    private func rebuildDisplayedItems() {
        let filtered = userFits.filter { item in
            let matchesCategory = selectedCategory == nil || item.category == selectedCategory
            let matchesBrand = selectedBrand == nil || item.brandName == selectedBrand

            return matchesCategory && matchesBrand
        }

        switch sortOption {
        case .recent:
            displayedItems = filtered.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            displayedItems = filtered.sorted { $0.createdAt < $1.createdAt }
        case .brand:
            displayedItems = filtered.sorted { $0.brandName < $1.brandName }
        case .category:
            displayedItems = filtered.sorted { $0.category.rawValue < $1.category.rawValue }
        case .basisFirst:
            displayedItems = filtered.sorted {
                if $0.isRepresentative != $1.isRepresentative {
                    return $0.isRepresentative && !$1.isRepresentative
                }
                return $0.createdAt > $1.createdAt
            }
        }
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
                id: "category",
                selectedID: selectedCategory?.rawValue ?? "all",
                selectedTitle: selectedCategory?.rawValue ?? "전체",
                options: [ContentFilterOption(id: "all", title: "전체")]
                    + availableCategories.map { ContentFilterOption(id: $0.rawValue, title: $0.rawValue) },
                onSelect: { id in
                    selectedCategory = id == "all" ? nil : ClothingCategory(rawValue: id)
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
                options: ClosetSortOption.allCases.map { ContentFilterOption(id: $0.rawValue, title: $0.title) },
                onSelect: { id in
                    sortOption = ClosetSortOption(rawValue: id) ?? .recent
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

    private var availableCategories: [ClothingCategory] {
        Array(Set(userFits.map(\.category))).sorted { $0.rawValue < $1.rawValue }
    }

    private var availableBrands: [String] {
        Array(Set(userFits.map(\.brandName))).sorted()
    }

    private func presentActiveSheet(_ sheet: ClosetActiveSheet) {
        print("[MyClosetView] activeSheet -> \(sheet.logName)")
        activeSheet = nil
        DispatchQueue.main.async {
            activeSheet = sheet
        }
    }

    private func dismissActiveSheet() {
        print("[MyClosetView] activeSheet -> nil")
        activeSheet = nil
    }

    @ViewBuilder
    private func basisSwipeButton(for item: UserFit) -> some View {
        Button {
            toggleRepresentative(item)
        } label: {
            Label(
                item.isRepresentative ? "기준 옷 해제" : "기준 옷으로 설정",
                systemImage: item.isRepresentative ? "tshirt" : "tshirt.fill"
            )
        }
        .tint(item.isRepresentative ? .gray : .black)
    }

    private func toggleRepresentative(_ item: UserFit) {
        if item.isRepresentative {
            item.isRepresentative = false
            item.updatedAt = Date()
            do {
                try modelContext.save()
                rebuildDisplayedItems()
            } catch {
                saveErrorMessage = "기준 옷 설정을 저장하지 못했습니다."
            }
            return
        }

        pendingBasisItem = item
        existingBasisItem = userFits.first {
            $0.id != item.id
                && $0.category == item.category
                && $0.detailCategory == item.detailCategory
                && $0.isRepresentative
        }
        isShowingBasisChangeAlert = true
    }

    private var basisAlertTitle: String {
        guard let pendingBasisItem else {
            return "기준 옷 설정"
        }

        if existingBasisItem == nil {
            return "이 옷을 기준 옷으로 설정할까요?"
        }

        return "\(pendingBasisItem.detailCategory.rawValue) 기준 옷을 변경할까요?"
    }

    private var basisAlertMessage: String {
        guard let pendingBasisItem else {
            return ""
        }

        if let existingBasisItem {
            return """
            현재 기준 옷
            \(existingBasisItem.displayName)

            새 기준 옷
            \(pendingBasisItem.displayName)

            기준 옷은 같은 종류별로 1개만 설정할 수 있습니다.
            변경하면 기존 기준 옷은 자동으로 해제됩니다.
            """
        }

        return """
        기준 옷은 같은 종류의 상품을 비교할 때 가장 먼저 사용됩니다.
        기준 옷은 종류별로 1개만 설정할 수 있으며 언제든 변경할 수 있습니다.
        """
    }

    private func applyPendingBasisChange() {
        guard let pendingBasisItem else {
            return
        }

        userFits
            .filter {
                $0.id != pendingBasisItem.id
                    && $0.category == pendingBasisItem.category
                    && $0.detailCategory == pendingBasisItem.detailCategory
                    && $0.isRepresentative
            }
            .forEach {
                $0.isRepresentative = false
                $0.updatedAt = Date()
            }

        pendingBasisItem.isRepresentative = true
        pendingBasisItem.updatedAt = Date()
        do {
            try modelContext.save()
        } catch {
            saveErrorMessage = "기준 옷 설정을 저장하지 못했습니다."
            clearPendingBasisChange()
            return
        }

        rebuildDisplayedItems()
        clearPendingBasisChange()
    }

    private func clearPendingBasisChange() {
        pendingBasisItem = nil
        existingBasisItem = nil
        isShowingBasisChangeAlert = false
    }

    private func deleteItem(_ item: UserFit) {
        deleteHistoriesReferencing(item)
        modelContext.delete(item)
        do {
            try modelContext.save()
            rebuildDisplayedItems()
        } catch {
            saveErrorMessage = "옷장 항목을 삭제하지 못했습니다."
        }
    }

    @ViewBuilder
    private func deleteSwipeButton(for item: UserFit) -> some View {
        Button(role: .destructive) {
            deleteItem(item)
        } label: {
            Label("삭제", systemImage: "trash")
        }
        .tint(.red)
    }

    private func deleteHistoriesReferencing(_ item: UserFit) {
        histories
            .filter { history in
                history.userFit.id == item.id
            }
            .forEach { history in
                modelContext.delete(history)
            }
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

private enum ClosetSortOption: String, CaseIterable {
    case recent
    case oldest
    case brand
    case category
    case basisFirst

    var title: String {
        switch self {
        case .recent: return "최근 등록"
        case .oldest: return "오래된순"
        case .brand: return "브랜드순"
        case .category: return "카테고리순"
        case .basisFirst: return "기준 옷 우선"
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
            "조건에 맞는 옷이 없습니다.",
            systemImage: "line.3.horizontal.decrease.circle",
            description: Text("검색어 또는 필터를 조정해 주세요.")
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
                Text("상품 링크로 불러오거나 직접 입력할 수 있습니다.")
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
                Image("EmptyCloset")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 132, height: 132)

                VStack(spacing: 6) {
                    Text("옷장이 비었습니다.")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("핏이 마음에 드는 옷을 먼저 추가해 주세요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                EmptyStateActionButton(title: "추가하기", action: onAdd)
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
    let onToggleRepresentative: () -> Void

    var body: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    ProductThumbnailView(
                        imageURLString: item.sourceProduct?.imageURLString,
                        category: item.category,
                        width: 72,
                        height: 88,
                        cornerRadius: 16
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.displayName)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("출처: \(item.sourceName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("\(item.gender.rawValue) / \(item.category.rawValue) / \(item.detailCategory.rawValue) / \(item.sizeName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        Button(action: onToggleRepresentative) {
                            Image(systemName: item.isRepresentative ? "tshirt.fill" : "tshirt")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(item.isRepresentative ? Color(.systemBackground) : .primary)
                                .frame(width: 34, height: 34)
                                .background(
                                    item.isRepresentative ? Color.primary : Color(.secondarySystemGroupedBackground),
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.isRepresentative ? "기준 옷" : "기준 옷으로 설정")

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
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ClosetGridCard: View {
    let item: UserFit

    var body: some View {
        CardView(radius: 20, padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    ProductThumbnailView(
                        imageURLString: item.sourceProduct?.imageURLString,
                        category: item.category,
                        width: 126,
                        height: 142,
                        cornerRadius: 16
                    )
                    .frame(maxWidth: .infinity)

                    if item.isRepresentative {
                        Text("기준")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(Color(.systemBackground))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.primary, in: Capsule())
                            .padding(8)
                    }
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

                    Text("\(item.sizeName) · \(item.detailCategory.rawValue)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
