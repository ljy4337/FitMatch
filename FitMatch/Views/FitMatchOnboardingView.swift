import SwiftUI

struct FitMatchOnboardingView: View {
    let onFinish: () -> Void

    @State private var selectedPage = 0

    private let pages = [
        FitMatchOnboardingPage(
            title: "내 옷 등록하기",
            description: "평소 핏을 잘 알고 있는 옷을 내 옷장에 등록해 주세요.",
            systemImage: "tshirt.fill"
        ),
        FitMatchOnboardingPage(
            title: "상품 가져오기",
            description: "쇼핑몰에서 상품을 핏매치로 공유하거나 상품 링크를 입력하세요.",
            systemImage: "link"
        ),
        FitMatchOnboardingPage(
            title: "자동으로 비교하기",
            description: "핏매치가 상품 정보와 실측을 확인해 가장 적합한 내 옷과 비교해요. 기준 옷이 없어도 사용할 수 있어요.",
            systemImage: "sparkles"
        ),
        FitMatchOnboardingPage(
            title: "추천 사이즈 확인하기",
            description: "추천 사이즈와 내 옷보다 크거나 작은 부분을 확인해 보세요.",
            systemImage: "ruler.fill"
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("건너뛰기") {
                    onFinish()
                }
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
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == selectedPage ? Color.primary : Color.secondary.opacity(0.25))
                        .frame(width: index == selectedPage ? 22 : 8, height: 8)
                        .animation(.easeOut(duration: 0.18), value: selectedPage)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("총 \(pages.count)페이지 중 \(selectedPage + 1)페이지")
            .padding(.bottom, 24)

            Button {
                if selectedPage == pages.count - 1 {
                    onFinish()
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedPage += 1
                    }
                }
            } label: {
                Text(selectedPage == pages.count - 1 ? "핏매치 시작하기" : "다음")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
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
}

private struct FitMatchOnboardingPage {
    let title: String
    let description: String
    let systemImage: String
}
