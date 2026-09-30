#if DEBUG
import Foundation
import SwiftUI
import WebKit

enum ZARAWebViewAuditFeature {
    static let launchArgument = "-fitmatchZARAWebViewAudit"

    static var requestedURL: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: launchArgument),
              arguments.indices.contains(index + 1),
              let url = URL(string: arguments[index + 1]),
              ProductURLSupport.isZARAURL(url) else {
            return nil
        }
        return url
    }
}

/// Debug-only, user-visible proof of concept. It uses WebKit's normal browser
/// behavior and never attempts to bypass a challenge or copy account cookies.
struct ZARAWebViewAuditScreen: View {
    let requestedURL: URL

    @State private var status = "ZARA 페이지를 여는 중"
    @State private var identitySummary = "식별자 확인 전"
    @State private var guideSummary = "실측 API 확인 전"
    @State private var captureRequestID = UUID()
    @State private var rejectOptionalCookiesRequestID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ZARA WebView 검증")
                    .font(.headline)
                Text(status)
                    .font(.subheadline)
                    .accessibilityIdentifier("zaraAuditStatus")
                Text(identitySummary)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .accessibilityIdentifier("zaraAuditIdentity")
                Text(guideSummary)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .accessibilityIdentifier("zaraAuditGuide")
                HStack {
                    Button("비필수 쿠키 거부 후 읽기") {
                        rejectOptionalCookiesRequestID = UUID()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("zaraAuditRejectOptionalCookies")

                    Button("다시 읽기") {
                        captureRequestID = UUID()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("zaraAuditRecapture")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemBackground))

            ZARAVisibleWebView(
                requestedURL: requestedURL,
                captureRequestID: captureRequestID,
                rejectOptionalCookiesRequestID: rejectOptionalCookiesRequestID
            ) { event in
                handle(event)
            }
            .accessibilityIdentifier("zaraAuditWebView")
        }
        .background(Color(.systemBackground))
    }

    private func handle(_ event: ZARAWebViewAuditEvent) {
        switch event {
        case .loading(let url):
            status = "사용자에게 보이는 페이지 로딩 중"
            identitySummary = "URL: \(url.absoluteString)"
        case .failed(let message):
            status = "검증 실패"
            guideSummary = message
            print("[ZARAAudit] FAILED reason=\(message)")
        case .captured(let page):
            validate(page)
        }
    }

    private func validate(_ page: ZARAProductPage) {
        guard !ZARAProductPageParser.isBotChallenge(page.html) else {
            status = "ZARA challenge 감지 — 우회하지 않고 중단"
            guideSummary = "challenge_detected"
            print("[ZARAAudit] BLOCKED challenge_detected=true")
            return
        }
        guard let identity = ZARAProductPageParser.identity(
            requestedURL: requestedURL,
            resolvedURL: page.url,
            html: page.html
        ) else {
            status = "구조화 데이터 식별자 검증 실패"
            guideSummary = "identity_unresolved"
            print("[ZARAAudit] FAILED reason=identity_unresolved resolvedURL=\(page.url.absoluteString)")
            return
        }

        status = "구조화 데이터 확인 완료"
        identitySummary = "style=\(identity.styleNumber) v1/catentry=\(identity.catentryID) productId=\(identity.internalProductID) productRef=\(identity.productReference)"
        print("[ZARAAudit] IDENTITY_PASS style=\(identity.styleNumber) catentry=\(identity.catentryID) internalProductId=\(identity.internalProductID) productRef=\(identity.productReference)")

        Task {
            do {
                let data = try await ZARASizeGuideLoader().load(productID: identity.catentryID)
                let presence = try ZARAGuidePresence(data: data)
                guideSummary = "apiID=\(identity.catentryID) response=\(presence.description)"
                status = presence.hasGarmentMeasurements
                    ? "상품정보·의류 실측 응답 확인 완료"
                    : "상품정보 확인 완료 · 의류 실측 미제공"
                print("[ZARAAudit] SIZE_GUIDE_PASS apiID=\(identity.catentryID) response=\(presence.description)")
            } catch {
                guideSummary = "apiID=\(identity.catentryID) error=\(error.localizedDescription)"
                status = "상품정보 확인 완료 · 실측 API 실패"
                print("[ZARAAudit] SIZE_GUIDE_FAILED apiID=\(identity.catentryID) error=\(error.localizedDescription)")
            }
        }
    }
}

private enum ZARAWebViewAuditEvent {
    case loading(URL)
    case captured(ZARAProductPage)
    case failed(String)
}

