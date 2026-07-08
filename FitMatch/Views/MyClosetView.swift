import SwiftUI
import SwiftData

struct MyClosetView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserFit.createdAt, order: .reverse) private var userFits: [UserFit]
    @State private var isShowingAddClosetItem = false
    @State private var pendingBasisItem: UserFit?
    @State private var existingBasisItem: UserFit?
    @State private var isShowingBasisChangeAlert = false

    var body: some View {
        Group {
            if userFits.isEmpty {
                EmptyClosetView()
            } else {
                List {
                    ForEach(userFits) { item in
                        ClosetItemCard(item: item) {
                            toggleRepresentative(item)
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                toggleRepresentative(item)
                            } label: {
                                Label(
                                    item.isRepresentative ? "기준 옷 해제" : "기준 옷으로 설정",
                                    systemImage: item.isRepresentative ? "heart.slash" : "heart.fill"
                                )
                            }
                            .tint(item.isRepresentative ? .gray : .red)
                        }
                    }
                    .onDelete(perform: deleteItems)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBarOnScroll()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingAddClosetItem = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("기준 옷 추가")
            }
        }
        .sheet(isPresented: $isShowingAddClosetItem) {
            NavigationStack {
                AddClosetItemView { item in
                    modelContext.insert(item)
                    try? modelContext.save()
                }
            }
        }
        .alert(basisAlertTitle, isPresented: $isShowingBasisChangeAlert) {
            Button("취소", role: .cancel) {
                pendingBasisItem = nil
                existingBasisItem = nil
            }
            Button(existingBasisItem == nil ? "기준 옷으로 설정" : "변경") {
                applyPendingBasisChange()
            }
        } message: {
            Text(basisAlertMessage)
        }
    }

    private func toggleRepresentative(_ item: UserFit) {
        if item.isRepresentative {
            item.isRepresentative = false
            item.updatedAt = Date()
            try? modelContext.save()
            return
        }

        pendingBasisItem = item
        existingBasisItem = userFits.first {
            $0.id != item.id
                && $0.detailCategory == item.detailCategory
                && $0.isRepresentative
        }
        isShowingBasisChangeAlert = true
    }

    private var basisAlertTitle: String {
        guard let pendingBasisItem else {
            return "기준 옷 설정"
        }

        if existingBasisItem == nil {
            return "이 옷을 기준 옷으로 설정할까요?"
        }

        return "\(pendingBasisItem.detailCategory.rawValue) 기준 옷은 1개만 설정할 수 있습니다."
    }

    private var basisAlertMessage: String {
        guard let pendingBasisItem else {
            return ""
        }

        if let existingBasisItem {
            return """
            현재 기준 옷:
            \(existingBasisItem.displayName)

            새 기준 옷:
            \(pendingBasisItem.displayName)

            기존 기준 옷이 해제되고 새 기준 옷으로 변경됩니다.
            """
        }

        return """
        기준 옷은 같은 카테고리 상품을 비교할 때 자동으로 우선 비교됩니다.

        언제든 다른 옷으로 변경할 수 있습니다.
        """
    }

    private func applyPendingBasisChange() {
        guard let pendingBasisItem else {
            return
        }

        userFits
            .filter {
                $0.id != pendingBasisItem.id
                    && $0.detailCategory == pendingBasisItem.detailCategory
                    && $0.isRepresentative
            }
            .forEach {
                $0.isRepresentative = false
                $0.updatedAt = Date()
            }

        pendingBasisItem.isRepresentative = true
        pendingBasisItem.updatedAt = Date()
        try? modelContext.save()

        self.pendingBasisItem = nil
        existingBasisItem = nil
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let item = userFits[index]
            modelContext.delete(item)
        }
        try? modelContext.save()
    }
}

private struct EmptyClosetView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            Image("EmptyCloset")
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 160)

            VStack(spacing: 6) {
                Text("옷장이 비었습니다.")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Text("핏이 마음에 드는 옷을 먼저 추가해 주세요.")
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

private struct ClosetItemCard: View {
    let item: UserFit
    let onToggleRepresentative: () -> Void

    var body: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.displayName)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("출처: \(item.sourceName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("\(item.gender.rawValue) / \(item.category.rawValue) / \(item.detailCategory.rawValue) / \(item.sizeName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Button(action: onToggleRepresentative) {
                            Label(
                                item.isRepresentative ? "기준 옷" : "기준 옷 설정",
                                systemImage: item.isRepresentative ? "heart.fill" : "heart"
                            )
                            .font(.caption.weight(.bold))
                            .foregroundStyle(item.isRepresentative ? .red : .primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.primary.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Text(item.fitPreference.rawValue)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.primary.opacity(0.08), in: Capsule())

                    }
                }

                MeasurementSummaryView(
                    measurements: item.measurements,
                    category: item.category,
                    detailCategory: item.detailCategory,
                    gender: item.gender
                )

                NavigationLink {
                    ClosetItemDetailView(item: item)
                } label: {
                    Text("상세 보기")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
