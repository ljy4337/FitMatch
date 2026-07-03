import SwiftUI
import SwiftData

struct ShoppingProductFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BaselineFit.createdAt, order: .reverse) private var baselineFits: [BaselineFit]
    @StateObject private var viewModel = ShoppingProductViewModel()

    var body: some View {
        Form {
            Section("쇼핑 상품") {
                TextField("브랜드", text: $viewModel.brand)
                TextField("제품명", text: $viewModel.productName)
                Picker("카테고리", selection: $viewModel.category) {
                    ForEach(ClothingCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
            }

            Section {
                ForEach($viewModel.sizeOptions) { $option in
                    ClothingSizeEditor(
                        option: $option,
                        canRemove: viewModel.sizeOptions.count > 1
                    ) {
                        viewModel.removeSizeOption(option)
                    }
                }

                Button {
                    viewModel.addSizeOption()
                } label: {
                    Label("사이즈 추가", systemImage: "plus.circle")
                }
            } header: {
                Text("사이즈별 실측값")
            } footer: {
                Text("단위는 cm입니다. 입력된 사이즈 중 내 옷장과 총 차이가 가장 작은 사이즈를 추천합니다.")
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    if let record = viewModel.calculateRecommendation(baselineFits: baselineFits) {
                        modelContext.insert(record.shoppingProduct)
                        modelContext.insert(record)
                    }
                } label: {
                    Label("추천 사이즈 계산", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("쇼핑 상품 추가")
        .sheet(item: $viewModel.recommendation) { result in
            NavigationStack {
                RecommendationResultView(result: result)
            }
        }
    }
}

private struct ClothingSizeEditor: View {
    @Binding var option: ClothingSizeForm
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("사이즈명", text: $option.sizeName)
                    .font(.headline)

                if canRemove {
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }

            MeasurementField(title: "어깨", placeholder: "48", value: $option.shoulder)
            MeasurementField(title: "가슴", placeholder: "56", value: $option.chest)
            MeasurementField(title: "총장", placeholder: "70", value: $option.totalLength)
            MeasurementField(title: "소매", placeholder: "62", value: $option.sleeveLength)
        }
        .padding(.vertical, 4)
    }
}
