import SwiftUI

struct MyPageView: View {
    @Binding var selectedTab: AppTab
    let onLogout: () -> Void

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
        .hidesTabBarOnScroll()
    }

    private func handleTap(title: String) {
        switch title {
        case "로그아웃":
            onLogout()
        default:
            break
        }
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

private struct MyMenuItem {
    let title: String
    let systemImage: String
}
