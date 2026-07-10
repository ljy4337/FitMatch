import SwiftUI
import SwiftData

struct ClosetItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserFit.updatedAt, order: .reverse) private var userFits: [UserFit]
    @State private var isShowingEdit = false

    let item: UserFit

    var body: some View {
        List {
            if let imageURLString = item.sourceProduct?.imageURLString,
               !imageURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    ProductThumbnailView(
                        imageURLString: imageURLString,
                        width: 300,
                        height: 320,
                        cornerRadius: 22
                    )
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
                }
            }

            Section("기본 정보") {
                LabeledContent("출처 유형", value: item.sourceType.displayName)
                LabeledContent("출처", value: item.sourceName)
                LabeledContent("브랜드", value: item.brandName)
                LabeledContent("제품명", value: item.productName)
                LabeledContent("카테고리", value: item.category.rawValue)
                LabeledContent("사이즈", value: item.sizeName)
                LabeledContent("핏", value: item.fitPreference.rawValue)
                if item.isRepresentative {
                    LabeledContent("기준 옷", value: "\(item.detailCategory.rawValue) 기준")
                }
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
        if item.isRepresentative {
            userFits
                .filter {
                    $0.id != item.id
                        && $0.detailCategory == item.detailCategory
                        && $0.isRepresentative
                }
                .forEach {
                    $0.isRepresentative = false
                    $0.updatedAt = Date()
                }
        }
        item.updatedAt = Date()
        try? modelContext.save()
    }
}
