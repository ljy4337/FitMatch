import SwiftUI
import SwiftData

struct HomeView: View {
    @Binding var selectedTab: AppTab
    @Query(sort: \UserFit.updatedAt, order: .reverse) private var userFits: [UserFit]
    @Query(sort: \RecommendationHistory.createdAt, order: .reverse) private var histories: [RecommendationHistory]
    @Query(sort: \Product.createdAt, order: .reverse) private var products: [Product]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                heroCard
                overviewGrid
                recommendationSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBarOnScroll()
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("FIT MATCH")
                    .font(.largeTitle.weight(.black))
                    .foregroundStyle(.primary)
                Text("Find Your Perfect Fit.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
            } label: {
                Image(systemName: "bell")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color(.systemBackground), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(.primary.opacity(0.08), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("알림")
        }
    }

    private var heroCard: some View {
        CardView(radius: 24, padding: 24, background: .black) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    Image(systemName: "scalemass.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)

                    Spacer()

                    Text("COMPARE")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.62))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("새 상품 비교")
                        .font(.title.weight(.black))
                        .foregroundStyle(.white)
                    Text("공유한 쇼핑몰 URL을 붙여넣고\n내게 맞는 사이즈를 찾아보세요.")
                        .font(.subheadline)
                        .lineSpacing(3)
                        .foregroundStyle(.white.opacity(0.72))
                }

                Button {
                    selectedTab = .compare
                } label: {
                    Label("상품 URL 붙여넣기", systemImage: "link")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var overviewGrid: some View {
        HStack(alignment: .top, spacing: 14) {
            closetCard
            historyCard
        }
    }

    private var closetCard: some View {
        NavigationLink {
            MyClosetView()
        } label: {
            HomeOverviewCard(title: "내 옷장", value: "\(userFits.count)개", systemImage: "tshirt") {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("대표 옷")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(representativeItem?.displayName ?? "등록 필요")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Text("내 옷장 보기")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var historyCard: some View {
        Button {
            selectedTab = .history
        } label: {
            HomeOverviewCard(title: "기록", value: histories.isEmpty ? "없음" : "\(histories.count)건", systemImage: "clock") {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                    if histories.isEmpty {
                        Text("비교 기록이 없습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(histories.prefix(2))) { history in
                            RecentCompareLine(history: history)
                        }
                    }
                    Spacer(minLength: 0)
                    Text("기록 보기")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var recommendationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "추천", subtitle: "최근 비교 기반")
                Spacer()
                Button {
                    selectedTab = .recommend
                } label: {
                    Text("추천 보러가기")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }

            CardView(radius: 24, padding: 18) {
                if recommendationCandidates.isEmpty {
                    EmptyStateLine(text: "상품 비교를 진행하면 추천 후보가 표시됩니다.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(recommendationCandidates.enumerated()), id: \.element.id) { index, history in
                            RecommendationPreviewRow(history: history)

                            if index != recommendationCandidates.count - 1 {
                                Divider()
                                    .padding(.vertical, 12)
                            }
                        }
                    }
                }
            }
        }
    }

    private var representativeItem: UserFit? {
        userFits.first(where: \.isRepresentative)
    }

    private var recommendationCandidates: [RecommendationHistory] {
        Array(histories.prefix(3))
    }
}

private struct HomeOverviewCard<Content: View>: View {
    let title: String
    let value: String
    let systemImage: String
    private let content: Content

    init(
        title: String,
        value: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 190, maxHeight: 190, alignment: .topLeading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.045), radius: 16, x: 0, y: 8)
    }
}

private struct RecentCompareLine: View {
    let history: RecommendationHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(history.product.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(history.recommendedSize.name)
                Text("\(history.recommendationScore)%")
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
        }
    }
}

private struct RecommendationPreviewRow: View {
    let history: RecommendationHistory

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(history.product.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("출처: \(history.product.sourceDisplayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text(history.recommendedSize.name)
                    .font(.title3.weight(.black))
                    .foregroundStyle(.primary)
                Text("\(history.recommendationScore)%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct EmptyStateLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
