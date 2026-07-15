import SwiftUI
import SwiftData

struct MyPageView: View {
    let onLogout: () -> Void
    @Query(sort: \UserFit.updatedAt, order: .reverse) private var userFits: [UserFit]
    @Query(sort: \RecommendationHistory.createdAt, order: .reverse) private var histories: [RecommendationHistory]

    private let menuItems: [MyMenuItem] = [
        MyMenuItem(title: "내 정보", systemImage: "person.circle"),
        MyMenuItem(title: "내옷장관리", systemImage: "tshirt"),
        MyMenuItem(title: "앱설정", systemImage: "gearshape"),
        MyMenuItem(title: "로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                FitMatchCard {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 54))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("FitMatch User")
                                .font(.title3.weight(.bold))
                            Text("내 옷장 기반 사이즈 추천")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                FitMatchCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "내 Fit 데이터", subtitle: "옷장과 비교 기록 요약")

                        HStack(spacing: 10) {
                            MyStatPill(title: "내 옷", value: "\(userFits.count)")
                            MyStatPill(title: "기준 옷", value: "\(representativeFitCount)")
                            MyStatPill(title: "비교 기록", value: "\(histories.count)")
                        }
                    }
                }

                FitMatchCard {
                    VStack(spacing: 0) {
                        ForEach(menuItems.indices, id: \.self) { index in
                            let item = menuItems[index]
                            if item.title == "내옷장관리" {
                                NavigationLink {
                                    MyClosetView()
                                } label: {
                                    menuRow(item)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button {
                                    handleTap(title: item.title)
                                } label: {
                                    menuRow(item)
                                }
                                .buttonStyle(.plain)
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

    private func handleTap(title: String) {
        switch title {
        case "로그아웃":
            onLogout()
        default:
            break
        }
    }

    private var representativeFitCount: Int {
        userFits.filter(\.isRepresentative).count
    }

    private func menuRow(_ item: MyMenuItem) -> some View {
        HStack {
            Label(item.title, systemImage: item.systemImage)
                .font(.body.weight(.semibold))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 14)
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
}
