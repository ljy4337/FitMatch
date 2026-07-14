//
//  ContentView.swift
//  FitMatch
//
//  Created by 이진영 on 7/3/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var brands: [Brand]
    @Query private var products: [Product]
    @Query private var userFits: [UserFit]
    @Query(sort: \RecommendationHistory.createdAt, order: .reverse) private var histories: [RecommendationHistory]
    @State private var selectedTab: AppTab = .home
    @State private var hasFinishedSplash = false
    @State private var isLoggedIn = false
    @State private var pendingCompareURL: String?
    @State private var compareViewID = UUID()
    @State private var clipboardCandidate: SmartClipboardCandidate?
    @State private var recentClipboardCandidate: SmartClipboardCandidate?
    @State private var lastCompareLaunchKey: String?
    @State private var lastCompareLaunchDate = Date.distantPast
    private let sharedURLStore = SharedURLStore()
    private let smartClipboardService = SmartClipboardService()

    var body: some View {
        Group {
            #if DEBUG
            if let screenshotCase = ScreenshotCase.current {
                ScreenshotShowcaseView(screenshotCase: screenshotCase)
            } else
            {
                normalContent
            }
            #else
            normalContent
            #endif
        }
        .dismissesKeyboardOnBackgroundTap()
        .task {
            SampleDataService.removeLegacySamples(
                modelContext: modelContext,
                products: products,
                userFits: userFits,
                histories: histories
            )
            try? await Task.sleep(nanoseconds: 800_000_000)
            hasFinishedSplash = true
            openPendingSharedURLIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshRecentClipboardCandidate()
                if !openPendingSharedURLIfNeeded() {
                    inspectClipboardIfNeeded()
                }
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    @ViewBuilder
    private var normalContent: some View {
        if !hasFinishedSplash {
            SplashView()
        } else if !isLoggedIn {
            LoginView {
                isLoggedIn = true
                inspectClipboardIfNeeded()
            }
        } else {
                MainTabView(
                    selectedTab: $selectedTab,
                    clipboardCandidate: $clipboardCandidate,
                    compareURL: pendingCompareURL,
                    onCompareURLConsumed: { pendingCompareURL = nil },
                    onClipboardCandidateHandled: { candidate, shouldMuteToday in
                        smartClipboardService.markHandled(candidate)
                        if shouldMuteToday {
                            smartClipboardService.muteToday()
                        }
                    },
                    recentClipboardCandidate: recentClipboardCandidate,
                    histories: histories,
                    onRecompare: { urlString in
                        openCompare(with: urlString)
                    },
                    onStartCompareLatestURL: {
                        openCompareUsingLatestAvailableURL()
                    },
                    onRefreshClipboardCandidate: {
                        refreshRecentClipboardCandidate()
                    },
                    onLogout: {
                        isLoggedIn = false
                        selectedTab = .home
                        pendingCompareURL = nil
                    },
                    compareViewID: compareViewID
                )
        }
    }

    private func handleDeepLink(_ url: URL) {
        print("[FitMatch] onOpenURL: \(url.absoluteString)")

        guard isSupportedDeepLink(url) else {
            print("[FitMatch] unsupported deep link: \(url.absoluteString)")
            return
        }

        switch deepLinkRoute(from: url) {
        case "compare":
            openCompareFromDeepLink()
        default:
            _ = openPendingSharedURLIfNeeded()
        }
    }

    private func isSupportedDeepLink(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "fitmatch":
            return true
        case "https":
            return url.host?.lowercased() == "fitmatch.app"
        default:
            return false
        }
    }

    private func deepLinkRoute(from url: URL) -> String {
        if url.scheme?.lowercased() == "fitmatch", let host = url.host, !host.isEmpty {
            return host.lowercased()
        }

        let pathComponents = url.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/")
            .map(String.init)

        return pathComponents.first?
            .lowercased()
            ?? ""
    }

    private func openCompareFromDeepLink() {
        if openPendingSharedURLIfNeeded() {
            return
        }

        print("[FitMatch] opening compare tab from deep link without pending URL")
        isLoggedIn = true
        pendingCompareURL = nil
        compareViewID = UUID()
        selectedTab = .home
    }

    @discardableResult
    private func openPendingSharedURLIfNeeded() -> Bool {
        guard let urlString = sharedURLStore.consumePendingProductURL() else {
            print("[FitMatch] no pending shared URL")
            return false
        }

        print("[FitMatch] consumed pending shared URL: \(urlString)")
        isLoggedIn = true
        selectedTab = .home
        openCompare(with: urlString)
        return true
    }

    private func inspectClipboardIfNeeded() {
        refreshRecentClipboardCandidate()

        guard isLoggedIn,
              clipboardCandidate == nil,
              let candidate = smartClipboardService.detectCandidate() else {
            return
        }

        recentClipboardCandidate = candidate
        clipboardCandidate = candidate
    }

    private func refreshRecentClipboardCandidate() {
        guard isLoggedIn else {
            recentClipboardCandidate = nil
            return
        }

        let latestCandidate = smartClipboardService.currentSupportedProductCandidate()
        if recentClipboardCandidate != latestCandidate {
            recentClipboardCandidate = latestCandidate
        }
    }

    private func openCompare(with urlString: String?) {
        guard shouldLaunchCompare(for: urlString) else {
            return
        }

        pendingCompareURL = urlString
        compareViewID = UUID()
    }

    private func openCompareUsingLatestAvailableURL(fallbackURL: String? = nil) {
        openCompare(with: latestCompareURL(fallbackURL: fallbackURL))
    }

    private func latestCompareURL(fallbackURL: String?) -> String? {
        if let candidate = smartClipboardService.currentSupportedProductCandidate() {
            recentClipboardCandidate = candidate
            clipboardCandidate = nil
            smartClipboardService.markHandled(candidate)
            return candidate.urlString
        }

        if let pendingURL = sharedURLStore.consumePendingProductURL() {
            return pendingURL
        }

        guard let fallbackURL = fallbackURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              ProductURLSupport.isSupportedProductURL(fallbackURL) else {
            return nil
        }

        return fallbackURL
    }

    private func shouldLaunchCompare(for urlString: String?) -> Bool {
        let key = urlString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "__empty_compare__"
        let now = Date()
        if lastCompareLaunchKey == key,
           now.timeIntervalSince(lastCompareLaunchDate) < 0.8 {
            return false
        }

        lastCompareLaunchKey = key
        lastCompareLaunchDate = now
        return true
    }
}

