import SwiftUI
import SwiftData

struct RecommendView: View {
    @Environment(\.openURL) private var openURL
    @Query(sort: \RecommendationHistory.createdAt, order: .reverse) private var histories: [RecommendationHistory]

    var body: some View {
        Group {
            if histories.isEmpty {
                EmptyRecommendView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(histories.prefix(6))) { history in
                            RecommendProductCard(history: history) {
                                openShoppingMall(history)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                }
            }
        }
            .background(Color(.systemBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .hidesTabBarOnScroll()
    }

    private func openShoppingMall(_ history: RecommendationHistory) {
        guard let urlString = history.product.sourceURLString,
              let url = URL(string: urlString) else {
            return
        }

        openURL(url)
    }
}

private struct EmptyRecommendView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            Image(systemName: "sparkles")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 160, height: 160)

            VStack(spacing: 6) {
                Text("추천 상품을 준비 중입니다.")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Text("나중에 AI 추천과 광고 상품을 이곳에서 보여줄 예정입니다.")
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

private struct RecommendProductCard: View {
    let history: RecommendationHistory
    let onBuy: () -> Void

    var body: some View {
        FitMatchCard {
            HStack(alignment: .top, spacing: 14) {
                ProductThumbnailView(
                    imageURLString: history.product.imageURLString,
                    width: 84,
                    height: 106,
                    cornerRadius: 16
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(history.product.displayName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text("출처: \(history.product.sourceDisplayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text("추천 \(history.recommendedSize.name)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.primary.opacity(0.08), in: Capsule())

                        Text("\(history.recommendationScore)%")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }

                    Button("구매하기", action: onBuy)
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.primary, in: Capsule())
                        .disabled(history.product.sourceURLString == nil)
                        .opacity(history.product.sourceURLString == nil ? 0.35 : 1)
                }

                Spacer(minLength: 0)
            }
        }
    }
}
