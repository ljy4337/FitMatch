import SwiftUI

struct SettingsView: View {
    var onLogout: (() -> Void)?

    var body: some View {
        List {
            Section {
                SettingsRow(title: "계정", systemImage: "person.crop.circle")
                SettingsRow(title: "알림 설정", systemImage: "bell")
                SettingsRow(title: "앱 설정", systemImage: "gearshape")
            }

            Section {
                SettingsRow(title: "문의하기", systemImage: "questionmark.circle")
                SettingsRow(title: "리뷰 남기기", systemImage: "star")
            }

            Section {
                SettingsRow(title: "이용약관", systemImage: "doc.text")
                SettingsRow(title: "개인정보처리방침", systemImage: "lock.shield")
                LabeledContent("버전 정보", value: appVersion)
                    .font(.subheadline)
            }

            Section {
                Button(role: .destructive) {
                    onLogout?()
                } label: {
                    Label("로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("설정")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

private struct SettingsRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        Button {
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
