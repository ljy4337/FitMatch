import SwiftUI
import SwiftData

struct FitMatchOnboardingView: View {
    @Environment(\.modelContext) private var modelContext

    let onFinish: () -> Void

    @State private var selectedPage = 0
    @State private var registrationRoute: OnboardingRegistrationRoute?

    private let pages = [
        FitMatchOnboardingPage(
            title: "내 옷이 비교 기준이 돼요",
            description: "FitMatch는 몸이나 취향을 추측하지 않고, 내가 실제로 잘 입는 옷을 기준으로 비교해요.",
            systemImage: "tshirt.fill"
        ),
        FitMatchOnboardingPage(
            title: "상품 실측을 불러와요",
            description: "무신사·유니클로 상품 링크를 입력하면 사이즈별 실측 정보를 확인할 수 있어요.",
            systemImage: "link"
        ),
        FitMatchOnboardingPage(
            title: "가장 비슷한 사이즈를 찾아요",
            description: "기준 옷과 쇼핑 상품의 공통 실측을 비교해 가장 가까운 사이즈와 부위별 차이를 보여드려요.",
            systemImage: "ruler.fill"
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
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .sheet(item: $registrationRoute) { route in
            switch route {
            case .shoppingLink:
                NavigationStack {
                    LinkClosetRegistrationView {
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
                        prefillProductName: usesUITestFixtures ? "온보딩 직접등록 기준옷" : nil
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
        VStack(spacing: 30) {
            Spacer(minLength: 24)

            ZStack {
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 22, y: 10)
                Circle()
                    .fill(.primary.opacity(0.06))
                    .frame(width: 150, height: 150)
                Image(systemName: page.systemImage)
                    .font(.system(size: 68, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 260, height: 260)
            .accessibilityHidden(true)

            VStack(spacing: 14) {
                Text(page.title)
                    .font(.largeTitle.weight(.black))
                    .multilineTextAlignment(.center)
                Text(page.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 30)

            Spacer(minLength: 20)
        }
    }

    private var registrationPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("잘 맞는 옷 하나를 등록해보세요")
                        .font(.largeTitle.weight(.black))
                    Text("새 옷을 살 때 등록한 내 옷과 비교해 가장 비슷한 사이즈를 찾아드려요.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                }

                registrationCard(
                    title: "쇼핑몰 상품으로 등록",
                    description: "무신사·유니클로에서 가지고 있는 상품의 링크를 복사해 등록할 수 있어요.",
                    supportText: "지원 쇼핑몰  MUSINSA · UNIQLO",
                    buttonTitle: "등록하기",
                    systemImage: "link"
                ) {
                    registrationRoute = .shoppingLink
                }
                .accessibilityIdentifier("onboarding.shoppingLink")

                registrationCard(
                    title: "직접 등록",
                    description: "온라인에서 찾을 수 없는 옷은 가지고 있는 옷의 실측을 직접 입력할 수 있어요.",
                    supportText: "신체 치수가 아닌 의류 실측을 입력해요",
                    buttonTitle: "직접 입력하기",
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
    let title: String
    let description: String
    let systemImage: String
}

private enum OnboardingRegistrationRoute: String, Identifiable {
    case shoppingLink
    case manual

    var id: String { rawValue }
}