#if DEBUG
private enum ScreenshotCase: String, CaseIterable {
    case home
    case compare
    case compareMissingBasis
    case closetEmpty
    case closetList
    case addClosetEmpty
    case addClosetFilled
    case historyEmpty
    case historyList
    case recommend
    case my
    case result

    static var current: ScreenshotCase? {
        guard let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-fitmatchScreenshot"),
              ProcessInfo.processInfo.arguments.indices.contains(index + 1) else {
            return nil
        }
        return ScreenshotCase(rawValue: ProcessInfo.processInfo.arguments[index + 1])
    }
}

private struct ScreenshotShowcaseView: View {
    let screenshotCase: ScreenshotCase

    var body: some View {
        NavigationStack {
            Group {
                switch screenshotCase {
                case .home:
                    ScreenshotHomeView()
                case .compare:
                    ScreenshotCompareView(showsMissingBasis: false)
                case .compareMissingBasis:
                    ScreenshotCompareView(showsMissingBasis: true)
                case .closetEmpty:
                    ScreenshotClosetEmptyView()
                case .closetList:
                    ScreenshotClosetListView()
                case .addClosetEmpty:
                    ScreenshotAddClosetView(isFilled: false)
                case .addClosetFilled:
                    ScreenshotAddClosetView(isFilled: true)
                case .historyEmpty:
                    ScreenshotHistoryView(isEmpty: true)
                case .historyList:
                    ScreenshotHistoryView(isEmpty: false)
                case .recommend:
                    ScreenshotRecommendView()
                case .my:
                    ScreenshotMyView()
                case .result:
                    ScreenshotResultView()
                }
            }
        }
    }
}

