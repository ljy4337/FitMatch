import SwiftUI
import SwiftData

struct MyClosetView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserFit.createdAt, order: .reverse) private var userFits: [UserFit]
    @State private var isShowingAddMethodSheet = false
    @State private var isShowingManualAddClosetItem = false
    @State private var isShowingLinkCompare = false
    @State private var pendingBasisItem: UserFit?
    @State private var existingBasisItem: UserFit?
    @State private var isShowingBasisChangeAlert = false
    @State private var searchText = ""
    @State private var selectedCategory: ClothingCategory?
    @State private var selectedBrand: String?
    @State private var sortOption: ClosetSortOption = .recent

    var body: some View {
        VStack(spacing: 0) {
            closetHeader

            if userFits.isEmpty {
                EmptyClosetView {
                    isShowingAddMethodSheet = true
                }
            } else {
                List {
                    ForEach(filteredItems) { item in
                        ClosetItemCard(item: item) {
                            toggleRepresentative(item)
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            basisSwipeButton(for: item)
                        }
                    }
                    .onDelete(perform: deleteItems)

                    Color.clear
                        .frame(height: 92)
                        .listRowSeparator(.hidden)
                        .listRowInsets(.init())

                    if filteredItems.isEmpty {
                        EmptyFilterResultView()
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 24, leading: 20, bottom: 24, trailing: 20))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBarOnScroll()
        .toolbar {
            if !userFits.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAddMethodSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("기준 옷 추가")
                }
            }
        }
        .sheet(isPresented: $isShowingAddMethodSheet) {
            AddClosetMethodSheet(
                onLink: {
                    isShowingAddMethodSheet = false
                    isShowingLinkCompare = true
                },
                onManual: {
                    isShowingAddMethodSheet = false
                    isShowingManualAddClosetItem = true
                }
            )
            .presentationDetents([.height(290)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingManualAddClosetItem) {
            NavigationStack {
                AddClosetItemView { item in
                    modelContext.insert(item)
                    try? modelContext.save()
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingLinkCompare) {
            NavigationStack {
                LinkClosetRegistrationView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                isShowingLinkCompare = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.headline.weight(.semibold))
                            }
                            .foregroundStyle(.primary)
                        }
                    }
            }
        }
        .alert(basisAlertTitle, isPresented: $isShowingBasisChangeAlert) {
            Button("취소", role: .cancel) {
                pendingBasisItem = nil
                existingBasisItem = nil
            }
            Button(existingBasisItem == nil ? "기준 옷으로 설정" : "변경") {
                applyPendingBasisChange()
            }
        } message: {
            Text(basisAlertMessage)
        }
    }

    private var closetHeader: some View {
        VStack(spacing: 14) {
            dashboard
            searchField
            categoryFilter
            brandAndSortRow
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
    }

    private var dashboard: some View {
        HStack(spacing: 10) {
            ClosetDashboardTile(title: "등록한 옷", value: "\(userFits.count)")
            ClosetDashboardTile(title: "기준 옷", value: "\(userFits.filter(\.isRepresentative).count)")
            ClosetDashboardTile(title: "브랜드", value: "\(Set(userFits.map(\.brandName)).count)")
            ClosetDashboardTile(title: "카테고리", value: "\(Set(userFits.map { $0.category.rawValue }).count)")
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("브랜드, 상품명 검색", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "전체", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }

                ForEach(availableCategories, id: \.self) { category in
                    FilterChip(title: category.rawValue, isSelected: selectedCategory == category) {
                        selectedCategory = category
                    }
                }
            }
        }
    }

    private var brandAndSortRow: some View {
        HStack(spacing: 10) {
            Menu {
                Button("전체") {
                    selectedBrand = nil
                }
                ForEach(availableBrands, id: \.self) { brand in
                    Button(brand) {
                        selectedBrand = brand
                    }
                }
            } label: {
                Label(selectedBrand ?? "브랜드 전체", systemImage: "tag")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Menu {
                ForEach(ClosetSortOption.allCases, id: \.self) { option in
                    Button(option.title) {
                        sortOption = option
                    }
                }
            } label: {
                Label(sortOption.title, systemImage: "arrow.up.arrow.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var filteredItems: [UserFit] {
        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = userFits.filter { item in
            let matchesSearch = normalizedSearchText.isEmpty
                || item.displayName.lowercased().contains(normalizedSearchText)
                || item.brandName.lowercased().contains(normalizedSearchText)

            let matchesCategory = selectedCategory == nil || item.category == selectedCategory
            let matchesBrand = selectedBrand == nil || item.brandName == selectedBrand

            return matchesSearch && matchesCategory && matchesBrand
        }

        switch sortOption {
        case .recent:
            return filtered.sorted { $0.createdAt > $1.createdAt }
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

    private var availableCategories: [ClothingCategory] {
        Array(Set(userFits.map(\.category))).sorted { $0.rawValue < $1.rawValue }
    }

    private var availableBrands: [String] {
        Array(Set(userFits.map(\.brandName))).sorted()
    }

    @ViewBuilder
    private func basisSwipeButton(for item: UserFit) -> some View {
        Button {
            toggleRepresentative(item)
        } label: {
            Label(
                item.isRepresentative ? "기준 옷 해제" : "기준 옷으로 설정",
                systemImage: item.isRepresentative ? "heart.slash" : "heart.fill"
            )
        }
        .tint(item.isRepresentative ? .gray : .red)
    }

    private func toggleRepresentative(_ item: UserFit) {
        if item.isRepresentative {
            item.isRepresentative = false
            item.updatedAt = Date()
            try? modelContext.save()
            return
        }

        pendingBasisItem = item
        existingBasisItem = userFits.first {
            $0.id != item.id
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
        try? modelContext.save()

        self.pendingBasisItem = nil
        existingBasisItem = nil
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let item = filteredItems[index]
            modelContext.delete(item)
        }
        try? modelContext.save()
    }
}

private enum ClosetSortOption: CaseIterable {
    case recent
    case brand
    case category
    case basisFirst

    var title: String {
        switch self {
        case .recent: return "최근 등록"
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
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            Image("EmptyCloset")
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 160)

            VStack(spacing: 6) {
                Text("옷장이 비었습니다.")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Text("핏이 마음에 드는 옷을 먼저 추가해 주세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onAdd) {
                Label("추가하기", systemImage: "plus")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(width: 160, height: 50)
                    .background(Color.primary, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)

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
                    if let imageURLString = item.sourceProduct?.imageURLString,
                       !imageURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ProductThumbnailView(
                            imageURLString: imageURLString,
                            width: 72,
                            height: 88,
                            cornerRadius: 16
                        )
                    }

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

                    VStack(alignment: .trailing, spacing: 4) {
                        Button(action: onToggleRepresentative) {
                            Label(
                                item.isRepresentative ? "기준 옷" : "기준 옷 설정",
                                systemImage: item.isRepresentative ? "heart.fill" : "heart"
                            )
                            .font(.caption.weight(.bold))
                            .foregroundStyle(item.isRepresentative ? .red : .primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.primary.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)

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

                NavigationLink {
                    ClosetItemDetailView(item: item)
                } label: {
                    Text("상세 보기")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
