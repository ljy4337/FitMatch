import SwiftUI

struct BodyShapeSetupFlow: View {
    let isRequiredFlow: Bool
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var preferences: BodyShapePreferences
    @State private var isShowingSaveConfirmation = false

    init(isRequiredFlow: Bool, onComplete: @escaping () -> Void = {}) {
        self.isRequiredFlow = isRequiredFlow
        self.onComplete = onComplete
        _preferences = State(initialValue: BodyShapeSettingsStore().load())
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("체형 설정 \(page + 1)/2")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(page == 0 ? "상체는 어떤 체형에 가까운가요?" : "하체는 어떤 체형에 가까운가요?")
                            .font(.title2.weight(.black))
                        Text("해당되는 항목을 모두 선택해 주세요.\n선택한 부위는 사이즈 추천 시 조금 더 중요하게 반영돼요.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                    }

                    VStack(spacing: 12) {
                        if page == 0 {
                            selectionCard(
                                title: "어깨가 넓은 편",
                                description: "어깨가 편한 사이즈를 더 중요하게 비교해요.",
                                isSelected: preferences.hasBroadShoulders
                            ) { preferences.hasBroadShoulders.toggle() }
                            selectionCard(
                                title: "가슴이 발달한 편",
                                description: "가슴이 끼지 않는 사이즈를 더 중요하게 비교해요.",
                                isSelected: preferences.hasDevelopedChest
                            ) { preferences.hasDevelopedChest.toggle() }
                            selectionCard(
                                title: "복부가 나온 편",
                                description: "배 부분이 편한 사이즈를 우선 추천해요.",
                                isSelected: preferences.hasProminentAbdomen
                            ) { preferences.hasProminentAbdomen.toggle() }
                        } else {
                            selectionCard(
                                title: "허리·복부가 나온 편",
                                description: "허리가 편한 사이즈를 더 중요하게 비교해요.",
                                isSelected: preferences.hasProminentLowerWaist
                            ) { preferences.hasProminentLowerWaist.toggle() }
                            selectionCard(
                                title: "엉덩이가 발달한 편",
                                description: "엉덩이가 편한 사이즈를 더 중요하게 비교해요.",
                                isSelected: preferences.hasDevelopedHips
                            ) { preferences.hasDevelopedHips.toggle() }
                            selectionCard(
                                title: "허벅지가 발달한 편",
                                description: "허벅지가 끼지 않는 사이즈를 더 중요하게 비교해요.",
                                isSelected: preferences.hasDevelopedThighs
                            ) { preferences.hasDevelopedThighs.toggle() }
                        }
                    }

                    Text(page == 0
                         ? "선택하지 않으면 보통 체형으로 적용됩니다."
                         : "선택하지 않으면 보통 체형으로 적용됩니다.\n상품에 일부 치수가 없으면 비교 가능한 치수만 사용해 추천해요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("선택한 체형은 관련 치수가 있는 상품에서만 반영돼요.\n변경한 설정은 새로 비교하는 상품부터 적용돼요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            HStack(spacing: 12) {
                if page == 1 {
                    Button {
                        page = 0
                    } label: {
                        Label("이전", systemImage: "chevron.left")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(minWidth: 96)
                            .frame(height: 54)
                            .background(
                                Color.primary.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    if page == 0 {
                        page = 1
                    } else {
                        let store = BodyShapeSettingsStore()
                        store.save(preferences)
                        store.markCompleted()
                        isShowingSaveConfirmation = true
                    }
                } label: {
                    Text(page == 0 ? "다음" : "설정 완료")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            Color.black,
                            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.bar)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationBarBackButtonHidden(isRequiredFlow)
        .navigationTitle(isRequiredFlow ? "" : "체형 설정")
        .navigationBarTitleDisplayMode(.inline)
        .alert("체형 설정을 저장했어요", isPresented: $isShowingSaveConfirmation) {
            Button("확인") {
                onComplete()
                if !isRequiredFlow { dismiss() }
            }
        } message: {
            Text("기존 비교 기록은 변경되지 않아요.")
        }
    }

    private func selectionCard(
        title: String,
        description: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.body.weight(.bold))
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.primary : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "선택됨" : "선택 안 됨")
    }
}
