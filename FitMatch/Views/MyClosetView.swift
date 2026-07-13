import SwiftUI
import SwiftData

struct MyClosetView: View {
    var onLogout: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserFit.createdAt, order: .reverse) private var userFits: [UserFit]
    @Query(sort: \RecommendationHistory.createdAt, order: .reverse) private var histories: [RecommendationHistory]
    @AppStorage("FitMatch.hideBasisPrompt") private var hidesBasisPrompt = false
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

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                if isTopChromeVisible {
                    FitMatchNavigationHeader(onLogout: onLogout)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                closetHeader

                if userFits.isEmpty {
                    EmptyClosetView {
                        presentActiveSheet(.addMethod)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    closetContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !userFits.isEmpty {
                closetFloatingAddButton
                    .padding(.trailing, 22)
                    .padding(.bottom, 92)
            }
        }
        .background(Color(.systemBackground))
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isTopChromeVisible)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
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
            case .linkRegistration:
                NavigationStack {
                    LinkClosetRegistrationView()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $isShowingBasisChangeAlert) {
            BasisChangeSheet(
                title: basisAlertTitle,
                message: basisAlertMessage,
                hidesFuturePrompt: $hidesBasisPrompt,
                onCancel: {
                    pendingBasisItem = nil
                    existingBasisItem = nil
                    isShowingBasisChangeAlert = false
                },
                onConfirm: {
                    isShowingBasisChangeAlert = false
                    applyPendingBasisChange()
                }
            )
            .presentationDetents([.height(existingBasisItem == nil ? 300 : 380)])
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
    }

    private var closetHeader: some View {
        ContentFilterBar(filters: closetFilterItems, layout: closetLayoutBinding)
    }

    private var closetFloatingAddButton: some View {
        Button {
            presentActiveSheet(.addMethod)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(.black, in: Circle())
                .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("기준 옷 추가")
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
            ForEach(filteredItems) { item in
                NavigationLink {
                    ClosetItemDetailView(item: item)
                } label: {
                    ClosetItemCard(item: item) {
                        toggleRepresentative(item)
                    }
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    basisSwipeButton(for: item)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    deleteSwipeButton(for: item)
                }
            }

            if filteredItems.isEmpty {
                EmptyFilterResultView()
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 24, leading: 20, bottom: 24, trailing: 20))
            }

            Color.clear
                .frame(height: 112)
                .listRowSeparator(.hidden)
                .listRowInsets(.init())
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .hidesBottomTabBarOnScroll(tab: .my)
        .hidesTopChromeOnScroll($isTopChromeVisible)
    }

    private var closetGrid: some View {
        ScrollView {
            VStack(spacing: 0) {
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(filteredItems) { item in
                        NavigationLink {
                            ClosetItemDetailView(item: item)
                        } label: {
                            ClosetGridCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }

                    if filteredItems.isEmpty {
                        EmptyFilterResultView()
                            .gridCellColumns(2)
                            .padding(.top, 24)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 122)
            }
        }
        .hidesBottomTabBarOnScroll(tab: .my)
        .hidesTopChromeOnScroll($isTopChromeVisible)
    }

    private var filteredItems: [UserFit] {
        let filtered = userFits.filter { item in
            let matchesCategory = selectedCategory == nil || item.category == selectedCategory
            let matchesBrand = selectedBrand == nil || item.brandName == selectedBrand

            return matchesCategory && matchesBrand
        }

        switch sortOption {
        case .recent:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return filtered.sorted { $0.createdAt < $1.createdAt }
        case .brand:
            return filtered.sorted { $0.brandName < $1.brandName }
        case .category:
            return filtered.sorted { $0.category.rawValue < $1.category.rawValue }
        case .basisFirst:
            return filtered.sorted {
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
            } catch {
                saveErrorMessage = "기준 옷 설정을 저장하지 못했습니다."
            }
            return
        }

        pendingBasisItem = item
        existingBasisItem = userFits.first {
            $0.id != item.id
                && $0.detailCategory == item.detailCategory
                && $0.isRepresentative
        }
        if hidesBasisPrompt {
            applyPendingBasisChange()
        } else {
            isShowingBasisChangeAlert = true
        }
    }

    private var basisAlertTitle: String {
        guard let pendingBasisItem else {
            return "기준 옷 설정"
        }

        if existingBasisItem == nil {
            return "이 옷을 기준 옷으로 설정할까요?"
        }

        return "\(pendingBasisItem.detailCategory.rawValue) 기준 옷은 1개만 설정할 수 있습니다."
    }

    private var basisAlertMessage: String {
        guard let pendingBasisItem else {
            return ""
        }

        if let existingBasisItem {
            return """
            현재 기준 옷:
            \(existingBasisItem.displayName)

            새 기준 옷:
            \(pendingBasisItem.displayName)

            기존 기준 옷이 해제되고 새 기준 옷으로 변경됩니다.
            """
        }

        return """
        기준 옷은 같은 카테고리 상품을 비교할 때 자동으로 우선 비교됩니다.

        언제든 다른 옷으로 변경할 수 있습니다.
        """
    }

    private func applyPendingBasisChange() {
        guard let pendingBasisItem else {
            return
        }

        userFits
            .filter {
                $0.id != pendingBasisItem.id
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
            return
        }

        self.pendingBasisItem = nil
        existingBasisItem = nil
    }

    private func deleteItem(_ item: UserFit) {
        deleteHistoriesReferencing(item)
        modelContext.delete(item)
        do {
            try modelContext.save()
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

private struct BasisChangeSheet: View {
    let title: String
    let message: String
    @Binding var hidesFuturePrompt: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title3.weight(.black))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                hidesFuturePrompt.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: hidesFuturePrompt ? "checkmark.square.fill" : "square")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("앞으로 표시하지 않기")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text("취소")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onConfirm) {
                    Text("설정")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(.systemBackground))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.primary, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(Color(.systemGroupedBackground))
    }
}

private struct AddClosetMethodSheet: View {
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