private struct ScreenshotHomeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FIT MATCH")
                            .font(.largeTitle.weight(.black))
                        Text("Find Your Perfect Fit.")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "bell")
                        .font(.headline.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(Color(.systemBackground), in: Circle())
                }

                CardView(radius: 24, padding: 24, background: .black) {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack {
                            Image(systemName: "scalemass.fill")
                                .font(.system(size: 34, weight: .bold))
                            Spacer()
                            Text("COMPARE")
                                .font(.caption.weight(.bold))
                                .opacity(0.62)
                        }
                        .foregroundStyle(.white)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("새 상품 비교")
                                .font(.title.weight(.black))
                            Text("공유한 쇼핑몰 URL을 붙여넣고\n내게 맞는 사이즈를 찾아보세요.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        .foregroundStyle(.white)
                        Label("상품 비교 시작", systemImage: "link")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }

                Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                    GridRow {
                        SmallInfoCard(title: "내 옷장", value: "2개", systemImage: "tshirt") {
                            Divider()
                            Text("기준 옷")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("UNIQLO Daily Oxford Shirt")
                                .font(.subheadline.weight(.bold))
                        }
                        SmallInfoCard(title: "최근 비교", value: "3건", systemImage: "clock") {
                            Divider()
                            Text("유니온스튜디오 반팔티")
                                .font(.caption.weight(.semibold))
                            Text("XL · 87%")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SectionHeader(title: "추천", subtitle: "최근 비교 기반")
                CardView(radius: 24, padding: 18) {
                    ScreenshotRecommendationRow(title: "로그 헨리넥 크롭 반팔티", source: "무신사", size: "XL", score: "87%")
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct ScreenshotCompareView: View {
    let showsMissingBasis: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                FitMatchCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "상품 URL", subtitle: "쇼핑몰 URL을 분석해서 내 옷장 기준으로 바로 사이즈를 계산합니다.")
                        Text("https://www.musinsa.com/products/6364516")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(11)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        PrimaryButton(title: "비교하기", systemImage: "sparkles") {}

                        if showsMissingBasis {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("내 옷장에 이 상품과 같은 기준 옷이 없습니다. 어떤 옷과 비교할까요?", systemImage: "tshirt")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Label("비교할 옷 선택하기", systemImage: "list.bullet.rectangle")
                                    .font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                                    .background(.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .foregroundStyle(Color(.systemBackground))
                            }
                            .padding(14)
                            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct ScreenshotClosetEmptyView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image("EmptyCloset")
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 160)
            Text("옷장이 비었습니다.")
                .font(.title3.weight(.bold))
            Text("핏이 마음에 드는 옷을 먼저 추가해 주세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "plus")
                    .font(.title3.weight(.bold))
                    .frame(width: 42, height: 42)
                    .background(.primary, in: Circle())
                    .foregroundStyle(Color(.systemBackground))
            }
        }
    }
}

private struct ScreenshotClosetListView: View {
    var body: some View {
        List {
            ScreenshotClosetCard(title: "UNIQLO Daily Oxford Shirt", source: "유니클로 공식몰", meta: "남성 / 상의 / 셔츠 / L", isRepresentative: true)
            ScreenshotClosetCard(title: "MUSINSA STANDARD Favorite Hoodie", source: "직접 입력", meta: "공용 / 상의 / 후드 / L", isRepresentative: false)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "plus")
                    .font(.title3.weight(.bold))
                    .frame(width: 42, height: 42)
                    .background(.primary, in: Circle())
                    .foregroundStyle(Color(.systemBackground))
            }
        }
    }
}

private struct ScreenshotClosetCard: View {
    let title: String
    let source: String
    let meta: String
    let isRepresentative: Bool

    var body: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.headline.weight(.semibold))
                        Text("출처: \(source)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(meta)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Label(isRepresentative ? "기준 옷" : "기준 옷 설정", systemImage: isRepresentative ? "heart.fill" : "heart")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isRepresentative ? .red : .primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.primary.opacity(0.08), in: Capsule())
                    }
                }
                Text("어깨 48cm · 가슴단면 57cm · 총장 75cm · 소매 62cm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("상세 보기")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
    }
}

private struct ScreenshotAddClosetView: View {
    let isFilled: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("내 옷 추가")
                        .font(.title2.weight(.black))
                    Text("핏이 마음에 드는 옷의 정보를 저장합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ScreenshotFormCard(title: "상품 출처") {
                    ScreenshotFormInfoRow(title: "출처 유형", value: isFilled ? "공식몰" : "직접 입력")
                    ScreenshotFormInfoRow(title: "브랜드", value: isFilled ? "유니클로" : "브랜드 선택")
                }

                ScreenshotFormCard(title: "분류") {
                    ScreenshotFormInfoRow(title: "성별", value: isFilled ? "남성" : "남성")
                    ScreenshotFormInfoRow(title: "카테고리", value: "상의")
                    ScreenshotFormInfoRow(title: "세부 카테고리", value: isFilled ? "셔츠" : "민소매")
                }

