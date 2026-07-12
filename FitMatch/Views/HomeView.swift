import SwiftUI
import SwiftData
import UIKit

struct HomeView: View {
    let recentClipboardCandidate: SmartClipboardCandidate?
    let onStartCompare: () -> Void
    let onStartCompareWithURL: (String) -> Void
    let onOpenHistory: () -> Void
    let onRecompare: (String) -> Void
    var onLogout: (() -> Void)?

    @Query(sort: \RecommendationHistory.createdAt, order: .reverse) private var histories: [RecommendationHistory]
    @State private var favoriteURLs = FavoriteProductStore().favoriteURLs()
    @State private var isTopChromeVisible = true
    private let favoriteStore = FavoriteProductStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if isTopChromeVisible {
                    FitMatchNavigationHeader(onLogout: onLogout)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                clipboardSection
                recentProductsSection
                advertisementSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 112)
            .tracksTabBarVisibilityOnScroll(.home)
        }
        .background(Color(.systemGroupedBackground))
        .fitMatchTabScrollCoordinateSpace(.home)
        .hidesTopChromeOnScroll($isTopChromeVisible)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var clipboardSection: some View {
        if let recentClipboardCandidate {
            CardView(radius: 20, padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.title3.weight(.semibold))
                            .frame(width: 42, height: 42)
                            .background(.primary.opacity(0.06), in: Circle())

                        VStack(alignment: .leading, spacing: 5) {
                            Text("최근 복사한 링크 발견")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.primary)
                            Text(recentClipboardCandidate.providerName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()
                    }

                    PrimaryButton(title: "바로 비교하기", systemImage: "sparkles") {
                        onStartCompareWithURL(recentClipboardCandidate.urlString)
                    }
                }
            }
        }
    }

    private var recentProductsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "최근 비교한 상품", subtitle: recentProductsSubtitle)
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

            if recentHistories.isEmpty {
                EmptyHomeCard(
                    title: "아직 비교한 상품이 없습니다.",
                    subtitle: "첫 상품을 비교해보세요.",
                    systemImage: "clock",
                    actionTitle: "비교 시작",
                    action: onStartCompare
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(recentHistories) { history in
                            RecentProductPreviewCard(
                                history: history,
                                isFavorite: isFavorite(history),
                                layout: .carousel,
                                onToggleFavorite: {
                                    toggleFavorite(history)
                                },
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
            }
        }
    }

    private var advertisementSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "혹시 찾는 상품인가요?", subtitle: "광고 SDK 연결 예정")
                Spacer()
                Text("AD")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    AdvertisementPlaceholderCard(
                        title: "핏 데이터 기반 상품",
                        subtitle: "내 기준 옷과 가까운 상품 영역",
                        systemImage: "sparkles"
                    )
                    AdvertisementPlaceholderCard(
                        title: "브랜드 캠페인",
                        subtitle: "추후 제휴 광고 노출 자리",
                        systemImage: "tag"
                    )
                    AdvertisementPlaceholderCard(
                        title: "쇼핑몰 추천",
                        subtitle: "플랫폼 광고 SDK 연결 예정",
                        systemImage: "bag"
                    )
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var recentHistories: [RecommendationHistory] {
        uniqueRecentHistories().prefix(3).map { $0 }
    }

    private var recentProductsSubtitle: String {
        let count = recentHistories.count
        guard count > 0 else {
            return "아직 비교 기록이 없습니다"
        }

        return count == 1 ? "1건" : "최근 \(count)건"
    }

    private func uniqueRecentHistories() -> [RecommendationHistory] {
        var seenKeys = Set<String>()
        var results: [RecommendationHistory] = []

        for history in histories.sorted(by: { $0.createdAt > $1.createdAt }) {
            let key = history.product.sourceURLString ?? history.product.displayName
            guard !seenKeys.contains(key) else {
                continue
            }

            seenKeys.insert(key)
            results.append(history)
        }

        return results
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

private struct AdvertisementPlaceholderCard: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        CardView(radius: 22, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .frame(width: 42, height: 42)
                    .background(.primary.opacity(0.06), in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(width: 240, height: 150)
    }
}

struct CompareStartSheet: View {
    @Environment(\.openURL) private var openURL
    let recentClipboardCandidate: SmartClipboardCandidate?
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
            if let recentClipboardCandidate {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("최근 복사한 링크")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text(recentClipboardCandidate.providerName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    PrimaryButton(title: "바로 비교하기", systemImage: "sparkles") {
                        onStartCompareWithURL(recentClipboardCandidate.urlString)
                    }
                }
                .padding(16)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                }

                Divider()
                    .padding(.vertical, 2)
            }

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

                Button("붙여넣기") {
                    productURL = UIPasteboard.general.string ?? productURL
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button(action: submitURL) {
                Label("사이즈 계산", systemImage: "sparkles")
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
        !productURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitURL() {
        let trimmedURL = productURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            return
        }

        onStartCompareWithURL(trimmedURL)
    }

    private func openMusinsa() {
        guard let url = URL(string: "https://musinsa.onelink.me/PvkC/51vm2j7p") else {
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
            ProductThumbnailView(
                imageURLString: history.product.imageURLString,
                category: history.product.category,
                width: 178,
                height: 178,
                cornerRadius: 18
            )

            productText

            HStack {
                fitSummary
                Spacer()
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
            ProductPriceView(product: history.product)
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

struct SmartClipboardPromptSheet: View {
    let candidate: SmartClipboardCandidate
    let matchingHistory: RecommendationHistory?
    let onCompare: (Bool) -> Void
    let onLater: (Bool) -> Void

    @State private var muteToday = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Capsule()
                .fill(.tertiary)
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("최근 복사한 상품을 발견했어요.")
                    .font(.title3.weight(.black))
                Text("바로 비교하시겠어요?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                ProductThumbnailView(
                    imageURLString: matchingHistory?.product.imageURLString,
                    category: matchingHistory?.product.category,
                    width: 84,
                    height: 104,
                    cornerRadius: 16
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(matchingHistory?.product.brand?.name ?? candidate.providerName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(matchingHistory?.product.name ?? "복사한 상품 링크")
                        .font(.headline.weight(.bold))
                        .lineLimit(2)
                    Text(candidate.urlString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Toggle("오늘은 다시 묻지 않기", isOn: $muteToday)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                Button {
                    onLater(muteToday)
                } label: {
                    Text("나중에 하기")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    onCompare(muteToday)
                } label: {
                    Text("바로 비교")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
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
