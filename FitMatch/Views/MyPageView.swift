import SwiftUI
import SwiftData

struct MyPageView: View {
    let onLogout: () -> Void
    @Query(sort: \UserFit.updatedAt, order: .reverse) private var userFits: [UserFit]
    @Query(sort: \RecommendationHistory.createdAt, order: .reverse) private var histories: [RecommendationHistory]

    private let menuItems: [MyMenuItem] = [
        // MyMenuItem(title: "내 정보", systemImage: "person.circle", destination: .comingSoon),
        MyMenuItem(title: "핏매치 사용 방법", systemImage: "questionmark.circle", destination: .guide),
        // MyMenuItem(title: "앱 설정", systemImage: "gearshape", destination: .comingSoon)
        // 로그인 기능을 다시 사용할 때 함께 복구합니다.
        // MyMenuItem(title: "로그아웃", systemImage: "rectangle.portrait.and.arrow.right", destination: .logout)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                FitMatchCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("안녕하세요! 핏매치입니다.")
                            .font(.title3.weight(.bold))
                        Text("내 옷과 쇼핑 상품의 실측을 비교해 나에게 맞는 사이즈를 찾도록 도와드려요.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 계정 기능을 다시 사용할 때 함께 복구합니다.
                // FitMatchCard {
                //     VStack(alignment: .leading, spacing: 16) {
                //         SectionHeader(title: "내 Fit 데이터", subtitle: "옷장과 비교 기록 요약")
                //
                //         HStack(spacing: 10) {
                //             MyStatPill(title: "내 옷", value: "\(userFits.count)")
                //             MyStatPill(title: "기준 옷", value: "\(representativeFitCount)")
                //             MyStatPill(title: "비교 기록", value: "\(histories.count)")
                //         }
                //     }
                // }

                FitMatchCard {
                    VStack(spacing: 0) {
                        ForEach(menuItems.indices, id: \.self) { index in
                            let item = menuItems[index]
                            switch item.destination {
                            case .closet:
                                NavigationLink {
                                    MyClosetView()
                                } label: {
                                    menuRow(item)
                                }
                                .buttonStyle(.plain)
                            case .guide:
                                NavigationLink {
                                    FitMatchUsageGuideView()
                                } label: {
                                    menuRow(item)
                                }
                                .buttonStyle(.plain)
                            case .logout:
                                Button {
                                    onLogout()
                                } label: {
                                    menuRow(item)
                                }
                                .buttonStyle(.plain)
                            case .comingSoon:
                                menuRow(item)
                                    .foregroundStyle(.secondary)
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel("\(item.title), 준비 중")
                            }

                            if index != menuItems.indices.last {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("My")
    }

    private var representativeFitCount: Int {
        userFits.filter(\.isRepresentative).count
    }

    private func menuRow(_ item: MyMenuItem) -> some View {
        HStack {
            Label(item.title, systemImage: item.systemImage)
                .font(.body.weight(.semibold))
            Spacer()
            if item.destination == .comingSoon {
                Text("준비 중")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if item.destination == .closet || item.destination == .guide {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

private struct MyStatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.title2.weight(.black))
                .foregroundStyle(.primary)
                .monospacedDigit()
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct MyMenuItem {
    let title: String
    let systemImage: String
    let destination: MyMenuDestination
}

private enum MyMenuDestination: Equatable {
    case closet
    case guide
    case logout
    case comingSoon
}

private struct FitMatchUsageGuideView: View {
    @State private var expandedItemID: String?
    @State private var isShowingOnboarding = false

    private let items = [
        FitMatchGuideItem(
            title: "핏매치는 어떤 앱인가요?",
            description: "내 옷의 실측과 쇼핑 상품의 사이즈별 실측을 비교해 추천 사이즈와 부위별 차이를 보여주는 앱입니다."
        ),
        FitMatchGuideItem(
            title: "내 옷장에 옷 등록하기",
            description: "MY 탭의 내 옷장에서 링크로 상품을 불러오거나 직접 실측을 입력해 옷을 등록할 수 있습니다. 분류와 보유 사이즈를 정확히 선택해 주세요."
        ),
        FitMatchGuideItem(
            title: "기준 옷이란?",
            description: "평소 핏을 잘 아는 옷을 기준 옷으로 지정하면 호환되는 후보 중 우선 비교합니다. 기준 옷이 없어도 같은 종류의 호환되는 옷이 있으면 비교할 수 있습니다."
        ),
        FitMatchGuideItem(
            title: "쇼핑 상품 비교하기",
            description: "쇼핑몰에서 FitMatch로 상품을 공유하거나 비교 화면에 지원 쇼핑몰 상품 링크를 붙여넣어 상품 정보와 사이즈표를 불러오세요."
        ),
        FitMatchGuideItem(
            title: "자동매칭은 어떻게 하나요?",
            description: "상품의 성별, 분류, 옷 종류, 길이 형태와 공통 실측 항목을 확인해 내 옷장에서 호환되는 옷을 찾습니다. 쇼핑몰이나 브랜드는 매칭 기준이 아닙니다."
        ),
        FitMatchGuideItem(
            title: "비교할 옷이 없을 때",
            description: "호환되는 옷이 없으면 같은 대분류의 내 옷을 직접 선택해 비교하거나, 쇼핑 상품을 내 옷장에 추가할 수 있습니다."
        ),
        FitMatchGuideItem(
            title: "결과 화면 보는 방법",
            description: "추천 사이즈와 비교에 사용한 내 옷을 확인하고, 가슴·총장·소매 등 부위별로 얼마나 크거나 작은지 살펴보세요."
        ),
        FitMatchGuideItem(
            title: "핏 신뢰도란?",
            description: "비교에 사용 가능한 공통 실측과 옷의 호환 정도를 바탕으로 결과를 얼마나 참고할 수 있는지 보여줍니다. 실측이 부족하거나 형태가 다르면 낮아질 수 있습니다."
        ),
        FitMatchGuideItem(
            title: "비교 기록 다시 보기",
            description: "기록 탭에서 이전 비교 결과를 다시 열어 추천 사이즈와 실측 차이를 확인할 수 있습니다."
        ),
        FitMatchGuideItem(
            title: "상품 정보를 불러오지 못할 때",
            description: "지원 쇼핑몰의 상품 URL인지 확인하고 링크를 다시 붙여넣어 주세요. 쇼핑몰 페이지나 사이즈표 형식이 변경되면 일부 정보를 불러오지 못할 수 있습니다."
        ),
        FitMatchGuideItem(
            title: "더 정확하게 사용하는 방법",
            description: "핏을 잘 알고 자주 입는 옷의 정확한 실측을 등록하고, 쇼핑 상품과 같은 종류와 길이 형태의 옷을 비교 대상으로 사용해 주세요."
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    isShowingOnboarding = true
                } label: {
                    FitMatchCard {
                        HStack(spacing: 14) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.headline.weight(.bold))
                                .frame(width: 42, height: 42)
                                .background(.primary.opacity(0.07), in: Circle())
                            Text("온보딩 다시 보기")
                                .font(.body.weight(.bold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .padding(.bottom, 4)

                ForEach(items) { item in
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            expandedItemID = expandedItemID == item.id ? nil : item.id
                        }
                    } label: {
                        FitMatchCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    Text(item.title)
                                        .font(.body.weight(.semibold))
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 12)
                                    Image(systemName: expandedItemID == item.id ? "chevron.up" : "chevron.down")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }

                                if expandedItemID == item.id {
                                    Divider()
                                    Text(item.description)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineSpacing(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("핏매치 사용 방법")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isShowingOnboarding) {
            FitMatchOnboardingView {
                isShowingOnboarding = false
            }
        }
    }
}

private struct FitMatchGuideItem: Identifiable {
    let title: String
    let description: String

    var id: String { title }
}