                ScreenshotFormCard(title: "상품 정보") {
                    ScreenshotFormInfoRow(title: "상품명", value: isFilled ? "Daily Oxford Shirt" : "상품명 입력")
                }

                ScreenshotFormCard(title: "실측값", subtitle: "둘레가 아닌 단면 기준으로 입력합니다.") {
                    ForEach(["총장", "어깨너비", "가슴단면", "소매길이"], id: \.self) { title in
                        ScreenshotFormInfoRow(title: title, value: isFilled ? sampleValue(for: title) : "-")
                    }
                }

                ScreenshotFormCard(title: "핏 기록") {
                    ScreenshotFormInfoRow(title: "핏", value: "정핏")
                    ScreenshotFormInfoRow(title: "메모", value: isFilled ? "정핏에 가까운 셔츠 기준" : "핏 메모")
                }

                Text("저장하기")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(20)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("기준 옷")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sampleValue(for title: String) -> String {
        switch title {
        case "어깨너비": return "48"
        case "가슴단면": return "57"
        case "총장": return "75"
        default: return "62"
        }
    }
}

private struct ScreenshotFormCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: title, subtitle: subtitle)
                VStack(spacing: 10) {
                    content
                }
            }
        }
    }
}

private struct ScreenshotFormInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value.isEmpty ? "-" : value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(value.isEmpty || value == "-" ? .secondary : .primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ScreenshotHistoryView: View {
    let isEmpty: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
            if isEmpty {
                FitMatchCard {
                    ContentUnavailableView("상품 비교 기록이 없습니다", systemImage: "clock.arrow.circlepath", description: Text("상품을 비교하면 비교 결과가 저장됩니다."))
                }
            } else {
                ScreenshotHistoryCard(title: "유니온스튜디오 로그 헨리넥 크롭 반팔티", source: "무신사", size: "XL", score: "87%")
                ScreenshotHistoryCard(title: "MUSINSA STANDARD Relaxed Sweatshirt", source: "무신사", size: "L", score: "82%")
            }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct ScreenshotHistoryCard: View {
    let title: String
    let source: String
    let size: String
    let score: String

    var body: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.headline.weight(.bold))
                        Text("출처: \(source)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(score)
                        .font(.title3.weight(.black))
                }
                HStack {
                    Label(size, systemImage: "tag.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("오늘")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Text("쇼핑몰 이동")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.primary, in: Capsule())
                    Text("다시 비교")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.primary.opacity(0.08), in: Capsule())
                }
            }
        }
    }
}

private struct ScreenshotRecommendView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ScreenshotRecommendationCard(title: "유니온스튜디오 로그 헨리넥 크롭 반팔티", source: "무신사", size: "XL", score: "87%")
                ScreenshotRecommendationCard(title: "MUSINSA STANDARD Relaxed Sweatshirt", source: "무신사", size: "L", score: "82%")
                Text("선호 핏: 정핏")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct ScreenshotRecommendationCard: View {
    let title: String
    let source: String
    let size: String
    let score: String

    var body: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.headline.weight(.bold))
                        Text("출처: \(source)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(score)
                        .font(.title3.weight(.black))
                }
                HStack {
                    Label(size, systemImage: "tag.fill")
                        .font(.headline)
                    Spacer()
                    Text("구매")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.primary, in: Capsule())
                }
            }
        }
    }
}

