import SwiftUI

struct AddClosetItemView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AddClosetItemViewModel

    let onSave: (ClosetItem) -> Void

    init(item: ClosetItem? = nil, onSave: @escaping (ClosetItem) -> Void) {
        _viewModel = StateObject(wrappedValue: AddClosetItemViewModel(item: item))
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("기본 정보") {
                TextField("브랜드", text: $viewModel.brand)
                TextField("제품명", text: $viewModel.productName)
                Picker("카테고리", selection: $viewModel.category) {
                    ForEach(ClothingCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                TextField("사이즈", text: $viewModel.size)
            }

            Section("실측값") {
                MeasurementField(title: "어깨", placeholder: "48", value: $viewModel.shoulder)
                MeasurementField(title: "가슴", placeholder: "56", value: $viewModel.chest)
                MeasurementField(title: "총장", placeholder: "70", value: $viewModel.totalLength)
                MeasurementField(title: "소매", placeholder: "62", value: $viewModel.sleeveLength)
            }

            Section("핏 기록") {
                TextField("핏 메모", text: $viewModel.fitMemo, axis: .vertical)
                    .lineLimit(3...5)
                SatisfactionPicker(value: $viewModel.satisfaction)
            }
        }
        .navigationTitle("기준 옷")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("저장") {
                    guard let item = viewModel.makeClosetItem() else {
                        return
                    }

                    onSave(item)
                    dismiss()
                }
                .disabled(!viewModel.canSave)
            }
        }
    }
}
