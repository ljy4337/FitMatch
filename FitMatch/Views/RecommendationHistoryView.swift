import SwiftUI
import SwiftData

struct RecommendationHistoryView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecommendationHistory.createdAt, order: .reverse) private var histories: [RecommendationHistory]
    @State private var searchText = ""
    @State private var sortOption: HistorySortOption = .latest
    @State private var selectedScope: HistoryScope = .all
    @State private var favoriteURLs = FavoriteProductStore().favoriteURLs()
    @State private var selectedHistoryForCloset: RecommendationHistory?
    @State private var isShowingClosetSavedAlert = false
    private let favoriteStore = FavoriteProductStore()
    var onRecompare: ((String) -> Void)?

    init(onRecompare: ((String) -> Void)? = nil) {
        self.onRecompare = onRecompare
    }

    var body: some View {
        Group {
            if histories.isEmpty {
                EmptyRecommendationHistoryView()
            } else {
                VStack(spacing: 0) {
                    historyControls

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
                                recompare(history)
                            } onAddToCloset: {
                                selectedHistoryForCloset = history
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        }
                        .onDelete(perform: deleteItems)

                        Color.clear
                            .frame(height: 92)
                            .listRowSeparator(.hidden)
                            .listRowInsets(.init())
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBarOnScroll()
        .sheet(item: $selectedHistoryForCloset) { history in
            AddComparedProductToClosetSheet(
                product: history.product,
                productDetailCategory: history.productDetailCategory,
                recommendedSize: history.recommendedSize
            ) {
                isShowingClosetSavedAlert = true
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("내 옷장에 추가했어요.", isPresented: $isShowingClosetSavedAlert) {
            Button("확인", role: .cancel) {}
        }
    }

    private var historyControls: some View {
        VStack(spacing: 12) {
            Picker("기록 범위", selection: $selectedScope) {
                ForEach(HistoryScope.allCases, id: \.self) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)

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

            HStack {
                Text("\(selectedScope.title) \(filteredHistories.count)건")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Spacer()

                Menu {
                    ForEach(HistorySortOption.allCases, id: \.self) { option in
                        Button(option.title) {
                            sortOption = option
                        }
                    }
                } label: {
                    Label(sortOption.title, systemImage: "arrow.up.arrow.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .background(Color(.systemBackground))
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

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let history = filteredHistories[index]
            modelContext.delete(history)
        }
        try? modelContext.save()
    }

    private var filteredHistories: [RecommendationHistory] {
        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let scoped = histories.filter { history in
            switch selectedScope {
            case .all:
                return true
            case .favorite:
                return isFavorite(history)
            }
        }

        let filtered = scoped.filter { history in
            guard !normalizedSearchText.isEmpty else {
                return true
            }

            return history.product.displayName.lowercased().contains(normalizedSearchText)
                || (history.product.brand?.name.lowercased().contains(normalizedSearchText) ?? false)
                || history.product.sourceDisplayName.lowercased().contains(normalizedSearchText)
        }

        switch sortOption {
        case .latest:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return filtered.sorted { $0.createdAt < $1.createdAt }
        case .brand:
            return filtered.sorted { ($0.product.brand?.name ?? "") < ($1.product.brand?.name ?? "") }
        case .fitConfidence:
            return filtered.sorted { $0.recommendationScore > $1.recommendationScore }
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
}

private enum HistorySortOption: CaseIterable {
    case latest
    case oldest
    case brand
    case fitConfidence

    var title: String {
        switch self {
        case .latest: return "최신순"
        case .oldest: return "오래된순"
        case .brand: return "브랜드순"
        case .fitConfidence: return "Fit Confidence 높은순"
        }
    }
}

private enum HistoryScope: CaseIterable {
    case all
    case favorite

    var title: String {
        switch self {
        case .all: return "전체"
        case .favorite: return "관심"
        }
    }
}

private struct EmptyRecommendationHistoryView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 160, height: 160)

            VStack(spacing: 6) {
                Text("상품 비교 기록이 없습니다.")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Text("상품을 비교하면 비교 결과가 여기에 쌓입니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

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

    var body: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 14) {
                NavigationLink {
                    RecommendationResultView(result: history)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        ProductThumbnailView(
                            imageURLString: history.product.imageURLString,
                            width: 76,
                            height: 92,
                            cornerRadius: 16
                        )

                        VStack(alignment: .leading, spacing: 5) {
                            Text(history.product.displayName)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text("출처: \(history.product.sourceDisplayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Text("\(history.product.category.rawValue) / \(history.productDetailCategory.rawValue) / \(history.recommendedSize.name.displaySizeName)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 6) {
                            Button(action: onToggleFavorite) {
                                Image(systemName: isFavorite ? "heart.fill" : "heart")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(isFavorite ? .red : .primary)
                                    .frame(width: 34, height: 34)
                                    .background(.primary.opacity(0.06), in: Circle())
                            }
                            .buttonStyle(.plain)

                            Text("Fit Confidence")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text("\(history.recommendationScore)%")
                                .font(.title3.weight(.black))
                                .foregroundStyle(.primary)

                            Text(history.createdAt, style: .date)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.primary.opacity(0.08), in: Capsule())
                        }
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    Label(history.recommendedSize.name.displaySizeName, systemImage: "tag.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.primary.opacity(0.08), in: Capsule())

                    Text(history.comparisonMethod)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.primary.opacity(0.08), in: Capsule())
                }

                HStack(spacing: 10) {
                    Button("내 옷장에 추가", action: onAddToCloset)
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.primary, in: Capsule())

                    Button("쇼핑몰 이동", action: onOpen)
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.primary.opacity(0.08), in: Capsule())
                        .disabled(history.product.sourceURLString == nil)
                        .opacity(history.product.sourceURLString == nil ? 0.35 : 1)

                    Button("다시 비교", action: onRecompare)
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.primary.opacity(0.08), in: Capsule())
                        .disabled(history.product.sourceURLString == nil)
                        .opacity(history.product.sourceURLString == nil ? 0.35 : 1)
                }

                NavigationLink {
                    RecommendationResultView(result: history)
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