private struct ScreenshotMyView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                FitMatchCard {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 54))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("FitMatch User")
                                .font(.title3.weight(.bold))
                            Text("내 옷장 기반 사이즈 추천")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                FitMatchCard {
                    VStack(spacing: 0) {
                        ForEach(["내 정보", "내옷장관리", "앱설정", "로그아웃"], id: \.self) { title in
                            HStack {
                                Label(title, systemImage: icon(for: title))
                                    .font(.body.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 14)
                            if title != "로그아웃" {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("My")
    }

    private func icon(for title: String) -> String {
        switch title {
        case "내 정보": return "person.circle"
        case "내옷장관리": return "tshirt"
        case "앱설정": return "gearshape"
        default: return "rectangle.portrait.and.arrow.right"
        }
    }
}

private struct ScreenshotResultView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("유니온스튜디오 로그 헨리넥 크롭 반팔티")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .lastTextBaseline) {
                        Text("XL")
                            .font(.system(size: 58, weight: .black))
                        Spacer()
                        Text("87%")
                            .font(.title.weight(.black))
                    }
                    Text("추천 사이즈는 XL입니다")
                        .font(.title3.weight(.black))
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                FitMatchCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "비교 기준", subtitle: "기준 옷과 추천 상품 실측 차이를 함께 확인합니다.")
                        ScreenshotInfoRow(title: "기준 옷", value: "UNIQLO Daily Oxford Shirt")
                        ScreenshotInfoRow(title: "기준 옷 출처", value: "유니클로 공식몰")
                        ScreenshotInfoRow(title: "상품 출처", value: "무신사")
                        ScreenshotInfoRow(title: "비교 방식", value: "같은 대분류 기준 비교")
                        Divider()
                        SectionHeader(title: "상품 실측(차이)", subtitle: "괄호 안 값은 기준 옷과의 차이입니다.")
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
                            GridRow {
                                ScreenshotMeasure(title: "어깨", value: "52cm", diff: "+4cm")
                                ScreenshotMeasure(title: "가슴단면", value: "58.5cm", diff: "+1.5cm")
                            }
                            GridRow {
                                ScreenshotMeasure(title: "총장", value: "65.2cm", diff: "-9.8cm")
                                ScreenshotMeasure(title: "소매", value: "22.6cm", diff: "-39.4cm")
                            }
                        }
                    }
                }

                FitMatchCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "내 옷장의 다른 옷과 비교하기")
                        Label("같은 대분류 기준 비교", systemImage: "square.grid.2x2")
                            .font(.headline.weight(.bold))
                        PrimaryButton(title: "다른 옷 선택", systemImage: "tshirt") {}
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("추천 결과")
    }
}

