import SwiftUI
import SwiftData

struct RecommendationHistoryView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Environment(\.fitMatchComparisonSyncCoordinator) private var comparisonSync
    @Query(sort: \RecommendationHistory.createdAt, order: .reverse) private var histories: [RecommendationHistory]
    @AppStorage("FitMatch.historyViewLayout") private var historyViewLayoutRaw = ContentListLayout.list.rawValue
    @State private var sortOption: FitMatchHistorySortOption = .latest
    @State private var selectedScope: FitMatchHistoryScope = .all
    @State private var selectedCategory: ClothingCategory?
    @State private var searchText = ""
    @State private var favoriteURLs = FavoriteProductStore().favoriteURLs()
    @State private var selectedHistoryForCloset: RecommendationHistory?
    @State private var selectedHistoryIDForDetail: UUID?
    @State private var opensReferencePickerOnDetail = false
    @State private var saveErrorMessage: String?
    @State private var isTopChromeVisible = true
    @State private var isShowingClosetSavedToast = false
    @State private var cachedFilteredHistories: [RecommendationHistory] = []
    @State private var cachedAvailableCategories: [ClothingCategory] = []
    @State private var hidingHistoryIDs = Set<UUID>()
    private let favoriteStore = FavoriteProductStore()
    var onRecompare: ((FitMatchHistoryRecompareAction.StartRequest) -> Void)?
    var onStartCompare: (() -> Void)?
    var onLogout: (() -> Void)?

    init(onRecompare: ((FitMatchHistoryRecompareAction.StartRequest) -> Void)? = nil, onStartCompare: (() -> Void)? = nil, onLogout: (() -> Void)? = nil) {
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
        .searchable(text: $searchText, prompt: "브랜드 또는 상품명 검색")
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
                recommendedSize: history.recommendedSize,
                startsAtRegistrationConfirmation: true
            ) { _ in
                showClosetSavedToast()
            }
            .presentationDetents([.large])
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
        .overlay(alignment: .top) {
            if isShowingClosetSavedToast {
                FitMatchSuccessToast(message: "보유한 옷으로 등록했어요.")
                    .padding(.top, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            refreshFilteredHistories()
        }
        .onChange(of: histories.count) {
            refreshFilteredHistories()
        }
        .onChange(of: sortOption) {
            refreshFilteredHistories()
        }
        .onChange(of: selectedScope) {
            refreshFilteredHistories()
        }
        .onChange(of: selectedCategory) {
            refreshFilteredHistories()
        }
        .onChange(of: searchText) {
            refreshFilteredHistories()
        }
    }

    private func showClosetSavedToast() {
        withAnimation { isShowingClosetSavedToast = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation { isShowingClosetSavedToast = false }
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

            if displayedHistories.isEmpty {
                EmptyRecommendationHistoryView(onStartCompare: histories.isEmpty ? onStartCompare : nil)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 36, leading: 20, bottom: 24, trailing: 20))
            } else {
                ForEach(displayedHistories) { history in
                    HistoryCard(
                        history: history,
                        isFavorite: isFavorite(history)
                    ) {
                        toggleFavorite(history)
                    } onOpen: {
                        openShoppingMall(history)
                    } onRecompare: {
                        opensReferencePickerOnDetail = true
                        showDetail(history)
                    } onAddToCloset: {
                        selectedHistoryForCloset = history
                    } onShowDetail: {
                        opensReferencePickerOnDetail = false
                        showDetail(history)
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    // Temporarily disabled: restore these lines to re-enable
                    // right-swipe favorite assignment/removal.
//                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
//                        favoriteSwipeButton(for: history)
//                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        deleteSwipeButton(for: history)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, FitMatchTopChromeMetrics.height, for: .scrollContent)
        .hidesBottomTabBarOnScroll(tab: .history, topChrome: $isTopChromeVisible)
    }

    private var historyGrid: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                historyControls

                if displayedHistories.isEmpty {
                    EmptyRecommendationHistoryView(onStartCompare: histories.isEmpty ? onStartCompare : nil)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.top, 36)
                } else {
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(displayedHistories) { history in
                        HistoryGridCard(
                            history: history,
                            isFavorite: isFavorite(history),
                            onToggleFavorite: {
                                toggleFavorite(history)
                            },
                            onShowDetail: {
                                opensReferencePickerOnDetail = false
                                showDetail(history)
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
        .hidesBottomTabBarOnScroll(tab: .history, topChrome: $isTopChromeVisible)
    }

    private var historyLayout: ContentListLayout {
        get { ContentListLayout(rawValue: historyViewLayoutRaw) ?? .list }
        nonmutating set { historyViewLayoutRaw = newValue.rawValue }
    }

    private func showDetail(_ history: RecommendationHistory) {
        DetailPerformanceDiagnostics.beginHistoryResultNavigation(
            productName: history.productNameForDisplay
        )
        selectedHistoryIDForDetail = history.id
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
                options: FitMatchHistoryScope.allCases.map { ContentFilterOption(id: $0.rawValue, title: $0.title) },
                onSelect: { id in
                    selectedScope = FitMatchHistoryScope(rawValue: id) ?? .all
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
                options: FitMatchHistorySortOption.allCases.map { ContentFilterOption(id: $0.rawValue, title: $0.title) },
                onSelect: { id in
                    sortOption = FitMatchHistorySortOption(rawValue: id) ?? .latest
                }
            )
        ]
    }

    private var availableCategories: [ClothingCategory] {
        cachedAvailableCategories
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
        switch FitMatchHistoryRecompareAction.outcome(for: history) {
        case .openCompare(let request):
            onRecompare?(request)
        case .unavailable(let message):
            saveErrorMessage = message
        }
    }

    private func deleteHistory(_ history: RecommendationHistory) {
        guard !hidingHistoryIDs.contains(history.id) else { return }

        guard history.isServerBackedVNextHistory else {
            deleteHistoryLocally(history)
            return
        }

        guard let comparisonSync else {
            saveErrorMessage = "서버 비교 기록을 삭제할 준비가 되지 않았어요. 다시 시도해 주세요."
            return
        }

        hidingHistoryIDs.insert(history.id)
        Task { @MainActor in
            defer { hidingHistoryIDs.remove(history.id) }
            let outcome = await FitMatchHistoryVisibilityAction.delete(
                history,
                in: modelContext,
                comparisonSync: comparisonSync
            )
            if let message = outcome.userVisibleMessage {
                refreshFilteredHistories()
                saveErrorMessage = message
            } else {
                refreshFilteredHistories()
            }
        }
    }

    private func deleteHistoryLocally(
        _ history: RecommendationHistory,
        localSaveFailureMessage: String = "비교 기록을 삭제하지 못했어요. 다시 시도해 주세요."
    ) {
        let outcome = FitMatchHistoryVisibilityAction.deleteLocally(
            history,
            in: modelContext,
            afterServerHide: false
        )
        if let message = outcome.userVisibleMessage {
            refreshFilteredHistories()
            saveErrorMessage = outcome == .localPersistenceFailed
                ? localSaveFailureMessage
                : message
            return
        }
        refreshFilteredHistories()
    }

    private var displayedHistories: [RecommendationHistory] {
        cachedFilteredHistories
    }

    private func refreshFilteredHistories() {
        cachedFilteredHistories = makeFilteredHistories()
        cachedAvailableCategories = Array(Set(histories.map { $0.product.category }))
            .sorted { $0.rawValue < $1.rawValue }
    }

    private func makeFilteredHistories() -> [RecommendationHistory] {
        FitMatchHistoryPresentation.displayedHistories(
            from: histories,
            searchText: searchText,
            scope: selectedScope,
            category: selectedCategory,
            favoriteURLs: favoriteURLs,
            sort: sortOption
        )
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
        refreshFilteredHistories()
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
        .disabled(hidingHistoryIDs.contains(history.id))
        .tint(.red)
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
                    Text("아직 비교한 상품이 없어요.")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("상품을 비교하면 결과가 여기에 저장돼요.")
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
    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy. M. d. (E)"
        return formatter
    }()

    var body: some View {
        let comparedKinds = resolvedComparedMeasurementKinds
        FitMatchCard(shadowRadius: 8) {
            currentCardContent(comparedKinds: comparedKinds)
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .onTapGesture(perform: onShowDetail)
        }
    }

    private func currentCardContent(comparedKinds: [MeasurementKind]) -> some View {
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
                let availableWidth = geometry.size.width - (dividerWidth * 2)
                let primaryMetricWidth = availableWidth * 0.30
                let reliabilityWidth = availableWidth * 0.40

                HStack(alignment: .top, spacing: 0) {
                    RecommendationMetricColumn(
                        title: "추천 사이즈",
                        value: history.recommendedSize.name.displaySizeName,
                        detail: nil,
                        isPrimary: true,
                        style: .historyCompact,
                        leadingPadding: 0
                    )
                        .frame(width: primaryMetricWidth)
                    Divider().frame(width: dividerWidth, height: 88)
                    RecommendationMetricColumn(
                        title: "사이즈 유사도",
                        value: "\(history.recommendationScore)%",
                        detail: fitMatchBadge,
                        isPrimary: true,
                        style: .historyCompact
                    )
                        .frame(width: primaryMetricWidth)
                    Divider().frame(width: dividerWidth, height: 88)
                    reliabilityMetric(comparedKinds: comparedKinds)
                        .frame(width: reliabilityWidth)
                }
            }
            .frame(height: 100)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 8) {
                Image(systemName: "ruler")
                    .rotationEffect(.degrees(-38))
                Text(measurementSummaryText(comparedKinds: comparedKinds))
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

    private func reliabilityMetric(comparedKinds: [MeasurementKind]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("신뢰도")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
            Text(reliabilityStars(comparedCount: comparedKinds.count))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.orange.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(reliabilityTitle(comparedCount: comparedKinds.count))
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
            Text(measurementSummaryText(comparedKinds: comparedKinds))
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
                historyMetric(title: "사이즈 유사도", value: "\(history.recommendationScore)%")
            }
            .padding(14)
            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(measurementSummaryText(comparedKinds: resolvedComparedMeasurementKinds))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }

    private func measurementSummaryText(comparedKinds: [MeasurementKind]) -> String {
        comparedKinds.isEmpty ? "실측 부족" : "실측 \(comparedKinds.count)개 항목 비교"
    }

    private var resolvedComparedMeasurementKinds: [MeasurementKind] {
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
        case 90...: return "거의 완벽한 핏"
        case 80..<90: return "매우 잘 맞는 편"
        case 70..<80: return "잘 맞는 편"
        case 60..<70: return "약간의 차이가 있어요"
        case 50..<60: return "핏 차이를 확인해 보세요"
        case 40..<50: return "핏 차이가 큰 편이에요"
        default: return "추천하기 어려워요"
        }
    }

    private func reliabilityStars(comparedCount: Int) -> String {
        let count = reliabilityStarCount(comparedCount: comparedCount)
        return String(repeating: "★", count: count)
            + String(repeating: "☆", count: 5 - count)
    }

    private func reliabilityTitle(comparedCount: Int) -> String {
        let title: String
        switch reliabilityStarCount(comparedCount: comparedCount) {
        case 5: title = "매우 높음"
        case 4: title = "높음"
        case 3: title = "보통"
        case 2: title = "낮음"
        default: title = "매우 낮음"
        }
        return history.comparisonMethod.contains("확장 비교") ? "확장 · \(title)" : title
    }

    private func reliabilityStarCount(comparedCount: Int) -> Int {
        let base: Int
        switch comparedCount {
        case 4...: base = 5
        case 3: base = 4
        case 2: base = 3
        case 1: base = 2
        default: base = 1
        }
        return max(1, base - (history.comparisonMethod.contains("확장 비교") ? 1 : 0))
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
        Self.historyDateFormatter.string(from: history.createdAt)
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
                CardView(radius: 20, padding: 12, shadowRadius: 8) {
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
                gridResult(title: "사이즈 유사도", value: "\(history.recommendationScore)%")
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
            Text("추천 \(history.recommendedSize.name.displaySizeName) · 사이즈 유사도 \(history.recommendationScore)%")
                .font(.caption.weight(.bold))
        }
    }
}

private extension String {
    var displaySizeName: String {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        let finalComponent = value
            .split(separator: "/")
            .last
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? value
        return SizeTokenNormalizer.displayName(for: finalComponent)
    }
}
