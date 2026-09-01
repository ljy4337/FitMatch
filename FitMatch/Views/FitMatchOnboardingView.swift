import SwiftUI
import SwiftData

struct FitMatchOnboardingView: View {
    @Environment(\.modelContext) private var modelContext

    let onFinish: () -> Void

    @State private var selectedPage = 0
    @State private var registrationRoute: OnboardingRegistrationRoute?

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let initialPage: Int
        if let marker = arguments.firstIndex(of: "-fitmatchOnboardingInitialPage"),
           arguments.indices.contains(marker + 1),
           let requestedPage = Int(arguments[marker + 1]) {
            initialPage = max(0, min(3, requestedPage))
        } else {
            initialPage = 0
        }
        _selectedPage = State(initialValue: initialPage)
        #endif
    }

    private let pages = [
        FitMatchOnboardingPage(
            title: "내 옷이 비교 기준이 돼요",
            description: "체형을 재는 대신, 내가 실제로 잘 입는 옷의 실측을 사이즈 선택 기준으로 사용해요.",
            kind: .referenceGarment
        ),
        FitMatchOnboardingPage(
            title: "상품 실측을 불러와요",
            description: "내 옷을 등록하고 사고 싶은 상품을 불러오면, 모든 사이즈의 공통 실측을 비교해요.",
            kind: .howItWorks
        ),
        FitMatchOnboardingPage(
            title: "가장 비슷한 사이즈를 찾아요",
            description: "기준옷이 있으면 우선 자동 비교하고, 없다면 같은 카테고리의 내 옷을 직접 선택해요.",
            kind: .referenceSelection
        )
    ]

    private var pageCount: Int { pages.count + 1 }
    private var isRegistrationPage: Bool { selectedPage == pages.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(isRegistrationPage ? "나중에 등록하기" : "건너뛰기") {
                    onFinish()
                }
                .accessibilityIdentifier(isRegistrationPage ? "onboarding.later.top" : "onboarding.skip")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            TabView(selection: $selectedPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    onboardingPage(page)
                        .tag(index)
                }

                registrationPage
                    .tag(pages.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .layoutPriority(-1)

            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == selectedPage ? Color.primary : Color.secondary.opacity(0.25))
                        .frame(width: index == selectedPage ? 22 : 8, height: 8)
                        .animation(.easeOut(duration: 0.18), value: selectedPage)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("총 \(pageCount)페이지 중 \(selectedPage + 1)페이지")
            .padding(.bottom, 24)
            .layoutPriority(1)

            if isRegistrationPage {
                Button("나중에 등록하기") {
                    onFinish()
                }
                .accessibilityIdentifier("onboarding.later")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
                .layoutPriority(1)
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedPage += 1
                    }
                } label: {
                    Text("다음")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color(.systemBackground))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.primary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .accessibilityIdentifier("onboarding.next")
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
                .layoutPriority(1)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .sheet(item: $registrationRoute) { route in
            switch route {
            case .shoppingLink:
                NavigationStack {
                    LinkClosetRegistrationView(prefersRepresentativeByDefault: true) {
                        finishAfterRegistration()
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            case .manual:
                NavigationStack {
                    AddClosetItemView(
                        prefillCategory: usesUITestFixtures ? .top : nil,
                        prefillDetailCategory: usesUITestFixtures ? .shortSleeve : nil,
                        prefillGender: usesUITestFixtures ? .unisex : nil,
                        prefillSourceOption: usesUITestFixtures ? .manual : nil,
                        prefillBrand: usesUITestFixtures ? "온보딩 직접등록 브랜드" : nil,
                        prefillProductName: usesUITestFixtures ? "온보딩 직접등록 기준옷" : nil,
                        prefersRepresentativeByDefault: true
                    ) { item in
                        modelContext.insert(item)
                        do {
                            try modelContext.save()
                            finishAfterRegistration()
                            return true
                        } catch {
                            modelContext.rollback()
                            return false
                        }
                    }
                }
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func onboardingPage(_ page: FitMatchOnboardingPage) -> some View {
        ScrollView {
            VStack(spacing: page.kind == .referenceSelection ? 16 : 24) {
                Text(page.title)
                    .font(.largeTitle.weight(.black))
                    .multilineTextAlignment(.center)
                Text(page.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                pageVisual(for: page.kind)
            }
            .padding(.horizontal, 24)
            .padding(.top, page.kind == .referenceSelection ? 12 : 26)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func pageVisual(for kind: FitMatchOnboardingPage.Kind) -> some View {
        switch kind {
        case .referenceGarment:
            referenceGarmentVisual
        case .howItWorks:
            howItWorksVisual
        case .referenceSelection:
            referenceSelectionVisual
        }
    }

    private var referenceGarmentVisual: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 18, y: 8)

            Image(systemName: "tshirt.fill")
                .font(.system(size: 104, weight: .semibold))
                .foregroundStyle(.primary)

            measurementChip("어깨 53", alignment: .topTrailing)
            measurementChip("가슴 64", alignment: .leading)
            measurementChip("총장 76", alignment: .bottomTrailing)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 290)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("기준옷 실측 예시, 어깨 53, 가슴 64, 총장 76센티미터")
    }

    private func measurementChip(_ title: String, alignment: Alignment) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(.primary.opacity(0.08)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding(22)
    }

    private var howItWorksVisual: some View {
        VStack(spacing: 10) {
            onboardingStep(
                number: 1,
                title: "잘 맞는 내 옷 등록",
                description: "상품 링크 또는 직접 실측으로 등록",
                systemImage: "tshirt"
            )
            onboardingStep(
                number: 2,
                title: "사고 싶은 상품 불러오기",
                description: "무신사·유니클로·ZARA 링크를 공유하거나 입력",
                systemImage: "link"
            )
            onboardingStep(
                number: 3,
                title: "가까운 사이즈 확인",
                description: "공통 실측과 부위별 차이를 한눈에 확인",
                systemImage: "checkmark.circle"
            )
        }
    }

    private func onboardingStep(
        number: Int,
        title: String,
        description: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(.headline.weight(.black))
                .foregroundStyle(Color(.systemBackground))
                .frame(width: 38, height: 38)
                .background(Color.primary, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.bold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var referenceSelectionVisual: some View {
        VStack(spacing: 12) {
            comparisonRouteCard(
                badge: "기준옷이 있을 때",
                title: "기준옷과 우선 자동 비교",
                description: "사고 싶은 상품과 같은 카테고리의 기준옷을 찾아 바로 비교해요.",
                systemImage: "bolt.fill",
                emphasized: true
            )

            comparisonRouteCard(
                badge: "기준옷이 없을 때",
                title: "내가 비교할 옷을 직접 선택",
                description: "같은 카테고리의 내 옷 목록을 보여드리고, 원하는 비교 대상을 선택할 수 있어요.",
                systemImage: "hand.tap.fill",
                emphasized: false
            )

            Label("선택된 옷과 상품의 모든 사이즈를 실측으로 비교해요.", systemImage: "ruler")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.top, 2)
        }
    }

    private func comparisonRouteCard(
        badge: String,
        title: String,
        description: String,
        systemImage: String,
        emphasized: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.bold))
                .foregroundStyle(emphasized ? Color(.systemBackground) : .primary)
                .frame(width: 38, height: 38)
                .background(emphasized ? Color.primary : Color.primary.opacity(0.07), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(badge)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline.weight(.black))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(emphasized ? Color.primary : Color.primary.opacity(0.08), lineWidth: emphasized ? 1.5 : 1)
        }
    }

    private var registrationPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("잘 맞는 내 옷을 하나 등록해보세요")
                        .font(.largeTitle.weight(.black))
                    Text("새 옷을 살 때 내 옷과 비교해 가장 비슷한 사이즈를 찾아드려요.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                }

                registrationCard(
                    title: "상품 링크로 등록",
                    description: "무신사·유니클로·ZARA에서 가지고 있는 상품의 링크를 복사해 등록할 수 있어요.",
                    supportText: "지원 쇼핑몰  MUSINSA · UNIQLO · ZARA",
                    buttonTitle: "상품 링크로 등록",
                    systemImage: "link"
                ) {
                    registrationRoute = .shoppingLink
                }
                .accessibilityIdentifier("onboarding.shoppingLink")

                registrationCard(
                    title: "직접 등록",
                    description: "온라인에서 찾을 수 없는 옷은 가지고 있는 옷의 실측을 직접 입력할 수 있어요.",
                    supportText: "신체 치수가 아닌 의류 실측을 입력해요",
                    buttonTitle: "직접 등록",
                    systemImage: "ruler"
                ) {
                    registrationRoute = .manual
                }
                .accessibilityIdentifier("onboarding.manual")
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 20)
        }
    }

    private func registrationCard(
        title: String,
        description: String,
        supportText: String,
        buttonTitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.black))
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(supportText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Button(buttonTitle, action: action)
                .font(.headline.weight(.bold))
                .foregroundStyle(Color(.systemBackground))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .buttonStyle(.plain)
        }
        .padding(18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func finishAfterRegistration() {
        registrationRoute = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onFinish()
        }
    }

    private var usesUITestFixtures: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-fitmatchOnboardingFixtures")
        #else
        false
        #endif
    }
}

private struct FitMatchOnboardingPage {
    enum Kind: Equatable {
        case referenceGarment
        case howItWorks
        case referenceSelection
    }

    let title: String
    let description: String
    let kind: Kind
}

private enum OnboardingRegistrationRoute: String, Identifiable {
    case shoppingLink
    case manual

    var id: String { rawValue }
}
