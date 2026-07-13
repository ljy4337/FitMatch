import SwiftUI
import SwiftData

struct ClosetItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var tabBarVisibilityController: TabBarVisibilityController
    @Query(sort: \UserFit.updatedAt, order: .reverse) private var userFits: [UserFit]
    @Query(sort: \RecommendationHistory.createdAt, order: .reverse) private var histories: [RecommendationHistory]
    @State private var isShowingEdit = false
    @State private var saveErrorMessage: String?

    let item: UserFit

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroCard
                quickSummaryCard
                basicInfoCard
                measurementCard

                if !item.fitMemo.isEmpty {
                    memoCard
                }
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("내 옷 정보")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("편집") {
                    isShowingEdit = true
                }
                .font(.subheadline.weight(.bold))
            }
        }
        .sheet(isPresented: $isShowingEdit) {
            NavigationStack {
                AddClosetItemView(
                    item: item,
                    onDelete: {
                        deleteItemAndDismiss()
                    }
                ) { editedItem in
                    applyChanges(from: editedItem)
                }
            }
            .presentationDragIndicator(.visible)
        }
        .alert("저장 실패", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "")
        }
        .onAppear {
            tabBarVisibilityController.hide(reason: .navigationDetail, source: "closet detail")
        }
        .onDisappear {
            tabBarVisibilityController.release(reason: .navigationDetail, source: "closet detail disappear")
        }
    }

    private var heroCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                if let imageURLString, !imageURLString.isEmpty {
                    ProductThumbnailView(
                        imageURLString: imageURLString,
                        category: item.category,
                        width: 320,
                        height: 260,
                        cornerRadius: 22
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    ClosetDetailPlaceholderImage(category: item.category)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.brandName)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(item.productName)
                                .font(.title3.weight(.black))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        if item.isRepresentative {
                            Text("기준 옷")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color(.systemBackground))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(Color.primary, in: Capsule())
                        }
                    }

                    HStack(spacing: 8) {
                        ClosetDetailChip(title: item.detailCategory.rawValue)
                        ClosetDetailChip(title: item.sizeName)
                        ClosetDetailChip(title: item.fitPreference.rawValue)
                    }
                }
            }
        }
    }

    private var quickSummaryCard: some View {
        HStack(spacing: 10) {
            ClosetSummaryTile(title: "카테고리", value: item.category.rawValue)
            ClosetSummaryTile(title: "사이즈", value: item.sizeName)
            ClosetSummaryTile(title: "핏", value: item.fitPreference.rawValue)
        }
    }

    private var basicInfoCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "기본 정보")

                VStack(spacing: 11) {
                    DetailInfoRow(title: "브랜드", value: item.brandName)
                    DetailInfoRow(title: "상품명", value: item.productName)
                    DetailInfoRow(title: "출처", value: sourceDescription)
                    DetailInfoRow(title: "성별", value: item.gender.rawValue)
                    DetailInfoRow(title: "분류", value: "\(item.category.rawValue) / \(item.detailCategory.rawValue)")
                }
            }
        }
    }

    private var measurementCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "실측값")

                LazyVGrid(columns: measurementGridColumns, spacing: 10) {
                    ForEach(item.category.measurementKinds(detailCategory: item.detailCategory, gender: item.gender)) { kind in
                        MeasurementValueTile(
                            title: kind.title,
                            value: measurementText(for: kind)
                        )
                    }
                }
            }
        }
    }

    private var measurementGridColumns: [GridItem] {
        let columnCount = item.category.serviceGroup == .bottom ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: columnCount)
    }

    private var memoCard: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "핏 메모")
                Text(item.fitMemo)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var imageURLString: String? {
        item.sourceProduct?.imageURLString?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sourceDescription: String {
        item.sourceName == item.sourceType.displayName
            ? item.sourceName
            : "\(item.sourceName) · \(item.sourceType.displayName)"
    }

    private func measurementText(for kind: MeasurementKind) -> String {
        let value = item.measurements.value(for: kind)
        return value > 0 ? value.cmText : "-"
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
        do {
            try modelContext.save()
        } catch {
            saveErrorMessage = "수정 내용을 저장하지 못했습니다."
        }
    }

    private func deleteItemAndDismiss() {
        histories
            .filter { $0.userFit.id == item.id }
            .forEach { modelContext.delete($0) }

        modelContext.delete(item)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveErrorMessage = "옷장 항목을 삭제하지 못했습니다."
        }
    }
}

private struct ClosetDetailPlaceholderImage: View {
    let category: ClothingCategory

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 82, height: 82)
                .background(Color(.systemBackground), in: Circle())

            Text("이미지 없음")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var iconName: String {
        switch category.serviceGroup {
        case .shoes:
            return "shoe.2"
        case .accessory:
            return "watch.analog"
        default:
            return "tshirt"
        }
    }
}

private struct ClosetDetailChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
    }
}

private struct ClosetSummaryTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 7) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.black))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct DetailInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct MeasurementValueTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
