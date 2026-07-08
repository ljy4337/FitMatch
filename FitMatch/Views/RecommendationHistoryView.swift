import SwiftUI
import SwiftData

struct RecommendationHistoryView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecommendationHistory.createdAt, order: .reverse) private var histories: [RecommendationHistory]
    var onRecompare: ((String) -> Void)?

    init(onRecompare: ((String) -> Void)? = nil) {
        self.onRecompare = onRecompare
    }

    var body: some View {
        Group {
            if histories.isEmpty {
                EmptyRecommendationHistoryView()
            } else {
                List {
                    ForEach(histories) { history in
                        HistoryCard(history: history) {
                            openShoppingMall(history)
                        } onRecompare: {
                            recompare(history)
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    }
                    .onDelete(perform: deleteItems)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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

    private func recompare(_ history: RecommendationHistory) {
        guard let urlString = history.product.sourceURLString else {
            return
        }
        onRecompare?(urlString)
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let history = histories[index]
            modelContext.delete(history)
        }
        try? modelContext.save()
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
                Text("추천 기록이 없습니다.")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Text("상품을 비교하면 추천 결과가 여기에 쌓입니다.")
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
    let onOpen: () -> Void
    let onRecompare: () -> Void

    var body: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(history.product.displayName)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("출처: \(history.product.sourceDisplayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text("\(history.product.category.rawValue) / \(history.productDetailCategory.rawValue) / \(history.recommendedSize.name)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
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

                HStack(spacing: 8) {
                    Label(history.recommendedSize.name, systemImage: "tag.fill")
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
                    Button("쇼핑몰 이동", action: onOpen)
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.primary, in: Capsule())
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
