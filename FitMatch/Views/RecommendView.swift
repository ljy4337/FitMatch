import SwiftUI

struct RecommendView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image("FitMatchWordmark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.primary)
                    .frame(width: 138, height: 32, alignment: .leading)

                CardView(radius: 24, padding: 22) {
                    VStack(alignment: .leading, spacing: 22) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 34, weight: .semibold))
                            .frame(width: 58, height: 58)
                            .background(.primary.opacity(0.06), in: Circle())

                        VStack(alignment: .leading, spacing: 8) {
                            Text("추천 서비스 준비중")
                                .font(.title2.weight(.black))
                                .foregroundStyle(.primary)
                            Text("기준 옷을 많이 등록할수록\n더 정확한 추천을 제공합니다.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineSpacing(3)
                        }

                        Text("Coming Soon")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                    }
                }

                CardView(radius: 20, padding: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "앞으로 제공될 추천", subtitle: "내 옷장, 비교 기록, 선호 핏을 기반으로 확장합니다.")
                        Divider()
                        RecommendPreviewRow(title: "내 기준 옷과 가까운 상품", systemImage: "tshirt")
                        RecommendPreviewRow(title: "선호 브랜드 신상품", systemImage: "tag")
                        RecommendPreviewRow(title: "Fit Confidence 높은 상품", systemImage: "chart.bar")
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 112)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RecommendPreviewRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 30, height: 30)
                .background(.primary.opacity(0.06), in: Circle())
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 6)
    }
}
