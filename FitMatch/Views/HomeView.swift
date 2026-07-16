import SwiftUI
import SwiftData
import UIKit

struct HomeView: View {
    let onStartCompare: () -> Void
    let onOpenHistory: () -> Void
    let onOpenCloset: () -> Void
    let onRecompare: (String) -> Void
    var onLogout: (() -> Void)?

    @Query(sort: \RecommendationHistory.createdAt, order: .reverse) private var histories: [RecommendationHistory]
    @Query(sort: \UserFit.updatedAt, order: .reverse) private var userFits: [UserFit]
    @State private var favoriteURLs = FavoriteProductStore().favoriteURLs()
    @State private var isTopChromeVisible = true
    private let favoriteStore = FavoriteProductStore()

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    closetDashboardSection
                    recentComparisonSection
                    homeGuideSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 112)
            }
            .contentMargins(.top, FitMatchTopChromeMetrics.height, for: .scrollContent)
            .hidesBottomTabBarOnScroll(tab: .home, topChrome: $isTopChromeVisible)

            CollapsibleTopChrome(isVisible: isTopChromeVisible) {
                FitMatchNavigationHeader(onLogout: onLogout)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 12)
                    .background(Color(.systemGroupedBackground))
            }
            .zIndex(1)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var closetDashboardSection: some View {
        CardView(radius: 22, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "내 옷장 현황", subtitle: "상품 비교에 활용할 수 있는 옷을 확인하세요")

                HStack(spacing: 10) {
                    HomeClosetStat(title: "등록된 옷", value: userFits.count)
                    HomeClosetStat(title: "비교 상의", value: comparableTopCount)
                    HomeClosetStat(title: "비교 하의", value: comparableBottomCount)
                }

                Button(action: onOpenCloset) {
                    HStack {
                        Text("내 옷장 보기")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var recentComparisonSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "최근 비교", subtitle: recentComparisonSubtitle)
                Spacer()
                Button(action: onOpenHistory) {
                    HStack(spacing: 4) {
                        Text("전체보기")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }

            if !recentHistories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(recentHistories) { history in
                            RecentProductPreviewCard(
                                history: history,
                                isFavorite: isFavorite(history),
                                layout: .carousel,
                                onToggleFavorite: { toggleFavorite(history) },
                                onRecompare: {
                                    if let urlString = history.product.sourceURLString {
                                        onRecompare(urlString)
                                    }
                                }
                            )
                            .frame(width: 214)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else {
                Button(action: onStartCompare) {
                    CardView(radius: 22, padding: 18) {
                        HStack(spacing: 14) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.title3.weight(.bold))
                                .frame(width: 44, height: 44)
                                .background(.primary.opacity(0.07), in: Circle())

                            VStack(alignment: .leading, spacing: 5) {
                                Text("첫 상품을 비교해 보세요")
                                    .font(.headline.weight(.bold))
                                Text("상품 링크를 가져오면 내 옷과 맞는 사이즈를 찾아드려요.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 4)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("첫 상품 비교 시작하기")
            }
        }
    }

    private var recentHistories: [RecommendationHistory] {
        var seenKeys = Set<String>()
        return histories.filter { history in
            let key = history.product.sourceURLString ?? history.product.displayName
            return seenKeys.insert(key).inserted
        }
        .prefix(5)
        .map { $0 }
    }

    private var recentComparisonSubtitle: String {
        recentHistories.isEmpty ? "아직 비교 기록이 없습니다" : "최근 비교한 상품을 최대 5개까지 보여드려요"
    }

    private func isFavorite(_ history: RecommendationHistory) -> Bool {
        guard let urlString = history.product.sourceURLString else { return false }
        return favoriteURLs.contains(urlString)
    }

    private func toggleFavorite(_ history: RecommendationHistory) {
        _ = favoriteStore.toggle(history.product.sourceURLString)
        favoriteURLs = favoriteStore.favoriteURLs()
    }

    private var homeGuideSection: some View {
        CardView(radius: 22, padding: 18, background: Color(.secondarySystemGroupedBackground)) {
            VStack(alignment: .leading, spacing: 6) {
                Text("지금 찾는 상품인가요?")
                    .font(.headline.weight(.bold))
                Text("상품 링크를 붙여넣고 내 기준 옷과 사이즈를 비교해보세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var comparableTopCount: Int {
        userFits.filter { $0.resolvedCategoryCode == "tops" }.count
    }

    private var comparableBottomCount: Int {
        userFits.filter {
            $0.resolvedCategoryCode == "bottoms"
                || $0.resolvedCategoryCode == "leggings"
        }.count
    }

}

private struct HomeClosetStat: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(spacing: 5) {
            Text("\(value)")
                .font(.title2.weight(.black))
                .monospacedDigit()
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct EmptyHomeCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        CardView(radius: 22, padding: 18) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .frame(width: 42, height: 42)
                    .background(.primary.opacity(0.06), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if let actionTitle, let action {
                EmptyStateActionButton(title: actionTitle, action: action)
                .padding(.top, 12)
            }
        }
    }
}

#if DEBUG && FITMATCH_LEGACY_COMPARE_START
struct CompareStartSheet: View {
    @Environment(\.openURL) private var openURL
    let onStartCompare: () -> Void
    let onStartCompareWithURL: (String) -> Void
    let onDismiss: () -> Void
    @State private var productURL = ""

    private let platformItems: [(title: String, systemImage: String)] = [
        ("무신사", "m.circle"),
        ("유니클로", "u.circle"),
        ("29CM", "29.circle"),
        ("쿠팡", "cart.circle"),
        ("네이버쇼핑", "n.circle")
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                content
                .padding(.horizontal, 20)

                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("상품 비교 시작")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            urlInputSection

            Divider()
                .padding(.vertical, 2)

            HStack {
                Text("지원 쇼핑몰 바로가기")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 8)

            ForEach(platformItems, id: \.title) { item in
                let isMusinsa = item.title == "무신사"
                CompareStartRow(
                    title: item.title,
                    subtitle: isMusinsa ? "무신사 앱/웹 열기" : "지원 예정",
                    systemImage: item.systemImage,
                    isPlaceholder: !isMusinsa,
                    placeholderText: "준비중",
                    actionText: isMusinsa ? "열기" : nil,
                    isEnabled: isMusinsa,
                    isProminent: isMusinsa
                ) {
                    if isMusinsa {
                        openMusinsa()
                    }
                }
            }
        }
    }

    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("상품 URL 입력")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                Text("쇼핑몰 상품 링크를 붙여넣으면 사이즈표를 불러와 내 옷장과 비교합니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                TextField("상품 URL을 붙여넣어 주세요", text: $productURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.URL)
                    .submitLabel(.search)
                    .onSubmit {
                        submitURL()
                    }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button(action: submitURL) {
                Label("비교하기", systemImage: "sparkles")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(canSubmitURL ? Color.black : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmitURL)
        }
    }

    private var canSubmitURL: Bool {
        ProductURLSupport.isSupportedProductURL(productURL)
    }

    private func submitURL() {
        let trimmedURL = productURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ProductURLSupport.isSupportedProductURL(trimmedURL) else {
            return
        }

        onStartCompareWithURL(trimmedURL)
    }

    private func openMusinsa() {
        guard let url = URL(string: "https://musinsa.onelink.me/PvkC/msuf8hvg") else {
            return
        }

        UIApplication.shared.open(url)
    }
}

private struct CompareStartRow: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    let isPlaceholder: Bool
    var placeholderText: String = "상품추가"
    var actionText: String?
    var isEnabled: Bool = true
    var isProminent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(isProminent ? Color(.systemBackground) : .primary)
                    .frame(width: 34, height: 34)
                    .background(isProminent ? Color.black : .primary.opacity(0.06), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let actionText {
                    Text(actionText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(.systemBackground))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.black, in: Capsule())
                } else if isPlaceholder {
                    Text(placeholderText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, isProminent ? 12 : 0)
            .padding(.vertical, 13)
            .background(
                isProminent ? Color.black.opacity(0.06) : Color.clear,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                if isProminent {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
    }
}

#endif

struct RecentProductPreviewCard: View {
    enum Layout {
        case compact
        case carousel
    }

    let history: RecommendationHistory
    let isFavorite: Bool
    var layout: Layout = .compact
    let onToggleFavorite: () -> Void
    let onRecompare: () -> Void

    var body: some View {
        FitMatchCard {
            ZStack(alignment: .topTrailing) {
                NavigationLink {
                    RecommendationResultView(result: history)
                } label: {
                    if layout == .carousel {
                        carouselContent
                    } else {
                        compactContent
                    }
                }
                .buttonStyle(.plain)

                favoriteButton
                    .padding(layout == .carousel ? 9 : 0)
            }
        }
    }

    private var carouselContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            resultSummary

            ProductThumbnailView(
                imageURLString: history.product.imageURLString,
                category: history.product.category,
                width: 178,
                height: 112,
                cornerRadius: 18
            )

            productText

            HStack {
                Spacer()
                recompareButton
            }
        }
    }

    private var compactContent: some View {
        HStack(alignment: .top, spacing: 14) {
            ProductThumbnailView(
                imageURLString: history.product.imageURLString,
                category: history.product.category,
                width: 86,
                height: 108,
                cornerRadius: 18
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    productText
                    Spacer(minLength: 8)
                    Color.clear.frame(width: 34, height: 34)
                }

                HStack {
                    fitSummary
                    Spacer()
                    recompareButton
                }
            }
        }
    }

    private var productText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(history.product.brand?.name ?? history.product.sourceDisplayName)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(history.product.name)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
    }

    private var fitSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("추천 \(history.recommendedSize.name.displaySizeName)")
                .font(.subheadline.weight(.bold))
            Text("핏 매칭률 \(history.recommendationScore)%")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var resultSummary: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("추천 사이즈")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(history.recommendedSize.name.displaySizeName)
                    .font(.title2.weight(.black))
                    .foregroundStyle(.primary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("핏 매칭률")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text("\(history.recommendationScore)%")
                    .font(.title2.weight(.black))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
        }
        .padding(12)
        .padding(.trailing, 30)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var favoriteButton: some View {
        Button(action: onToggleFavorite) {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.headline.weight(.semibold))
                .foregroundStyle(isFavorite ? .red : .primary)
                .frame(width: 34, height: 34)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var recompareButton: some View {
        Button(action: onRecompare) {
            Text("다시 비교")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(.systemBackground))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.primary, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(history.product.sourceURLString == nil)
        .opacity(history.product.sourceURLString == nil ? 0.45 : 1)
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
