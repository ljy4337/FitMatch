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
        ZStack(alignment: .top) {
            historyContent
            historyTopChrome
                .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: Binding(
            get: { selectedHistoryIDForDetail != nil },
            set: { if !$0 { selectedHistoryIDForDetail = nil } }
        )) {
            if let selectedHistoryForDetail {
                RecommendationResultView(
                    result: selectedHistoryForDetail,
                    opensReferencePickerOnAppear: opensReferencePickerOnDetail
                ) { updatedHistory in
                    opensReferencePickerOnDetail = false
                    selectedHistoryIDForDetail = updatedHistory.id
                }
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
    private var historyTopChrome: some View {
        CollapsibleTopChrome(isVisible: isTopChromeVisible) {
            FitMatchNavigationHeader(onLogout: onLogout)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)
                .background(Color(.systemBackground))
        }
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
            historyControls
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())

            if filteredHistories.isEmpty {
                EmptyRecommendationHistoryView(onStartCompare: histories.isEmpty ? onStartCompare : nil)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 36, leading: 20, bottom: 24, trailing: 20))
            } else {
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
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, FitMatchTopChromeMetrics.height, for: .scrollContent)
        .contentMargins(.bottom, FitMatchScrollContentMetrics.bottomClearance, for: .scrollContent)
        .hidesBottomTabBarOnScroll(tab: .history, topChrome: $isTopChromeVisible)
    }

    private var historyGrid: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                historyControls

                if filteredHistories.isEmpty {
                    EmptyRecommendationHistoryView(onStartCompare: histories.isEmpty ? onStartCompare : nil)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.top, 36)
                } else {
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
        }
        .contentMargins(.top, FitMatchTopChromeMetrics.height, for: .scrollContent)
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
            currentCardContent
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

    private var currentCardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                HStack(alignment: .top, spacing: 14) {
                    ProductThumbnailView(
                        imageURLString: history.productImageURLStringForDisplay,
                        category: history.product.category,
                        width: 104,
                        height: 112,
                        cornerRadius: 16
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(historyBrandText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text(history.productNameForDisplay)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(historySourceCategoryText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        Text(relativeDateText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(.primary.opacity(0.07), in: Capsule())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 38)
                }

                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isFavorite ? .red : .primary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorite ? "관심 해제" : "관심 등록")
            }

            GeometryReader { geometry in
                let dividerWidth: CGFloat = 1
                let columnWidth = (geometry.size.width - (dividerWidth * 2)) / 3

                HStack(alignment: .top, spacing: 0) {
                    RecommendationMetricColumn(
                        title: "추천 사이즈",
                        value: history.recommendedSize.name.displaySizeName,
                        detail: nil,
                        isPrimary: true,
                        style: .historyCompact
                    )
                        .frame(width: columnWidth)
                    Divider().frame(width: dividerWidth, height: 88)
                    RecommendationMetricColumn(
                        title: "핏 매칭률",
                        value: "\(history.recommendationScore)%",
                        detail: fitMatchBadge,
                        isPrimary: false,
                        style: .historyCompact
                    )
                        .frame(width: columnWidth)
                    Divider().frame(width: dividerWidth, height: 88)
                    reliabilityMetric
                        .frame(width: columnWidth)
                }
            }
            .frame(height: 100)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 8) {
                Image(systemName: "ruler")
                    .rotationEffect(.degrees(-38))
                Text(measurementSummaryText)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(formattedHistoryDate)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.72))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func historyMetric(title: String, value: String, badge: String? = nil) -> some View {
        RecommendationMetricColumn(
            title: title,
            value: value,
            detail: badge ?? " ",
            isPrimary: title == "추천 사이즈",
            style: .historyCompact
        )
    }

    private var reliabilityMetric: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("신뢰도")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
            Text(reliabilityStars)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.orange.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(reliabilityTitle)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
            Text(measurementSummaryText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary.opacity(0.8))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
    }

    // TODO: Legacy UI, 삭제 금지. currentCardContent 대신 연결하면 기존 목록 카드로 즉시 원복할 수 있습니다.
    private var historyCardLegacy: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ProductThumbnailView(
                    imageURLString: history.productImageURLStringForDisplay,
                    category: history.product.category,
                    width: 88,
                    height: 112,
                    cornerRadius: 16
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text(history.productBrandNameForDisplay)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(history.productNameForDisplay)
                        .font(.headline.weight(.bold))
                        .lineLimit(2)
                    Text("출처: \(history.productSourceNameForDisplay)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(historySourceCategoryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                historyMetric(title: "추천 사이즈", value: history.recommendedSize.name.displaySizeName)
                historyMetric(title: "핏 매칭률", value: "\(history.recommendationScore)%")
            }
            .padding(14)
            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(measurementSummaryText)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }

    private var measurementSummaryText: String {
        comparedMeasurementKinds.isEmpty ? "실측 부족" : "실측 \(comparedMeasurementKinds.count)개 항목 비교"
    }

    private var comparedMeasurementKinds: [MeasurementKind] {
        if history.comparisonSchemaVersion >= 1 {
            return history.comparedMeasurementUsages.map(\.kind)
        }

        return history.product.category
            .measurementKinds(detailCategory: history.productDetailCategory, gender: .unisex)
            .filter {
                history.recommendedSize.measurements.value(for: $0) > 0
                    && history.userFit.measurements.value(for: $0) > 0
            }
    }

    private var fitMatchBadge: String {
        switch history.recommendationScore {
        case 90...: return "매우 잘 맞아요"
        case 80..<90: return "잘 맞아요"
        case 70..<80: return "비슷해요"
        default: return "참고해 주세요"
        }
    }

    private var reliabilityStars: String {
        switch comparedMeasurementKinds.count {
        case 4...: return "★★★★★"
        case 3: return "★★★★☆"
        case 2: return "★★★☆☆"
        case 1: return "★★☆☆☆"
        default: return "★☆☆☆☆"
        }
    }

    private var reliabilityTitle: String {
        switch comparedMeasurementKinds.count {
        case 4...: return "매우 높음"
        case 3: return "높음"
        case 2: return "보통"
        case 1: return "낮음"
        default: return "매우 낮음"
        }
    }

    private var relativeDateText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(history.createdAt) {
            return "오늘"
        }
        if calendar.isDateInYesterday(history.createdAt) {
            return "어제"
        }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: history.createdAt),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0
        return days > 0 ? "\(days)일 전" : history.createdAt.formatted(date: .abbreviated, time: .omitted)
    }

    private var historyBrandText: String {
        isMusinsaProduct
            ? "\(history.productBrandNameForDisplay) (무신사)"
            : history.productBrandNameForDisplay
    }

    private var isMusinsaProduct: Bool {
        let source = history.productSourceNameForDisplay.lowercased()
        if source.contains("무신사") || source.contains("musinsa") {
            return true
        }
        return history.product.sourceURLString?.lowercased().contains("musinsa") == true
    }

    private var formattedHistoryDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy. M. d. (E)"
        return formatter.string(from: history.createdAt)
    }

    private var historySourceCategoryText: String {
        if let sourceCategoryPath = history.product.sourceCategoryPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceCategoryPath.isEmpty {
            return sourceCategoryPath
        }

        return "카테고리 정보 없음"
    }
}

