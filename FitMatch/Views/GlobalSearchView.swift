import SwiftUI
import SwiftData

struct GlobalSearchView: View {
    @Query(sort: \UserFit.updatedAt, order: .reverse) private var userFits: [UserFit]
    @Query(sort: \RecommendationHistory.createdAt, order: .reverse) private var histories: [RecommendationHistory]
    @State private var searchText = ""
    @State private var favoriteURLs = FavoriteProductStore().favoriteURLs()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SearchIntroCard(isSearching: !normalizedSearchText.isEmpty)

                SearchResultSection(
                    title: normalizedSearchText.isEmpty ? "최근 내 옷" : "내 옷장",
                    count: closetResults.count
                ) {
                    if closetResults.isEmpty {
                        SearchEmptyCard(
                            systemImage: "tshirt",
                            title: emptyClosetMessage,
                            message: normalizedSearchText.isEmpty ? "핏이 마음에 드는 옷을 등록하면 검색 결과에 표시됩니다." : "브랜드, 상품명, 카테고리로 다시 검색해보세요."
                        )
                    } else {
                        VStack(spacing: 12) {
                            ForEach(closetResults) { item in
                                NavigationLink {
                                    ClosetItemDetailView(item: item)
                                } label: {
                                    SearchClosetResultRow(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                SearchResultSection(
                    title: normalizedSearchText.isEmpty ? "최근 비교 기록" : "기록",
                    count: historyResults.count
                ) {
                    if historyResults.isEmpty {
                        SearchEmptyCard(
                            systemImage: "clock",
                            title: emptyHistoryMessage,
                            message: normalizedSearchText.isEmpty ? "상품을 비교하면 기록에서 다시 확인할 수 있습니다." : "상품명, 브랜드, 카테고리로 다시 검색해보세요."
                        )
                    } else {
                        VStack(spacing: 12) {
                            ForEach(historyResults) { history in
                                NavigationLink {
                                    RecommendationResultView(result: history)
                                } label: {
                                    SearchHistoryResultRow(
                                        history: history,
                                        isFavorite: isFavorite(history)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("검색")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "브랜드, 상품명, 카테고리 검색")
        .onAppear {
            favoriteURLs = FavoriteProductStore().favoriteURLs()
        }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var closetResults: [UserFit] {
        guard !normalizedSearchText.isEmpty else {
            return Array(userFits.prefix(8))
        }

        return userFits.filter { item in
            item.brandName.lowercased().contains(normalizedSearchText)
                || item.productName.lowercased().contains(normalizedSearchText)
                || item.category.rawValue.lowercased().contains(normalizedSearchText)
                || item.detailCategory.rawValue.lowercased().contains(normalizedSearchText)
                || item.sizeName.lowercased().contains(normalizedSearchText)
        }
    }

    private var historyResults: [RecommendationHistory] {
        guard !normalizedSearchText.isEmpty else {
            return Array(histories.prefix(8))
        }

        return histories.filter { history in
            let product = history.product
            return product.displayName.lowercased().contains(normalizedSearchText)
                || (product.brand?.name.lowercased().contains(normalizedSearchText) ?? false)
                || product.category.rawValue.lowercased().contains(normalizedSearchText)
                || history.productDetailCategory.rawValue.lowercased().contains(normalizedSearchText)
                || product.sourceDisplayName.lowercased().contains(normalizedSearchText)
                || (isFavorite(history) && "관심상품".contains(normalizedSearchText))
        }
    }

    private var emptyClosetMessage: String {
        normalizedSearchText.isEmpty ? "등록된 옷이 없습니다." : "검색된 내 옷이 없습니다."
    }

    private var emptyHistoryMessage: String {
        normalizedSearchText.isEmpty ? "상품 비교 기록이 없습니다." : "검색된 기록이 없습니다."
    }

    private func isFavorite(_ history: RecommendationHistory) -> Bool {
        guard let urlString = history.product.sourceURLString else {
            return false
        }

        return favoriteURLs.contains(urlString)
    }
}

private struct SearchIntroCard: View {
    let isSearching: Bool

    var body: some View {
        CardView(radius: 24, padding: 20) {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(isSearching ? "검색 결과" : "무엇을 찾고 있나요?")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)

                    Text(isSearching ? "내 옷장과 비교 기록을 함께 찾고 있어요." : "브랜드, 상품명, 카테고리를 한 번에 검색하세요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

private struct SearchResultSection<Content: View>: View {
    let title: String
    let count: Int
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                Text("\(count)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)

                Spacer()
            }

            content
        }
    }
}

private struct SearchEmptyCard: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        CardView(radius: 22, padding: 22) {
            VStack(alignment: .center, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 54, height: 54)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())

                VStack(spacing: 5) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct SearchClosetResultRow: View {
    let item: UserFit

    var body: some View {
        CardView(radius: 22, padding: 14) {
            HStack(spacing: 14) {
                thumbnail

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Text(item.brandName)
                            .font(.caption.weight(.black))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if item.isRepresentative {
                            Text("기준 옷")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(Color(.systemBackground))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Color.primary, in: Capsule())
                        }

                        Spacer(minLength: 0)
                    }

                    Text(item.productName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        metadataPill("\(item.category.rawValue) / \(item.detailCategory.rawValue)")
                        metadataPill(item.sizeName)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let imageURLString = item.sourceProduct?.imageURLString,
           !imageURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ProductThumbnailView(imageURLString: imageURLString, width: 76, height: 92, cornerRadius: 16)
        } else {
            Image(systemName: "tshirt")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 76, height: 92)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func metadataPill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
    }
}

private struct SearchHistoryResultRow: View {
    let history: RecommendationHistory
    let isFavorite: Bool

    var body: some View {
        CardView(radius: 22, padding: 14) {
            HStack(spacing: 14) {
                ProductThumbnailView(
                    imageURLString: history.product.imageURLString,
                    width: 76,
                    height: 92,
                    cornerRadius: 16
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Text(history.product.brand?.name ?? history.product.sourceDisplayName)
                            .font(.caption.weight(.black))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.red)
                        }

                        Spacer(minLength: 0)
                    }

                    Text(history.product.name)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        metadataPill("추천 \(history.recommendedSize.name)")
                        metadataPill("핏 매칭률 \(history.recommendationScore)%")
                    }

                    Text("\(history.product.category.rawValue) / \(history.productDetailCategory.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func metadataPill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
    }
}
