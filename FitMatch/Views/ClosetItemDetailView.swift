import SwiftUI
import SwiftData

struct ClosetItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isShowingEdit = false

    let item: UserFit

    var body: some View {
        List {
            Section("기본 정보") {
                LabeledContent("출처 유형", value: item.sourceType.displayName)
                LabeledContent("출처", value: item.sourceName)
                LabeledContent("브랜드", value: item.brandName)
                LabeledContent("제품명", value: item.productName)
                LabeledContent("카테고리", value: item.category.rawValue)
                LabeledContent("사이즈", value: item.sizeName)
                LabeledContent("만족도", value: "\(item.satisfaction) / 5")
            }

            Section("실측값") {
                ForEach(item.category.measurementKinds(detailCategory: item.detailCategory, gender: item.gender)) { kind in
                    LabeledContent(kind.title, value: item.measurements.value(for: kind).cmText)
                }
            }

            if !item.fitMemo.isEmpty {
                Section("핏 메모") {
                    Text(item.fitMemo)
                }
            }
        }
        .navigationTitle(item.productName)
        .hidesTabBarOnScroll()
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

    private func applyChanges(from editedItem: UserFit) {
        item.sourceType = editedItem.sourceType
        item.sourceName = editedItem.sourceName
        item.brandName = editedItem.brandName
        item.gender = editedItem.gender
        item.productName = editedItem.productName
        item.category = editedItem.category
        item.detailCategory = editedItem.detailCategory
        item.sizeName = editedItem.sizeName
        item.measurements = editedItem.measurements
        item.fitMemo = editedItem.fitMemo
        item.fitPreference = editedItem.fitPreference
        item.satisfaction = editedItem.satisfaction
        item.isRepresentative = editedItem.isRepresentative
        item.updatedAt = Date()
        try? modelContext.save()
    }
}
