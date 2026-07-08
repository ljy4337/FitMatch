import SwiftUI
import SwiftData

struct MyClosetView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserFit.createdAt, order: .reverse) private var userFits: [UserFit]
    @State private var isShowingAddClosetItem = false

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
                                    item.isRepresentative ? "대표 해제" : "대표 지정",
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
    }

    private func toggleRepresentative(_ item: UserFit) {
        item.isRepresentative.toggle()
        item.updatedAt = Date()
        try? modelContext.save()
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
                                item.isRepresentative ? "대표옷" : "대표 지정",
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

                        Label("\(item.satisfaction)", systemImage: "star.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .labelStyle(.titleAndIcon)
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
