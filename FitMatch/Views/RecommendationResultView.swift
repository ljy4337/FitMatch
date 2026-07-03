import SwiftUI

struct RecommendationResultView: View {
    let result: RecommendationRecord

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(result.shoppingProduct.productName)
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text(result.recommendedSize.name)
                        .font(.system(size: 48, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(result.reasonText)
                        .font(.body)
                }
                .padding(.vertical, 8)
            } header: {
                Text("추천 사이즈")
            }

            Section("비교 기준") {
                LabeledContent("기준 옷", value: result.baselineFit.displayName)
                LabeledContent("기준 사이즈", value: result.baselineFit.size)
                LabeledContent("카테고리", value: result.baselineFit.category.rawValue)
                LabeledContent("총 차이", value: result.totalDifference.cmText)
            }

            Section("실측 차이") {
                LabeledContent("어깨", value: result.measurementDifferences.shoulder.cmText)
                LabeledContent("가슴", value: result.measurementDifferences.chest.cmText)
                LabeledContent("총장", value: result.measurementDifferences.totalLength.cmText)
                LabeledContent("소매", value: result.measurementDifferences.sleeveLength.cmText)
            }

            Section("추천 상품 실측") {
                LabeledContent("어깨", value: result.recommendedSize.measurements.shoulder.cmText)
                LabeledContent("가슴", value: result.recommendedSize.measurements.chest.cmText)
                LabeledContent("총장", value: result.recommendedSize.measurements.totalLength.cmText)
                LabeledContent("소매", value: result.recommendedSize.measurements.sleeveLength.cmText)
            }
        }
        .navigationTitle("추천 결과")
    }
}
