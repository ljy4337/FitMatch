import SwiftUI

/// A read-only guide. Registration, comparison and persistence remain in Main.
struct FitMatchOnboardingView: View {
    let onFinish: () -> Void
    @State private var selectedPage = 0
    @State private var didFinish = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let titles = [
        "내 옷으로 비교하고,\n사이즈를 골라요.",
        "복사 없이,\n공유로 바로 보내세요.",
        "한 번만 설정하면,\n다음부터 더 간편해요.",
        "링크를 붙여넣어도,\n직접 입력해도 돼요."
    ]
    private let descriptions = [
        "잘 입는 옷과의 실측 차이를 확인하고\n비교 결과를 기록으로 남겨요.",
        "쇼핑몰의 상품 페이지에서\n공유 → FitMatch를 선택하면 돼요.",
        "아이폰 공유 목록에 FitMatch를 추가해 두세요.",
        "공유를 사용하지 않아도 상품을 불러오고,\n내 옷의 실측을 직접 입력할 수 있어요."
    ]

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let marker = arguments.firstIndex(of: "-fitmatchOnboardingInitialPage"),
           arguments.indices.contains(marker + 1),
           let page = Int(arguments[marker + 1]) {
            _selectedPage = State(initialValue: max(0, min(3, page)))
        }
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("FitMatch").font(.title2.bold())
                Spacer()
                Text("\(selectedPage + 1) / \(titles.count)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)

            TabView(selection: $selectedPage) {
                ForEach(titles.indices, id: \.self) { index in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(titles[index])
                                .font(.title.weight(.bold))
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("onboarding.title.\(index)")
                            Text(descriptions[index])
                                .font(.body).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            illustration(index)
                        }
                        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(titles.indices, id: \.self) { index in
                    Capsule().fill(index == selectedPage ? Color.primary : Color.secondary.opacity(0.25))
                        .frame(width: index == selectedPage ? 22 : 8, height: 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("총 4페이지 중 \(selectedPage + 1)페이지")
            .padding(.vertical, 14)

            Button {
                guard !didFinish else { return }
                if selectedPage == titles.count - 1 {
                    didFinish = true
                    onFinish()
                } else {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        selectedPage += 1
                    }
                }
            } label: {
                Text("다음").font(.headline.bold())
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                    .foregroundStyle(Color(.systemBackground))
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 24))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.next")
            .accessibilityHint(selectedPage == 3 ? "안내를 마치고 FitMatch를 시작해요" : "다음 안내 페이지")
            .padding(.horizontal, 24).padding(.bottom, 16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    @ViewBuilder private func illustration(_ index: Int) -> some View {
        switch index {
        case 0: introduction
        case 1: sharing
        case 2: shareSetup
        default: alternativeInput
        }
    }

    private var introduction: some View {
        VStack(spacing: 16) {
            guideCard {
                exampleLabel
                // The source capture contains no personal/account information.
                screenshot("OnboardingResultExample", from: 0.143, to: 0.50,
                           label: "비교 예시. 유니클로 집업블루종, 추천 XXL, 사이즈 유사도 92퍼센트, 사용한 실측 4개")
                Divider()
                measurement("총장", product: "69", closet: "76", difference: "7cm 짧아요")
            }
            guideCard {
                Label("기록에서 다시 확인", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Text("비교한 상품과 결과를 기록 화면에서 다시 볼 수 있어요.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            note("먼저 내 옷 한 벌을 등록해 주세요. 같은 그룹의 상품 중 비교 가능한 실측이 있는 상품을 비교해요.")
        }
    }

    private var sharing: some View {
        VStack(spacing: 16) {
            guideCard {
                step(1, "상품 페이지에서 공유 누르기")
                HStack(spacing: 16) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.largeTitle).foregroundStyle(.blue)
                        .frame(width: 64, height: 64)
                        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                    Text("쇼핑몰의 상품 공유 버튼을 찾아주세요. 버튼 모양과 위치는 쇼핑몰마다 달라요.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            guideCard {
                step(2, "공유 목록에서 FitMatch 선택")
                exampleLabel
                shareApps(includeFitMatch: true)
                Divider()
                Label("이미 가진 옷 → 내 옷 추가", systemImage: "tshirt")
                Label("구매할 옷 → 상품 비교", systemImage: "bag")
            }
            note("FitMatch가 안 보인다면 다음 장에서 설정해요.")
        }
    }

    private var shareSetup: some View {
        VStack(spacing: 14) {
            guideCard {
                step(1, "앱 목록 끝의 ‘더 보기’")
                Text("공유 목록을 왼쪽으로 밀어 맨 끝으로 이동해요.")
                    .font(.subheadline).foregroundStyle(.secondary)
                shareApps(includeFitMatch: false)
            }
            guideCard {
                step(2, "오른쪽 위 ‘편집’ 누르기")
                HStack {
                    Text("앱").font(.headline)
                    Spacer()
                    Text("편집").font(.subheadline.bold())
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                        .overlay(Capsule().stroke(Color.blue, lineWidth: 2))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("앱 목록 화면의 오른쪽 위 편집 버튼 예시")
            }
            guideCard {
                step(3, "FitMatch 옆 ＋ 누르기")
                HStack(spacing: 14) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.green).font(.title2)
                    Image("OnboardingAppIcon").resizable().frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    Text("FitMatch").font(.subheadline)
                    Spacer()
                    Capsule().fill(Color.green).frame(width: 40, height: 24)
                        .overlay(alignment: .trailing) {
                            Circle().fill(Color.white).padding(2).frame(width: 24, height: 24)
                        }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("FitMatch 왼쪽의 초록색 더하기로 즐겨찾기에 추가")
            }
            guideCard {
                step(4, "체크 버튼으로 완료")
                HStack {
                    Text("즐겨찾기에 FitMatch가 있으면 준비 완료예요.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.blue)
                }
            }
            note("이미 즐겨찾기에 있다면 설정하지 않아도 돼요. iOS 버전에 따라 완료 버튼 모양이 다를 수 있어요.")
        }
    }

    private var alternativeInput: some View {
        VStack(spacing: 16) {
            guideCard {
                step(1, "쇼핑몰에서 상품 링크 복사")
                step(2, "FitMatch에 붙여넣고 불러오기")
                exampleLabel
                // Only the URL-entry portion is shown; the original lower
                // capture includes an error state, which is not a tutorial.
                screenshot("OnboardingLinkExample", from: 0.175, to: 0.428,
                           label: "상품 URL 입력란의 붙여넣기, 상품 정보 불러오기 버튼 예시")
                Text("내 옷을 등록할 때는 내가 가진 사이즈를 선택하고 실측을 확인해 주세요.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            guideCard {
                Label("내 옷의 링크가 없다면", systemImage: "ruler").font(.headline)
                Text("직접 입력하기를 선택해, 옷을 평평하게 놓고 잰 실측을 입력해요.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Label("신체 치수가 아닌 옷의 치수예요", systemImage: "tshirt")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var exampleLabel: some View {
        Text("화면 예시").font(.caption).foregroundStyle(.secondary)
    }

    private func guideCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.primary.opacity(0.05)))
    }

    private func step(_ number: Int, _ title: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)").font(.subheadline.bold()).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(Color.blue, in: Circle())
                .accessibilityHidden(true)
            Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func note(_ text: String) -> some View {
        Label(text, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func measurement(_ title: String, product: String, closet: String, difference: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            Text("상품 \(product)cm · 내 옷 \(closet)cm").font(.subheadline)
            Text(difference).font(.subheadline.bold()).foregroundStyle(.blue)
        }
        .accessibilityElement(children: .combine)
    }

    private func shareApps(includeFitMatch: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            appTile("메시지", symbol: "message.fill", color: .green)
            appTile("Mail", symbol: "envelope.fill", color: .blue)
            if includeFitMatch {
                appTile("FitMatch", symbol: "bag.fill", color: .black)
            } else {
                appTile("메모", symbol: "note.text", color: .yellow)
            }
            appTile("더 보기", symbol: "ellipsis", color: .gray)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func appTile(_ title: String, symbol: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Group {
                if title == "FitMatch" {
                    Image("OnboardingAppIcon").resizable().scaledToFit()
                } else {
                    Image(systemName: symbol).font(.title2)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(color)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
            Text(title).font(.caption2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    /// Crop within the view so original capture bytes remain unchanged.
    /// Both approved captures are 590 × 1280. Decorative text is described
    /// through an accessibility label instead of exposing fake controls.
    private func screenshot(_ asset: String, from start: CGFloat, to end: CGFloat, label: String) -> some View {
        let ratio: CGFloat = 1280 / 590
        return GeometryReader { proxy in
            Image(asset).resizable()
                .frame(width: proxy.size.width, height: proxy.size.width * ratio)
                .offset(y: -proxy.size.width * ratio * start)
        }
        .aspectRatio(1 / (ratio * (end - start)), contentMode: .fit)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isImage)
        .allowsHitTesting(false)
    }
}
