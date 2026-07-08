import SwiftUI

struct RecommendView: View {
    var body: some View {
        EmptyRecommendView()
            .background(Color(.systemBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .hidesTabBarOnScroll()
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
