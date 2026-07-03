import SwiftUI
import SwiftData

struct ClosetItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var baselineFits: [BaselineFit]
    @State private var isShowingEdit = false

    let item: ClosetItem

    var body: some View {
        List {
            Section("기본 정보") {
                LabeledContent("브랜드", value: item.brand)
                LabeledContent("제품명", value: item.productName)
                LabeledContent("카테고리", value: item.category.rawValue)
                LabeledContent("사이즈", value: item.size)
                LabeledContent("만족도", value: "\(item.satisfaction) / 5")
            }

            Section("실측값") {
                LabeledContent("어깨", value: item.measurements.shoulder.cmText)
                LabeledContent("가슴", value: item.measurements.chest.cmText)
                LabeledContent("총장", value: item.measurements.totalLength.cmText)
                LabeledContent("소매", value: item.measurements.sleeveLength.cmText)
            }

            if !item.fitMemo.isEmpty {
                Section("핏 메모") {
                    Text(item.fitMemo)
                }
            }
        }
        .navigationTitle(item.productName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("수정") {
                    isShowingEdit = true
                }
            }
        }
        .sheet(isPresented: $isShowingEdit) {
            NavigationStack {
                AddClosetItemView(item: item) { editedItem in
                    applyChanges(from: editedItem)
                }
            }
        }
    }

    private func applyChanges(from editedItem: ClosetItem) {
        item.brand = editedItem.brand
        item.productName = editedItem.productName
        item.category = editedItem.category
        item.size = editedItem.size
        item.measurements = editedItem.measurements
        item.fitMemo = editedItem.fitMemo
        item.satisfaction = editedItem.satisfaction

        let matchedFits = baselineFits.filter { ($0.sourceClosetItemID ?? $0.id) == item.id }
        if matchedFits.isEmpty {
            modelContext.insert(item.baselineFit)
        } else {
            for fit in matchedFits {
                fit.brand = item.brand
                fit.productName = item.productName
                fit.category = item.category
                fit.size = item.size
                fit.measurements = item.measurements
                fit.fitMemo = item.fitMemo
                fit.satisfaction = item.satisfaction
            }
        }
    }
}
