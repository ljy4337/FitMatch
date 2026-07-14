import SwiftUI
import SwiftData

struct RecommendationHistoryView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecommendationHistory.createdAt, order: .reverse) private var histories: [RecommendationHistory]
    @AppStorage("FitMatch.historyViewLayout") private var historyViewLayoutRaw = ContentListLayout.list.rawValue
    @State private var sortOption: HistorySortOption = .latest
    @State private var selectedScope: HistoryScope = .all
    @State private var selectedCategory: ClothingCategory?
    @State private var favoriteURLs = FavoriteProductStore().favoriteURLs()
    @State private var selectedHistoryForCloset: RecommendationHistory?
    @State private var selectedHistoryIDForDetail: UUID?
    @State private var opensReferencePickerOnDetail = false
    @State private var isShowingClosetSavedAlert = false
    @State private var saveErrorMessage: String?
    @State private var isTopChromeVisible = true
    private let favoriteStore = FavoriteProductStore()
    var onRecompare: ((String) -> Void)?
    var onStartCompare: (() -> Void)?
    var onLogout: (() -> Void)?

    init(onRecompare: ((String) -> Void)? = nil, onStartCompare: (() -> Void)? = nil, onLogout: (() -> Void)? = nil) {
        self.onRecompare = onRecompare
        self.onStartCompare = onStartCompare
        self.onLogout = onLogout
    }

    var body: some View {
        VStack(spacing: 0) {
            if isTopChromeVisible {
                FitMatchNavigationHeader(onLogout: onLogout)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            historyControls

            if filteredHistories.isEmpty {
                EmptyRecommendationHistoryView(onStartCompare: histories.isEmpty ? onStartCompare : nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                historyContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: Binding(
            get: { selectedHistoryForDetail != nil },
            set: { if !$0 { selectedHistoryIDForDetail = nil } }
        )) {
            if let selectedHistoryForDetail {
                RecommendationResultView(
                    result: selectedHistoryForDetail,
                    opensReferencePickerOnAppear: opensReferencePickerOnDetail
                )
            }
        }
        .sheet(item: $selectedHistoryForCloset) { history in
            AddComparedProductToClosetSheet(
                product: history.product,
                productDetailCategory: history.productDetailCategory,
                recommendedSize: history.recommendedSize
            ) { _ in
                isShowingClosetSavedAlert = true
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("내 옷장에 추가했어요.", isPresented: $isShowingClosetSavedAlert) {
            Button("확인", role: .cancel) {}
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

    private var historyControls: some View {
        ContentFilterBar(filters: historyFilterItems, layout: historyLayoutBinding)
    }

    @ViewBuilder
    private var historyContent: some View {
        switch historyLayout {
        case .list:
            historyList
        case .grid:
            historyGrid
        }
    }

    private var historyList: some View {
        List {
            ForEach(filteredHistories) { history in
                HistoryCard(
                    history: history,
                    isFavorite: isFavorite(history)
                ) {
                    toggleFavorite(history)
                } onOpen: {
                    openShoppingMall(history)
                } onRecompare: {
                    opensReferencePickerOnDetail = true
                    selectedHistoryIDForDetail = history.id
                } onAddToCloset: {
                    selectedHistoryForCloset = history
                } onShowDetail: {
                    opensReferencePickerOnDetail = false
                    selectedHistoryIDForDetail = history.id
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    favoriteSwipeButton(for: history)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    deleteSwipeButton(for: history)
                }
            }

        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, FitMatchScrollContentMetrics.bottomClearance, for: .scrollContent)
        .hidesBottomTabBarOnScroll(tab: .history, topChrome: $isTopChromeVisible)
    }

    private var historyGrid: some View {
        ScrollView {
            VStack(spacing: 0) {
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(filteredHistories) { history in
                        HistoryGridCard(
                            history: history,
                            isFavorite: isFavorite(history),
                            onToggleFavorite: {
                                toggleFavorite(history)
                            },
                            onShowDetail: {
                                opensReferencePickerOnDetail = false
                                selectedHistoryIDForDetail = history.id
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .contentMargins(.bottom, FitMatchScrollContentMetrics.bottomClearance, for: .scrollContent)
        .hidesBottomTabBarOnScroll(tab: .history, topChrome: $isTopChromeVisible)
    }

    private var historyLayout: ContentListLayout {
        get { ContentListLayout(rawValue: historyViewLayoutRaw) ?? .list }
        nonmutating set { historyViewLayoutRaw = newValue.rawValue }
    }

    private var historyLayoutBinding: Binding<ContentListLayout> {
        Binding(
            get: { historyLayout },
            set: { historyLayout = $0 }
        )
    }

    private var historyFilterItems: [ContentFilterItem] {
        [
            ContentFilterItem(
                id: "scope",
                selectedID: selectedScope.rawValue,
                selectedTitle: selectedScope.title,
                options: HistoryScope.allCases.map { ContentFilterOption(id: $0.rawValue, title: $0.title) },
                onSelect: { id in
                    selectedScope = HistoryScope(rawValue: id) ?? .all
                }
            ),
            ContentFilterItem(
                id: "category",
                selectedID: selectedCategory?.rawValue ?? "all",
                selectedTitle: selectedCategory?.rawValue ?? "전체 카테고리",
                options: [ContentFilterOption(id: "all", title: "전체 카테고리")]
                    + availableCategories.map { ContentFilterOption(id: $0.rawValue, title: $0.rawValue) },
                onSelect: { id in
                    selectedCategory = id == "all" ? nil : ClothingCategory(rawValue: id)
                }
            ),
            ContentFilterItem(
                id: "sort",
                selectedID: sortOption.rawValue,
                selectedTitle: sortOption.title,
                options: HistorySortOption.allCases.map { ContentFilterOption(id: $0.rawValue, title: $0.title) },
                onSelect: { id in
                    sortOption = HistorySortOption(rawValue: id) ?? .latest
                }
            )
        ]
    }

    private var availableCategories: [ClothingCategory] {
        Array(Set(histories.map { $0.product.category })).sorted { $0.rawValue < $1.rawValue }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private var selectedHistoryForDetail: RecommendationHistory? {
        guard let selectedHistoryIDForDetail else {
            return nil
        }

        return histories.first { $0.id == selectedHistoryIDForDetail }
    }

    private func openShoppingMall(_ history: RecommendationHistory) {
        guard let urlString = history.product.sourceURLString,
              let url = URL(string: urlString) else {
            return
        }
        openURL(url)
    }

    private func recompare(_ history: RecommendationHistory) {
        guard let urlString = history.product.sourceURLString else {
            return
        }
        onRecompare?(urlString)
    }

    private func deleteHistory(_ history: RecommendationHistory) {
        modelContext.delete(history)
        do {
            try modelContext.save()
        } catch {
            saveErrorMessage = "비교 기록을 삭제하지 못했습니다."
        }
    }

    private var filteredHistories: [RecommendationHistory] {
        let scoped = histories.filter { history in
            let matchesCategory = selectedCategory == nil || history.product.category == selectedCategory
            guard matchesCategory else {
                return false
            }

            switch selectedScope {
            case .all:
                return true
            case .favorite:
                return isFavorite(history)
            }
        }

        switch sortOption {
        case .latest:
            return scoped.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return scoped.sorted { $0.createdAt < $1.createdAt }
        case .brand:
            return scoped.sorted { ($0.product.brand?.name ?? "") < ($1.product.brand?.name ?? "") }
        case .fitConfidence:
            return scoped.sorted { $0.recommendationScore > $1.recommendationScore }
        }
    }

    private func isFavorite(_ history: RecommendationHistory) -> Bool {
        guard let urlString = history.product.sourceURLString else {
            return false
        }

        return favoriteURLs.contains(urlString)
    }

    private func toggleFavorite(_ history: RecommendationHistory) {
        _ = favoriteStore.toggle(history.product.sourceURLString)
        favoriteURLs = favoriteStore.favoriteURLs()
    }

    @ViewBuilder
    private func favoriteSwipeButton(for history: RecommendationHistory) -> some View {
        Button {
            toggleFavorite(history)
        } label: {
            Label(
                isFavorite(history) ? "관심 해제" : "관심 등록",
                systemImage: isFavorite(history) ? "heart.slash" : "heart.fill"
            )
        }
        .tint(isFavorite(history) ? .gray : .black)
    }

    @ViewBuilder
    private func deleteSwipeButton(for history: RecommendationHistory) -> some View {
        Button(role: .destructive) {
            deleteHistory(history)
        } label: {
            Label("삭제", systemImage: "trash")
        }
        .tint(.red)
    }
}

private enum HistorySortOption: String, CaseIterable {
    case latest
    case oldest
    case brand
    case fitConfidence

    var title: String {
        switch self {
        case .latest: return "최신순"
        case .oldest: return "오래된순"
        case .brand: return "브랜드순"
        case .fitConfidence: return "핏 매칭률 높은순"
        }
    }
}

private enum HistoryScope: String, CaseIterable {
    case all
    case favorite

    var title: String {
        switch self {
        case .all: return "전체 기록"
        case .favorite: return "관심상품"
        }
    }
}

private struct EmptyRecommendationHistoryView: View {
    let onStartCompare: (() -> Void)?

    var body: some View {
        VStack {
            Spacer(minLength: 0)

            VStack(spacing: 18) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 132, height: 132)

                VStack(spacing: 6) {
                    Text("상품 비교 기록이 없습니다.")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("상품을 비교하면 비교 결과가 여기에 쌓입니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let onStartCompare {
                    EmptyStateActionButton(title: "비교 시작", action: onStartCompare)
                        .padding(.top, 2)
                }
            }
            .offset(y: -24)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}

private struct HistoryCard: View {
    let history: RecommendationHistory
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onOpen: () -> Void
    let onRecompare: () -> Void
    let onAddToCloset: () -> Void
    let onShowDetail: () -> Void
    @State private var isPressed = false

    var body: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .topTrailing) {
                    HStack(alignment: .top, spacing: 14) {
                        ProductThumbnailView(
                            imageURLString: history.product.imageURLString,
                            category: history.product.category,
                            width: 88,
                            height: 112,
                            cornerRadius: 16
                        )

                            VStack(alignment: .leading, spacing: 6) {
                            Text(history.product.brand?.name ?? history.product.sourceDisplayName)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)

                            Text(history.product.name)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)

                            Text("출처: \(history.product.sourceDisplayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            ProductPriceView(product: history.product)

                            Text("\(history.product.category.rawValue) / \(history.productDetailCategory.rawValue)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text(history.createdAt, style: .date)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.primary.opacity(0.08), in: Capsule())
                        }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.trailing, 58)
                    }

                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(isFavorite ? .red : .primary)
                            .frame(width: 36, height: 36)
                            .background(Color(.systemBackground).opacity(0.92), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("추천 사이즈")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(history.recommendedSize.name.displaySizeName)
                            .font(.title2.weight(.black))
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("핏 매칭률")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text("\(history.recommendationScore)%")
                            .font(.title2.weight(.black))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                    }
                }
                .padding(14)
                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text(measurementSummaryText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onTapGesture(perform: onShowDetail)
            .background(
                Color.primary.opacity(isPressed ? 0.035 : 0),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .scaleEffect(isPressed ? 0.992 : 1)
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .onLongPressGesture(
                minimumDuration: .infinity,
                maximumDistance: 16,
                pressing: { isPressing in
                    isPressed = isPressing
                },
                perform: {}
            )
        }
    }

    private var measurementSummaryText: String {
        let kinds = history.product.category
            .measurementKinds(detailCategory: history.productDetailCategory, gender: .unisex)
            .filter {
                history.recommendedSize.measurements.value(for: $0) > 0
                    && history.userFit.measurements.value(for: $0) > 0
            }

        return kinds.isEmpty ? "실측 부족" : "실측 \(kinds.count)개 비교"
    }
}

private struct HistoryGridCard: View {
    let history: RecommendationHistory
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onShowDetail: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onShowDetail) {
                CardView(radius: 20, padding: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        ProductThumbnailView(
                            imageURLString: history.product.imageURLString,
                            category: history.product.category,
                            width: 126,
                            height: 142,
                            cornerRadius: 16
                        )
                        .frame(maxWidth: .infinity)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(history.product.brand?.name ?? history.product.sourceDisplayName)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Text(history.product.name)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("추천 \(history.recommendedSize.name.displaySizeName)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text("핏 매칭률 \(history.recommendationScore)%")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isFavorite ? .red : .primary)
                    .frame(width: 34, height: 34)
                    .background(Color(.systemBackground).opacity(0.92), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
        }
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