private struct HistoryPriceSnapshotView: View {
    let history: RecommendationHistory

    var body: some View {
        EmptyView()
    }

    private var currentPrice: Int? {
        history.finalPriceSnapshot ?? history.salePriceSnapshot
    }

    private var displayPrice: String? {
        (currentPrice ?? history.normalPriceSnapshot).map(formatPrice)
    }

    private var normalPriceText: String? {
        guard let normal = history.normalPriceSnapshot,
              let current = currentPrice,
              normal > current else {
            return nil
        }
        return formatPrice(normal)
    }

    private var discountText: String? {
        if let rate = history.discountRateSnapshot, rate > 0 {
            let normalizedRate = rate <= 1 ? rate * 100 : rate
            return "\(Int(normalizedRate.rounded()))% 할인"
        }

        guard let normal = history.normalPriceSnapshot,
              let current = currentPrice,
              normal > current else {
            return nil
        }
        let rate = Double(normal - current) / Double(normal) * 100
        return "\(Int(rate.rounded()))% 할인"
    }

    private func formatPrice(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formatted = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(formatted)원"
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
                    currentGridContent
                }
            }
            .buttonStyle(.plain)

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isFavorite ? .red : .primary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }

    private var currentGridContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                ProductThumbnailView(
                    imageURLString: history.productImageURLStringForDisplay,
                    category: history.product.category,
                    width: geometry.size.width,
                    height: 150,
                    cornerRadius: 16
                )
                .overlay(alignment: .bottomTrailing) {
                    Text(relativeDateText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color(.systemBackground).opacity(0.9), in: Capsule())
                        .padding(8)
                }
            }
            .frame(height: 150)

            VStack(alignment: .leading, spacing: 5) {
                Text(history.productBrandNameForDisplay)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(history.productNameForDisplay)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(minHeight: 38, alignment: .topLeading)
            }

            Divider()
                .overlay(.secondary.opacity(0.12))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                gridResult(title: "추천", value: history.recommendedSize.name.displaySizeName)
                Spacer(minLength: 4)
                gridResult(title: "핏 매칭률", value: "\(history.recommendationScore)%")
            }
        }
    }

    private func gridResult(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.black))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
        }
    }

    private var relativeDateText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(history.createdAt) { return "오늘" }
        if calendar.isDateInYesterday(history.createdAt) { return "어제" }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: history.createdAt),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0
        return days > 0 ? "\(days)일 전" : history.createdAt.formatted(date: .abbreviated, time: .omitted)
    }

    // TODO: Legacy UI, 삭제 금지. currentGridContent 대신 연결하면 기존 그리드 카드로 원복할 수 있습니다.
    private var historyGridCardLegacy: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProductThumbnailView(
                imageURLString: history.productImageURLStringForDisplay,
                category: history.product.category,
                width: 126,
                height: 142,
                cornerRadius: 16
            )
            Text(history.productBrandNameForDisplay)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(history.productNameForDisplay)
                .font(.subheadline.weight(.bold))
                .lineLimit(2)
            Text("추천 \(history.recommendedSize.name.displaySizeName) · 핏 매칭률 \(history.recommendationScore)%")
                .font(.caption.weight(.bold))
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
