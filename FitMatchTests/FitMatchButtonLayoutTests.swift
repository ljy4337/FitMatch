import SwiftUI
import Testing
import UIKit
@testable import FitMatch

@MainActor
struct FitMatchButtonLayoutTests {
    @Test func longProductTextDoesNotCompressChangeClosetButton() async throws {
        for width: CGFloat in [320, 375, 430] {
            let short = try await referenceButtonFrame(width: width, longText: false)
            let long = try await referenceButtonFrame(width: width, longText: true)
            #expect(abs(short.width - long.width) < 1)
            #expect(abs(long.height - 38) < 1)
            #expect(long.width > 120)
            #expect(long.maxX <= width)
            #expect(long.minX >= 0)
        }
    }

    @Test func longActionTextStaysWithinOneLineAndAvailableWidth() {
        let title = String(repeating: "아주 긴 버튼 이름 ", count: 8)
        for width: CGFloat in [80, 156, 280] {
            let host = UIHostingController(rootView: Text(title).font(.body).fitMatchActionText())
            let size = host.sizeThatFits(in: CGSize(width: width, height: 1000))
            #expect(size.width <= width + 1)
            #expect(size.height <= 24)
        }
    }

    @Test func renderProductionCommonButtonsWithLongTitles() throws {
        let title = String(repeating: "아주 긴 버튼 이름 ", count: 8)
        let content = VStack(spacing: 16) {
            PrimaryButton(title: title, systemImage: "plus", action: {})
            SecondaryButton(title: title, systemImage: "arrow.clockwise", action: {})
            EmptyStateActionButton(title: title, action: {})
        }.padding(20).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 320, height: 240)
        renderer.scale = 3
        let image = try #require(renderer.uiImage)
        let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("BF1012-common-buttons.png")
        try image.pngData()?.write(to: path)
        print("BF1012_LAYOUT common screenshot=\(path.path)")
    }

    private func referenceButtonFrame(width: CGFloat, longText: Bool) async throws -> CGRect {
        let repeated = String(repeating: "러스트릭 반소매 티셔츠 매우 긴 상품명 ", count: 10)
        var measuredFrame: CGRect?
        let card = ResultClosetReferenceCard(
            imageURLString: nil, category: .top,
            brandName: longText ? repeated : "ZARA",
            productName: longText ? repeated : "티셔츠",
            sizeName: longText ? repeated : "L (KR 77)",
            onChangeCloset: {}
        )
        let host = UIHostingController(rootView: card.environment(\.fitMatchButtonLayoutObserver, { measuredFrame = $0 }).padding(.horizontal, 16).environment(\.colorScheme, .dark))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 220))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let frame = try #require(measuredFrame)
        let renderer = ImageRenderer(content: card.padding(.horizontal, 16).environment(\.colorScheme, .dark))
        renderer.proposedSize = ProposedViewSize(width: width, height: 220)
        renderer.scale = 3
        let image = try #require(renderer.uiImage)
        let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("BF1012-button-\(Int(width))-\(longText ? "long" : "short").png")
        try image.pngData()?.write(to: path)
        print("BF1012_LAYOUT width=\(width) long=\(longText) button=\(frame) screenshot=\(path.path)")
        return frame
    }

}