private struct ZARAVisibleWebView: UIViewRepresentable {
    let requestedURL: URL
    let captureRequestID: UUID
    let rejectOptionalCookiesRequestID: UUID
    let onEvent: (ZARAWebViewAuditEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onEvent: onEvent)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.requestedURL = requestedURL
        context.coordinator.captureRequestID = captureRequestID
        context.coordinator.rejectOptionalCookiesRequestID = rejectOptionalCookiesRequestID
        onEvent(.loading(requestedURL))
        webView.load(URLRequest(url: requestedURL, timeoutInterval: 30))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.captureRequestID != captureRequestID {
            context.coordinator.captureRequestID = captureRequestID
            context.coordinator.capture(from: webView)
        }
        if context.coordinator.rejectOptionalCookiesRequestID != rejectOptionalCookiesRequestID {
            context.coordinator.rejectOptionalCookiesRequestID = rejectOptionalCookiesRequestID
            context.coordinator.rejectOptionalCookies(in: webView)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var requestedURL: URL?
        var captureRequestID: UUID?
        var rejectOptionalCookiesRequestID: UUID?
        private let onEvent: (ZARAWebViewAuditEvent) -> Void
        private var hasAutoCaptured = false

        init(onEvent: @escaping (ZARAWebViewAuditEvent) -> Void) {
            self.onEvent = onEvent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !hasAutoCaptured else { return }
            hasAutoCaptured = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                capture(from: webView)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            onEvent(.failed("navigation_failed: \(error.localizedDescription)"))
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            onEvent(.failed("provisional_navigation_failed: \(error.localizedDescription)"))
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.targetFrame?.isMainFrame == true,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(ProductURLSupport.isZARAURL(url) ? .allow : .cancel)
        }

        func rejectOptionalCookies(in webView: WKWebView) {
            let script = """
            (() => {
              const candidates = Array.from(document.querySelectorAll('button,[role="button"]'));
              const button = candidates.find(node => {
                const text = (node.innerText || node.textContent || '').trim();
                return text.includes('일부 쿠키 차단하기') ||
                  text.includes('Reject non-essential') ||
                  text.includes('Reject optional');
              });
              if (!button) return false;
              button.click();
              return true;
            })();
            """
            webView.evaluateJavaScript(script) { [weak self, weak webView] value, error in
                guard let self, let webView else { return }
                guard error == nil, value as? Bool == true else {
                    onEvent(.failed("cookie_choice_button_not_found"))
                    return
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    self.capture(from: webView)
                }
            }
        }

        func capture(from webView: WKWebView) {
            let script = """
            (() => {
              const analytics = window.zara && window.zara.analyticsData
                ? JSON.stringify(window.zara.analyticsData)
                : null;
              const jsonLD = Array.from(document.querySelectorAll('script[type="application/ld+json"]'))
                .map(node => node.textContent || '')
                .filter(value => value.length > 0);
              const bodyText = (document.body && document.body.innerText) || '';
              const normalizedTitle = (document.title || '').toLowerCase();
              const normalizedBody = bodyText.toLowerCase();
              return JSON.stringify({
                resolvedURL: window.location.href,
                title: document.title || '',
                analyticsJSON: analytics,
                jsonLD: jsonLD,
                challengeDetected: normalizedTitle.includes('access denied') ||
                  normalizedBody.startsWith('access denied') ||
                  window.location.href.includes('bm-verify=')
              });
            })();
            """

            webView.evaluateJavaScript(script) { [weak self] value, error in
                guard let self else { return }
                if let error {
                    onEvent(.failed("javascript_failed: \(error.localizedDescription)"))
                    return
                }
                guard let json = value as? String,
                      let data = json.data(using: .utf8),
                      let snapshot = try? JSONDecoder().decode(ZARAWebMetadataSnapshot.self, from: data),
                      let page = snapshot.makeProductPage() else {
                    onEvent(.failed("structured_data_missing"))
                    return
                }
                onEvent(.captured(page))
            }
        }
    }
}

private struct ZARAWebMetadataSnapshot: Decodable {
    let resolvedURL: String
    let title: String
    let analyticsJSON: String?
    let jsonLD: [String]
    let challengeDetected: Bool

    func makeProductPage() -> ZARAProductPage? {
        guard let url = URL(string: resolvedURL) else { return nil }
        var fragments: [String] = []
        if let analyticsJSON {
            let safeAnalytics = analyticsJSON.replacingOccurrences(of: "</script", with: "<\\/script")
            fragments.append("<script>zara.analyticsData = \(safeAnalytics);</script>")
        }
        for rawJSON in jsonLD {
            let safeJSON = rawJSON.replacingOccurrences(of: "</script", with: "<\\/script")
            fragments.append("<script type=\"application/ld+json\">\(safeJSON)</script>")
        }
        if challengeDetected {
            fragments.append("<div>triggerInterstitialChallenge</div>")
        }
        fragments.append("<title>\(title)</title>")
        return ZARAProductPage(url: url, statusCode: 200, html: fragments.joined())
    }
}

private struct ZARAGuidePresence {
    let hasGarmentMeasurements: Bool
    let hasBodyGuide: Bool

    init(data: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProductURLParserError.automaticParsingUnavailable
        }
        hasGarmentMeasurements = Self.hasNonEmptySizes(object["measureGuideInfo"])
        hasBodyGuide = Self.hasNonEmptySizes(object["sizeGuideInfo"])
    }

    var description: String {
        switch (hasGarmentMeasurements, hasBodyGuide) {
        case (true, true): "both"
        case (true, false): "garment_measure"
        case (false, true): "body_only"
        case (false, false): "empty"
        }
    }

    private static func hasNonEmptySizes(_ value: Any?) -> Bool {
        guard let dictionary = value as? [String: Any],
              let sizes = dictionary["sizes"] as? [Any] else { return false }
        return !sizes.isEmpty
    }
}
#endif