private struct ScreenshotRecommendationRow: View {
    let title: String
    let source: String
    let size: String
    let score: String

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text("출처: \(source)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(size)
                    .font(.title3.weight(.black))
                Text(score)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ScreenshotInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

private struct ScreenshotMeasure: View {
    let title: String
    let value: String
    let diff: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value) (\(diff))")
                .font(.headline.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
#endif

private struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedTab: AppTab
    @Binding var clipboardCandidate: SmartClipboardCandidate?
    let compareURL: String?
    let onCompareURLConsumed: () -> Void
    let onClipboardCandidateHandled: (SmartClipboardCandidate, Bool) -> Void
    let recentClipboardCandidate: SmartClipboardCandidate?
    let histories: [RecommendationHistory]
    let onRecompare: (String) -> Void
    let onStartCompareLatestURL: () -> Void
    let onRefreshClipboardCandidate: () -> Void
    let onLogout: () -> Void
    let compareViewID: UUID
    @State private var activeSheet: MainActiveSheet?
    @StateObject private var tabBarVisibilityController = TabBarVisibilityController()

    var body: some View {
        currentTabContent
        .environmentObject(tabBarVisibilityController)
        .overlay(alignment: .bottom) {
            bottomNavigationOverlay
        }
        .tint(.primary)
        .onChange(of: selectedTab) { _, _ in
            tabBarVisibilityController.release(tab: selectedTab, reason: .scrolling, source: "tab changed")
        }
        .onChange(of: clipboardCandidate) { _, newValue in
            if let newValue {
                presentSheet(.clipboard(newValue))
            }
        }
        .onChange(of: compareViewID) { _, _ in
            presentCompareFlow(initialURL: compareURL)
            onCompareURLConsumed()
        }
        .sheet(item: $activeSheet, onDismiss: {
            print("[MainTabView] activeSheet dismissed")
            tabBarVisibilityController.release(tab: selectedTab, reason: .modalFlow, source: "sheet dismissed")
        }) { sheet in
            switch sheet {
            case .newTask:
                NewTaskSheet(
                    onCompare: {
                        presentCompareFlowFromNewTask(initialURL: nil)
                    },
                    onAddCloset: {
                        presentClosetAddMethodFromNewTask()
                    }
                )
                .presentationDetents([.height(270)])
                .presentationDragIndicator(.visible)
            case .compareFlow(let request):
                CompareFlowSheet(
                    initialURL: request.initialURL,
                    recentClipboardCandidate: recentClipboardCandidate
                )
                .presentationDetents([.height(640), .large])
                .presentationDragIndicator(.visible)
            case .clipboard(let candidate):
                SmartClipboardPromptSheet(
                    candidate: candidate,
                    matchingHistory: matchingHistory(for: candidate),
                    onCompare: { shouldMuteToday in
                        onClipboardCandidateHandled(candidate, shouldMuteToday)
                        clipboardCandidate = nil
                        presentCompareFlow(initialURL: candidate.urlString)
                    },
                    onLater: { shouldMuteToday in
                        onClipboardCandidateHandled(candidate, shouldMuteToday)
                        clipboardCandidate = nil
                        dismissSheet()
                    }
                )
                .presentationDetents([.height(390)])
                .presentationDragIndicator(.visible)
            case .closetAddMethod:
                AddClosetMethodSheet(
                    onLink: {
                        presentClosetLinkRegistrationFromNewTask()
                    },
                    onManual: {
                        presentManualClosetAddFromNewTask()
                    }
                )
                .presentationDetents([.height(290)])
                .presentationDragIndicator(.visible)
            case .closetLinkRegistration:
                NavigationStack {
                    LinkClosetRegistrationView()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            case .manualClosetAdd:
                NavigationStack {
                    AddClosetItemView { item in
                        modelContext.insert(item)
                        do {
                            try modelContext.save()
                        } catch {
                            print("[MainTabView] manual closet add failed: \(error.localizedDescription)")
                        }
                    }
                }
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var bottomNavigationOverlay: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.45)

            FitMatchBottomNavigationBar(
                selectedTab: $selectedTab,
                onStartCompare: {
                    presentSheet(.newTask)
                }
            )
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .offset(y: tabBarVisibilityController.isVisible ? 0 : 140)
        .opacity(tabBarVisibilityController.isVisible ? 1 : 0)
        .allowsHitTesting(tabBarVisibilityController.isVisible)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: tabBarVisibilityController.isVisible)
    }

    @ViewBuilder
    private var currentTabContent: some View {
        switch selectedTab {
        case .home, .compare:
            NavigationStack {
                HomeView(
                    recentClipboardCandidate: recentClipboardCandidate,
                    onStartCompare: {
                        presentCompareFlow(initialURL: nil)
                    },
                    onStartCompareWithURL: { urlString in
                        presentCompareFlow(initialURL: urlString)
                    },
                    onStartCompareLatestURL: onStartCompareLatestURL,
                    onRefreshClipboardCandidate: onRefreshClipboardCandidate,
                    onOpenHistory: {
                        selectedTab = .history
                    },
                    onRecompare: onRecompare,
                    onLogout: onLogout
                )
            }
        case .history:
            NavigationStack {
                RecommendationHistoryView(
                    onRecompare: onRecompare,
                    onStartCompare: {
                        presentCompareFlow(initialURL: nil)
                    },
                    onLogout: onLogout
                )
            }
        case .recommend:
            NavigationStack {
                RecommendView(onLogout: onLogout)
            }
        case .my:
            NavigationStack {
                MyClosetView(onLogout: onLogout)
            }
        }
    }

    private func presentSheet(_ sheet: MainActiveSheet) {
        print("[MainTabView] activeSheet -> \(sheet.logName)")
        tabBarVisibilityController.hide(tab: selectedTab, reason: .modalFlow, source: sheet.logName)
        activeSheet = nil
        DispatchQueue.main.async {
            tabBarVisibilityController.hide(tab: selectedTab, reason: .modalFlow, source: sheet.logName)
            activeSheet = sheet
        }
    }

    private func dismissSheet() {
        print("[MainTabView] activeSheet -> nil")
        activeSheet = nil
        tabBarVisibilityController.release(tab: selectedTab, reason: .modalFlow, source: "dismissSheet")
    }

    private func presentCompareFlow(initialURL: String?) {
        print("[MainTabView] activeSheet -> compareFlow, initialURL: \(initialURL ?? "nil")")
        tabBarVisibilityController.hide(tab: selectedTab, reason: .modalFlow, source: "compareFlow")
        activeSheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            tabBarVisibilityController.hide(tab: selectedTab, reason: .modalFlow, source: "compareFlow")
            activeSheet = .compareFlow(CompareFlowRequest(initialURL: initialURL))
        }
    }

    private func presentCompareFlowFromNewTask(initialURL: String?) {
        activeSheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            presentCompareFlow(initialURL: initialURL)
        }
    }

    private func presentClosetAddMethodFromNewTask() {
        activeSheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            presentSheet(.closetAddMethod)
        }
    }

