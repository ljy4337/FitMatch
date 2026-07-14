import SwiftUI

struct RecommendView: View {
    var onLogout: (() -> Void)?
    @State private var isTopChromeVisible = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CollapsibleTopChrome(isVisible: isTopChromeVisible) {
                    FitMatchNavigationHeader(onLogout: onLogout)
                }

                CardView(radius: 24, padding: 24) {
                    VStack(alignment: .center, spacing: 22) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(Color(.systemBackground))
                            .frame(width: 64, height: 64)
                            .background(Color.primary, in: Circle())

                        VStack(alignment: .center, spacing: 8) {
                            Text("추천 서비스 준비중")
                                .font(.title2.weight(.black))
                                .foregroundStyle(.primary)
                            Text("내 옷장과 비교 기록이 쌓이면\n나에게 맞는 상품을 추천할 예정입니다.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "clock")
                                .font(.caption.weight(.bold))
                            Text("상품추가 준비중")
                                .font(.caption.weight(.black))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                    }
                    .frame(maxWidth: .infinity)
                }

                CardView(radius: 20, padding: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "추천 기준", subtitle: "지금은 추천 데이터 수집 단계입니다.")
                        Divider()
                        RecommendPreviewRow(title: "내 기준 옷", subtitle: "카테고리별 기준 옷을 우선 반영", systemImage: "tshirt")
                        RecommendPreviewRow(title: "비교 기록", subtitle: "최근 본 상품과 핏 매칭률 활용", systemImage: "clock")
                        RecommendPreviewRow(title: "선호 브랜드", subtitle: "브랜드별 실측 차이를 누적 분석", systemImage: "tag")
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 112)
        }
        .background(Color(.systemGroupedBackground))
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isTopChromeVisible)
        .hidesBottomTabBarOnScroll(tab: .recommend, topChrome: $isTopChromeVisible)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct RecommendPreviewRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 30, height: 30)
                .background(.primary.opacity(0.06), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 6)
    }
}
