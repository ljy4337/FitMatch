import SwiftUI
import SwiftData

struct MyClosetView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClosetItem.createdAt, order: .reverse) private var items: [ClosetItem]
    @Query private var baselineFits: [BaselineFit]
    @State private var isShowingAddClosetItem = false

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView(
                    "저장된 기준 옷이 없습니다",
                    systemImage: "tshirt",
                    description: Text("핏이 마음에 드는 옷을 먼저 추가해 주세요.")
                )
            } else {
                ForEach(items) { item in
                    NavigationLink {
                        ClosetItemDetailView(item: item)
                    } label: {
                        ClosetItemRow(item: item)
                    }
                }
                .onDelete(perform: deleteItems)
            }
        }
        .navigationTitle("My Closet")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingAddClosetItem = true
                } label: {
                    Label("기준 옷 추가", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingAddClosetItem) {
            NavigationStack {
                AddClosetItemView { item in
                    modelContext.insert(item)
                    modelContext.insert(item.baselineFit)
                }
            }
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let item = items[index]
            baselineFits
                .filter { ($0.sourceClosetItemID ?? $0.id) == item.id }
                .forEach(modelContext.delete)
            modelContext.delete(item)
        }
    }
}

private struct ClosetItemRow: View {
    let item: ClosetItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(.headline)
                    Text("\(item.category.rawValue) / \(item.size)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Label("\(item.satisfaction)", systemImage: "star.fill")
                    .font(.subheadline)
                    .foregroundStyle(.yellow)
                    .labelStyle(.titleAndIcon)
            }

            MeasurementSummaryView(measurements: item.measurements)
        }
        .padding(.vertical, 6)
    }
}
