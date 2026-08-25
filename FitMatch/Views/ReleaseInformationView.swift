import Foundation
import SwiftUI

enum FitMatchReleaseConfiguration {
    static let privacyPolicyURLKey = "FitMatchPrivacyPolicyURL"
    static let supportURLKey = "FitMatchSupportURL"

    static var privacyPolicyURL: URL? {
        httpsURL(from: Bundle.main.object(forInfoDictionaryKey: privacyPolicyURLKey) as? String)
    }

    static var supportURL: URL? {
        httpsURL(from: Bundle.main.object(forInfoDictionaryKey: supportURLKey) as? String)
    }

    static func httpsURL(from rawValue: String?) -> URL? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil else {
            return nil
        }
        return components.url
    }

}

struct FitMatchPrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                FitMatchReleaseIntroCard(
                    systemImage: "lock.shield.fill",
                    title: "개인정보처리방침",
                    description: "FitMatch의 현재 계정 및 데이터 처리 방식을 안내합니다."
                )

                FitMatchReleaseSection(
                    title: "계정 정보",
                    content: "로그인과 계정 식별을 위해 Apple 로그인에서 제공하는 식별자와 사용자가 공개에 동의한 이메일 정보를 Supabase 인증 서비스에서 처리합니다. 추후 다른 로그인 수단을 추가하면 이 방침과 로그인 화면에 반영합니다."
                )
                FitMatchReleaseSection(
                    title: "기기와 서버에 저장하는 정보",
                    content: "등록한 옷, 선택한 사이즈와 실측, 기준 옷 설정, 상품 링크·카테고리, 비교 상품과 결과 기록을 기기와 FitMatch 서버에 저장합니다. 공용 쇼핑몰 상품 정보는 다른 사용자에게도 쓰이는 상품 카탈로그로 보관될 수 있습니다."
                )
                FitMatchReleaseSection(
                    title: "상품 정보 요청",
                    content: "사용자가 입력하거나 공유한 무신사·유니클로 상품 링크를 분석하기 위해 해당 쇼핑몰의 공식 웹·API 주소로 네트워크 요청을 보냅니다. 이 과정에서 쇼핑몰에는 일반적인 네트워크 요청 정보가 전달될 수 있습니다."
                )
                FitMatchReleaseSection(
                    title: "이미지와 실측 분석",
                    content: "사용자가 선택한 사이즈표 이미지는 Apple Vision을 이용해 기기 안에서 분석합니다. FitMatch가 이미지를 별도 서버로 업로드하거나 저장하지 않습니다."
                )
                FitMatchReleaseSection(
                    title: "외부 전송과 추적",
                    content: "계정·옷장·비교 데이터의 저장과 동기화에는 Supabase를 사용합니다. 상품 분석을 위해 무신사·유니클로의 공식 웹·API로 요청할 수 있습니다. 광고 SDK와 사용자 추적 기능은 사용하지 않으며, 품질 진단 정보는 사용자가 공유를 직접 선택한 경우에만 전달됩니다."
                )
                FitMatchReleaseSection(
                    title: "삭제와 보관",
                    content: "옷장 항목과 비교 기록은 앱 안에서 삭제할 수 있습니다. My 화면의 회원 탈퇴를 실행하면 계정과 사용자 소유 서버 데이터, 기기 내 옷장·비교 기록을 영구 삭제합니다. 공용 상품 카탈로그와 법령상 보관 의무가 있는 비식별 기록은 사용자 계정과 분리해 유지될 수 있습니다. Apple 로그인 권한은 iPhone 설정의 Apple로 로그인 메뉴에서도 해제할 수 있습니다."
                )
                FitMatchReleaseSection(
                    title: "정책 변경",
                    content: "데이터 전송 기능이나 외부 분석 도구를 도입할 경우 적용 전에 이 방침과 App Store 개인정보 답변을 함께 갱신합니다."
                )

                if let privacyPolicyURL = FitMatchReleaseConfiguration.privacyPolicyURL {
                    Link(destination: privacyPolicyURL) {
                        FitMatchReleaseLinkLabel(
                            title: "웹 개인정보처리방침 열기",
                            systemImage: "safari"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("privacyPolicyWebLink")
                }

                Text("시행일: 2026년 8월 20일")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("개인정보처리방침")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("privacyPolicyScreen")
    }
}

struct FitMatchSupportView: View {
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "4"
        return "\(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                FitMatchReleaseIntroCard(
                    systemImage: "lifepreserver.fill",
                    title: "문의 및 지원",
                    description: "문제가 생기면 앱을 삭제하기 전에 아래 내용을 확인해 주세요."
                )

                FitMatchReleaseSection(
                    title: "상품을 불러오지 못할 때",
                    content: "무신사 또는 유니클로의 실제 상품 페이지 링크인지 확인하고 다시 시도해 주세요. 쇼핑몰의 페이지나 사이즈표 형식이 변경되면 일시적으로 분석하지 못할 수 있습니다."
                )
                FitMatchReleaseSection(
                    title: "저장 오류가 표시될 때",
                    content: "앱을 바로 삭제하지 말고 앱을 완전히 종료한 뒤 다시 실행해 주세요. 삭제하면 기기에만 저장된 옷장과 비교 기록을 복구하지 못할 수 있습니다."
                )
                FitMatchReleaseSection(
                    title: "문의에 포함하면 좋은 정보",
                    content: "앱 버전, 문제가 발생한 화면, 발생 시각, 사용한 쇼핑몰, 표시된 오류 문구를 알려주세요. 상품 URL이나 옷장·비교 정보는 꼭 필요한 경우에만 직접 선택해 보내주세요."
                )

                FitMatchReleaseSection(
                    title: "품질 진단 정보",
                    content: "상품명·URL·상품 ID·실측값·사용자 식별자를 포함하지 않는 누적 성공·실패 횟수만 내보냅니다. 공유할 앱과 대상은 사용자가 직접 선택합니다."
                )

                ShareLink(
                    item: FitMatchMetricsRecorder.shared.diagnosticReport(),
                    subject: Text("FitMatch 품질 진단")
                ) {
                    FitMatchReleaseLinkLabel(
                        title: "품질 진단 정보 내보내기",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("supportDiagnosticsShareLink")

                if let supportURL = FitMatchReleaseConfiguration.supportURL {
                    Link(destination: supportURL) {
                        FitMatchReleaseLinkLabel(
                            title: "고객지원 웹페이지 열기",
                            systemImage: "safari"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("supportWebLink")
                }

                if FitMatchReleaseConfiguration.supportURL == nil {
                    FitMatchReleaseSection(
                        title: "고객지원 링크",
                        content: "고객지원 웹페이지를 불러오지 못했습니다. App Store의 FitMatch 앱 지원 링크를 이용해 주세요."
                    )
                    .accessibilityIdentifier("supportContactUnavailable")
                }

                Text("앱 버전 \(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("문의 및 지원")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("supportScreen")
    }
}

private struct FitMatchReleaseIntroCard: View {
    let systemImage: String
    let title: String
    let description: String

    var body: some View {
        FitMatchCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(.primary.opacity(0.07), in: Circle())
                VStack(alignment: .leading, spacing: 7) {
                    Text(title)
                        .font(.title3.weight(.bold))
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct FitMatchReleaseSection: View {
    let title: String
    let content: String

    var body: some View {
        FitMatchCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.body.weight(.bold))
                Text(content)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct FitMatchReleaseLinkLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        FitMatchCard {
            HStack(spacing: 12) {
                Label(title, systemImage: systemImage)
                    .font(.body.weight(.semibold))
                Spacer(minLength: 12)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
    }
}