    private func presentClosetLinkRegistrationFromNewTask() {
        activeSheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            presentSheet(.closetLinkRegistration)
        }
    }

    private func presentManualClosetAddFromNewTask() {
        activeSheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            presentSheet(.manualClosetAdd)
        }
    }

    private func matchingHistory(for candidate: SmartClipboardCandidate) -> RecommendationHistory? {
        histories.first { history in
            history.product.sourceURLString == candidate.urlString
        }
    }
}

private enum MainActiveSheet: Identifiable {
    case newTask
    case compareFlow(CompareFlowRequest)
    case clipboard(SmartClipboardCandidate)
    case closetAddMethod
    case closetLinkRegistration
    case manualClosetAdd

    var id: String {
        switch self {
        case .newTask:
            return "newTask"
        case .compareFlow(let request):
            return "compareFlow-\(request.id)"
        case .clipboard(let candidate):
            return "clipboard-\(candidate.id)"
        case .closetAddMethod:
            return "closetAddMethod"
        case .closetLinkRegistration:
            return "closetLinkRegistration"
        case .manualClosetAdd:
            return "manualClosetAdd"
        }
    }

    var logName: String {
        switch self {
        case .newTask:
            return "newTask"
        case .compareFlow:
            return "compareFlow"
        case .clipboard:
            return "clipboard"
        case .closetAddMethod:
            return "closetAddMethod"
        case .closetLinkRegistration:
            return "closetLinkRegistration"
        case .manualClosetAdd:
            return "manualClosetAdd"
        }
    }
}

private struct CompareFlowRequest: Identifiable {
    let id = UUID()
    let initialURL: String?
}

private struct NewTaskSheet: View {
    let onCompare: () -> Void
    let onAddCloset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("새 작업")
                    .font(.title2.weight(.black))
                    .foregroundStyle(.primary)
            }

            VStack(spacing: 12) {
                NewTaskLargeButton(title: "상품 비교", systemImage: "sparkles") {
                    onCompare()
                }
                NewTaskLargeButton(title: "내 옷 추가", systemImage: "tshirt") {
                    onAddCloset()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Color(.systemGroupedBackground))
    }
}

private struct NewTaskLargeButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(width: 40, height: 40)
                    .background(Color.primary, in: Circle())

                Text(title)
                    .font(.headline.weight(.black))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .frame(height: 72)
            .padding(.horizontal, 16)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct FitMatchBottomNavigationBar: View {
    @Binding var selectedTab: AppTab
    let onStartCompare: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            BottomNavigationItem(
                title: "홈",
                systemImage: "house.fill",
                isSelected: selectedTab == .home
            ) {
                selectedTab = .home
            }

            BottomNavigationItem(
                title: "기록",
                systemImage: "clock.fill",
                isSelected: selectedTab == .history
            ) {
                selectedTab = .history
            }

            Button(action: onStartCompare) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.black, in: Circle())
                    .shadow(color: Color.black.opacity(0.14), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("새 작업")

            BottomNavigationItem(
                title: "추천",
                systemImage: "sparkles",
                isSelected: selectedTab == .recommend
            ) {
                selectedTab = .recommend
            }

            BottomNavigationItem(
                title: "내 옷장",
                systemImage: "tshirt.fill",
                isSelected: selectedTab == .my
            ) {
                selectedTab = .my
            }
        }
        .frame(height: 58)
    }
}

private struct BottomNavigationItem: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SplashView: View {
    var body: some View {
        GeometryReader { proxy in
            Image("SplashBackground")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .ignoresSafeArea()
                .background(Color.black)
        }
        .ignoresSafeArea()
    }
}

private struct LoginView: View {
    let onLogin: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 10) {
                Text("FIT MATCH")
                    .font(.system(size: 44, weight: .black))
                    .tracking(4)
                Text("Find Your Perfect Fit")
                    .font(.title3.weight(.semibold))
            }

            VStack(spacing: 12) {
                LoginButton(title: "Apple로 계속하기", systemImage: "apple.logo", action: onLogin)
                LoginButton(title: "Google로 계속하기", systemImage: "g.circle", action: onLogin)
                LoginButton(title: "Kakao로 계속하기", systemImage: "message.fill", action: onLogin)
                LoginButton(title: "Naver로 계속하기", systemImage: "n.circle", action: onLogin)
            }
            .padding(.horizontal, 24)
            Spacer()
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct LoginButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
