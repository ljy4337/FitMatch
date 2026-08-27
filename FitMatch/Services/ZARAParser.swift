import Foundation
import WebKit

enum ZARAIntegrationAvailability {
    /// ZARA URL import is part of the supported product-link flow. Runtime
    /// parsing still fails closed when identity, variant, category, or verified
    /// garment measurements cannot be established.
    static let isEnabled = true
}

struct ZARAProductIdentity: Equatable, Sendable {
    enum ResolutionSource: String, Equatable, Sendable {
        case urlVariantVerifiedByEmbeddedAnalytics = "url_variant_verified_by_embedded_analytics"
        case embeddedAnalyticsSelectedVariant = "embedded_analytics_selected_variant"
    }

    let styleNumber: String
    /// Color/catalog-entry identity published as URL `v1` and analytics
    /// `catentryId`. This is the identifier accepted by size-measure-guide.
    let catentryID: String
    let internalProductID: String
    let productReference: String
    let resolutionSource: ResolutionSource
}

/// ZARA KR publishes actual garment measurements in `measureGuideInfo`.
/// `sizeGuideInfo` contains body-size guidance and is intentionally never
/// converted into FitMatch comparison measurements.
struct ZARAParser: ProductURLParsing, ZARACategoryResumableParsing {
    private let pageLoader: ZARAProductPageLoading
    private let fallbackPageLoader: ZARAProductPageLoading?
    private let sizeGuideLoader: ZARASizeGuideLoading

    init() {
        pageLoader = ZARAProductPageLoader()
        fallbackPageLoader = ZARAWebViewProductPageLoader()
        sizeGuideLoader = ZARASizeGuideLoader()
    }

    init(
        pageLoader: ZARAProductPageLoading,
        sizeGuideLoader: ZARASizeGuideLoading,
        fallbackPageLoader: ZARAProductPageLoading? = nil
    ) {
        self.pageLoader = pageLoader
        self.fallbackPageLoader = fallbackPageLoader
        self.sizeGuideLoader = sizeGuideLoader
    }

    func canParse(_ url: URL) -> Bool {
        ProductURLSupport.isZARAURL(url)
    }

    func parse(from url: URL) async throws -> ParsedProductInfo {
        try await parse(from: url, onProgress: { _ in })
    }

    func parse(
        from url: URL,
        onProgress: @escaping (ProductAnalysisPhase) -> Void
    ) async throws -> ParsedProductInfo {
        try await parseResolved(
            from: url,
            confirmedCategory: nil,
            confirmedDetailCategory: nil,
            onProgress: onProgress
        )
    }

    func parse(
        from url: URL,
        confirmedCategory: ClothingCategory,
        confirmedDetailCategory: ClosetDetailCategory,
        onProgress: @escaping (ProductAnalysisPhase) -> Void
    ) async throws -> ParsedProductInfo {
        guard confirmedCategory != .other,
              confirmedDetailCategory != .other,
              ParsedClosetClassification.resolve(
                category: confirmedCategory,
                detailCategory: confirmedDetailCategory,
                sourceDepths: [],
                sourcePath: nil,
                productName: ""
              )?.isValid == true else {
            throw ProductURLParserError.automaticParsingUnavailable
        }
        return try await parseResolved(
            from: url,
            confirmedCategory: confirmedCategory,
            confirmedDetailCategory: confirmedDetailCategory,
            onProgress: onProgress
        )
    }

    private func parseResolved(
        from url: URL,
        confirmedCategory: ClothingCategory?,
        confirmedDetailCategory: ClosetDetailCategory?,
        onProgress: @escaping (ProductAnalysisPhase) -> Void
    ) async throws -> ParsedProductInfo {
        guard ZARAProductPageParser.styleNumber(from: url) != nil else {
            throw ProductURLParserError.unsupportedURL
        }

        // A shared ZARA URL often publishes the selected colour/catalog entry
        // as `v1`. Ask the official measurement endpoint with that ID first;
        // do not wait for product-page metadata just to rediscover the same ID.
        // The response is only consumed after page structure independently
        // corroborates the style and selected variant.
        let requestedVariantID = ZARAProductPageParser.variantID(from: url)
        var prefetchedSizeGuide: Data?
        if let requestedVariantID {
            onProgress(.loadingSizeChart)
            do {
                prefetchedSizeGuide = try await sizeGuideLoader.load(productID: requestedVariantID)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Product metadata is still useful and a normal browser load
                // may establish the public page context needed by ZARA. Never
                // fabricate a response or try a different colour ID.
                prefetchedSizeGuide = nil
            }
        }

        let (page, identity) = try await loadVerifiedProductPage(from: url)

        var info = ZARAProductPageParser.parse(
            html: page.html,
            sourceURL: page.url,
            identity: identity
        )
        guard !info.productName.isEmpty else {
            throw ProductURLParserError.automaticParsingUnavailable
        }

        if let confirmedCategory, let confirmedDetailCategory {
            info.category = confirmedCategory
            info.detailCategory = confirmedDetailCategory
            info.recoveryAction = nil
            info.parserNotice = "사용자가 선택한 상품 종류로 ZARA 실측표를 다시 확인했어요."
        }
        guard info.category != .other, info.detailCategory != .other else {
            info.measurementAvailability = .unavailable
            info.recoveryAction = .confirmCategoryBeforeMeasurements
            throw ProductURLParserPartialError(
                productInfo: info.withNotice(
                    "ZARA 공식 분류만으로 상품 종류를 확정할 수 없어요. 상품 종류를 선택하면 실측 분석을 이어갈게요."
                )
            )
        }

        onProgress(.loadingSizeChart)
        do {
            let data: Data
            if identity.catentryID == requestedVariantID,
               let prefetchedSizeGuide {
                data = prefetchedSizeGuide
            } else {
                data = try await sizeGuideLoader.load(productID: identity.catentryID)
            }
            let sizes = try ZARASizeGuideParser.parseActualGarmentMeasurements(
                data: data,
                category: info.category
            )
            guard !sizes.isEmpty else { throw ProductURLParserError.automaticParsingUnavailable }

            var resolved = info
            resolved.sizes = sizes
            guard ZARASizeGuideParser.hasComparisonReadySize(
                sizes,
                category: info.category
            ) else {
                resolved.measurementAvailability = .unavailable
                resolved.recoveryAction = .enterMeasurementsManually
                throw ProductURLParserPartialError(
                    productInfo: resolved.withNotice(
                        "ZARA 의류 실측 후보는 확인했지만 측정 기준이 아직 검증되지 않았어요. 안전하게 직접 입력해 주세요."
                    )
                )
            }
            resolved.measurementAvailability = .actualMeasurements
            return resolved
        } catch is CancellationError {
            throw CancellationError()
        } catch let partialError as ProductURLParserPartialError {
            throw partialError
        } catch {
            var unresolved = info
            unresolved.measurementAvailability = .unavailable
            unresolved.recoveryAction = .enterMeasurementsManually
            throw ProductURLParserPartialError(
                productInfo: unresolved.withNotice(
                    "상품 정보는 불러왔지만 ZARA 공식 의류 실측표를 확인하지 못했어요. 사이즈를 직접 입력해 주세요."
                )
            )
        }
    }

    private func loadVerifiedProductPage(
        from requestedURL: URL
    ) async throws -> (ZARAProductPage, ZARAProductIdentity) {
        do {
            let page = try await pageLoader.load(url: requestedURL)
            if let identity = verifiedIdentity(for: page, requestedURL: requestedURL) {
                return (page, identity)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Continue to the ordinary WebKit fallback below. The fallback
            // uses an ephemeral browser context and stops if the visible page
            // is an access-denied/challenge response.
        }

        guard let fallbackPageLoader else {
            throw ProductURLParserError.automaticParsingUnavailable
        }
        let fallbackPage = try await fallbackPageLoader.load(url: requestedURL)
        guard let identity = verifiedIdentity(
            for: fallbackPage,
            requestedURL: requestedURL
        ) else {
            throw ProductURLParserError.automaticParsingUnavailable
        }
        return (fallbackPage, identity)
    }

    private func verifiedIdentity(
        for page: ZARAProductPage,
        requestedURL: URL
    ) -> ZARAProductIdentity? {
        guard page.statusCode == 200,
              !ZARAProductPageParser.isBotChallenge(page.html) else {
            return nil
        }
        return ZARAProductPageParser.identity(
            requestedURL: requestedURL,
            resolvedURL: page.url,
            html: page.html
        )
    }
}

protocol ZARAProductPageLoading: Sendable {
    func load(url: URL) async throws -> ZARAProductPage
}

struct ZARAProductPage: Sendable {
    let url: URL
    let statusCode: Int
    let html: String
}

struct ZARAProductPageLoader: ZARAProductPageLoading {
    func load(url: URL) async throws -> ZARAProductPage {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("ko-KR,ko;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(ZARARequestHeaders.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        return ZARAProductPage(
            url: response.url ?? url,
            statusCode: httpResponse?.statusCode ?? -1,
            html: String(data: data, encoding: .utf8) ?? ""
        )
    }
}

/// Browser-compatible fallback for ZARA pages whose public structured product
/// data is created by JavaScript or is not returned to a plain URLSession.
/// It uses an ephemeral WebKit data store, follows only official ZARA hosts,
/// captures structured scripts instead of DOM copy, and never attempts to
/// solve or bypass an access challenge.
struct ZARAWebViewProductPageLoader: ZARAProductPageLoading {
    func load(url: URL) async throws -> ZARAProductPage {
        try await ZARAWebViewPageCaptureOperation.capture(url: url)
    }
}

@MainActor
private final class ZARAWebViewPageCaptureOperation: NSObject, WKNavigationDelegate {
    private struct Snapshot: Decodable {
        let url: String
        let title: String
        let bodyExcerpt: String
        let analyticsScript: String
        let jsonLD: [String]
    }

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<ZARAProductPage, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var captureAttempts = 0
    private var requestedURL: URL?

    static func capture(url: URL) async throws -> ZARAProductPage {
        let operation = ZARAWebViewPageCaptureOperation()
        return try await operation.start(url: url)
    }

    private func start(url: URL) async throws -> ZARAProductPage {
        guard ProductURLSupport.isZARAURL(url) else {
            throw ProductURLParserError.unsupportedURL
        }
        requestedURL = url
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = .nonPersistent()
                configuration.defaultWebpagePreferences.allowsContentJavaScript = true
                let webView = WKWebView(frame: .zero, configuration: configuration)
                webView.navigationDelegate = self
                self.webView = webView
                timeoutTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(25))
                    self?.finish(.failure(ProductURLParserError.automaticParsingUnavailable))
                }
                webView.load(URLRequest(url: url, timeoutInterval: 25))
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        scheduleCapture(after: .milliseconds(600))
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        guard !Self.isCancelledNavigation(error) else { return }
        finish(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        // WKWebView reports the superseded navigation as NSURLErrorCancelled
        // when ZARA replaces a short `/item-p...` URL with its canonical
        // localized product URL. The replacement navigation continues and is
        // not an access failure.
        guard !Self.isCancelledNavigation(error) else { return }
        finish(.failure(error))
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

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if let response = navigationResponse.response as? HTTPURLResponse,
           [401, 403, 429].contains(response.statusCode) {
            decisionHandler(.cancel)
            finish(.failure(ProductURLParserError.automaticParsingUnavailable))
            return
        }
        decisionHandler(.allow)
    }

    private func scheduleCapture(after delay: Duration) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            self?.captureStructuredPage()
        }
    }

    private func captureStructuredPage() {
        guard continuation != nil, let webView else { return }
        let script = #"""
        (() => JSON.stringify({
          url: window.location.href,
          title: document.title || '',
          bodyExcerpt: (document.body?.innerText || '').slice(0, 4000),
          analyticsScript: Array.from(document.scripts)
            .map(node => node.textContent || '')
            .find(text => /zara\.analyticsData\s*=\s*\{/.test(text)) || '',
          jsonLD: Array.from(document.querySelectorAll('script[type="application/ld+json"]'))
            .map(node => node.textContent || '')
        }))();
        """#
        webView.evaluateJavaScript(script) { [weak self] value, error in
            Task { @MainActor in
                guard let self, self.continuation != nil else { return }
                guard error == nil,
                      let text = value as? String,
                      let data = text.data(using: .utf8),
                      let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
                      let resolvedURL = URL(string: snapshot.url),
                      ProductURLSupport.isZARAURL(resolvedURL) else {
                    self.retryOrFail()
                    return
                }

                let visibleText = "\(snapshot.title) \(snapshot.bodyExcerpt)".lowercased()
                guard !resolvedURL.absoluteString.lowercased().contains("bm-verify="),
                      !visibleText.contains("access denied") else {
                    self.finish(.failure(ProductURLParserError.automaticParsingUnavailable))
                    return
                }

                var fragments: [String] = []
                if !snapshot.analyticsScript.isEmpty {
                    fragments.append("<script>\(snapshot.analyticsScript)</script>")
                }
                for rawJSON in snapshot.jsonLD {
                    let safeJSON = rawJSON.replacingOccurrences(of: "</script", with: "<\\/script")
                    fragments.append("<script type=\"application/ld+json\">\(safeJSON)</script>")
                }
                fragments.append("<title>\(snapshot.title)</title>")
                let page = ZARAProductPage(
                    url: resolvedURL,
                    statusCode: 200,
                    html: fragments.joined()
                )
                if let requestedURL = self.requestedURL,
                   ZARAProductPageParser.identity(
                    requestedURL: requestedURL,
                    resolvedURL: resolvedURL,
                    html: page.html
                   ) != nil {
                    self.finish(.success(page))
                } else {
                    self.retryOrFail()
                }
            }
        }
    }

    private func retryOrFail() {
        captureAttempts += 1
        guard captureAttempts < 5 else {
            finish(.failure(ProductURLParserError.automaticParsingUnavailable))
            return
        }
        scheduleCapture(after: .milliseconds(500))
    }

    private func finish(_ result: Result<ZARAProductPage, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        continuation.resume(with: result)
    }

    private static func isCancelledNavigation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
            && nsError.code == NSURLErrorCancelled
    }
}

protocol ZARASizeGuideLoading: Sendable {
    func load(productID: String) async throws -> Data
}

struct ZARASizeGuideLoader: ZARASizeGuideLoading {
    func load(productID: String) async throws -> Data {
        guard productID.range(of: #"^\d+$"#, options: .regularExpression) != nil,
              let url = URL(string: "https://www.zara.com/itxrest/4/catalog/store/11717/product/\(productID)/size-measure-guide?locale=ko_KR") else {
            throw ProductURLParserError.automaticParsingUnavailable
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ko-KR,ko;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(ZARARequestHeaders.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ProductURLParserError.automaticParsingUnavailable
        }
        return data
    }
}

private enum ZARARequestHeaders {
    // This endpoint returns 403 without a User-Agent. Keep the request
    // identity explicit and test it on a physical iPhone before release.
    static let userAgent = "FitMatch/1.0 (iPhone; iOS 18.0)"
}

enum ZARAProductPageParser {
    static func styleNumber(from url: URL) -> String? {
        firstMatch(in: url.absoluteString, pattern: #"-p(\d{8})\.html"#)
    }

    static func variantID(from url: URL) -> String? {
        guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "v1" })?
            .value,
              value.range(of: #"^\d+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return value
    }

    static func identity(
        requestedURL: URL,
        resolvedURL: URL,
        html: String
    ) -> ZARAProductIdentity? {
        guard let requestedStyle = styleNumber(from: requestedURL) else { return nil }
        let resolvedStyle = styleNumber(from: resolvedURL) ?? requestedStyle
        guard requestedStyle == resolvedStyle,
              let analytics = analyticsObject(in: html),
              let internalProductID = firstMatch(
                in: analytics,
                pattern: #"\"productId\"\s*:\s*(\d+)"#
              ),
              let productReference = firstMatch(
                in: analytics,
                pattern: #"\"productRef\"\s*:\s*\"([^\"]+)\""#
              ),
              let analyticsVariantID = firstMatch(
                in: analytics,
                pattern: #"\"catentryId\"\s*:\s*(\d+)"#
              ) else {
            return nil
        }

        guard let productReferenceStyle = firstMatch(
            in: productReference,
            pattern: #"^(\d{8})(?:-|$)"#
        ), productReferenceStyle == resolvedStyle else {
            return nil
        }

        let requestedVariantID = variantID(from: resolvedURL) ?? variantID(from: requestedURL)
        if let requestedVariantID, requestedVariantID != analyticsVariantID {
            return nil
        }

        // Current ZARA KR product pages publish the same style/colour identity
        // independently in ProductGroup JSON-LD. When that richer structured
        // contract is present, use it as corroboration instead of trusting one
        // analytics object silently. Legacy captures without these fields stay
        // readable, but contradictory structured facts fail closed.
        if let jsonLD = productJSONLD(in: html) {
            if let structuredStyle = string(jsonLD["productGroupID"]),
               structuredStyle != resolvedStyle {
                return nil
            }

            let structuredVariantIDs = variantIDs(in: jsonLD["hasVariant"])
            if !structuredVariantIDs.isEmpty,
               !structuredVariantIDs.contains(analyticsVariantID) {
                return nil
            }
        }

        return ZARAProductIdentity(
            styleNumber: resolvedStyle,
            catentryID: analyticsVariantID,
            internalProductID: internalProductID,
            productReference: productReference,
            resolutionSource: requestedVariantID == nil
                ? .embeddedAnalyticsSelectedVariant
                : .urlVariantVerifiedByEmbeddedAnalytics
        )
    }

    static func isBotChallenge(_ html: String) -> Bool {
        let normalized = html.lowercased()
        if normalized.contains("bm-verify=")
            || normalized.contains("<title>access denied")
            || normalized.contains("<h1>access denied") {
            return true
        }

        // ZARA's normal product application bundles currently contain the
        // symbol `triggerInterstitialChallenge` even when the visible product
        // page loaded successfully. Treat it as a challenge only when the page
        // has no independently parseable product structure.
        return normalized.contains("triggerinterstitialchallenge")
            && analyticsObject(in: html) == nil
            && productJSONLD(in: html) == nil
    }

    static func parse(
        html: String,
        sourceURL: URL,
        identity: ZARAProductIdentity
    ) -> ParsedProductInfo {
        let analytics = analyticsObject(in: html) ?? ""
        let jsonLD = productJSONLD(in: html)
        let productName = string(jsonLD?["name"])
            ?? firstMatch(in: analytics, pattern: #"\"productName\"\s*:\s*\"([^\"]+)\""#)
            ?? ""
        let imageURL = stringArray(jsonLD?["image"]).first
        let price = firstMatch(in: analytics, pattern: #"\"mainPrice\"\s*:\s*(\d+)"#)
            .flatMap(Int.init)
            ?? offerPrice(jsonLD?["hasVariant"])
            ?? offerPrice(jsonLD?["offers"])
        let section = firstMatch(in: analytics, pattern: #"\"section\"\s*:\s*\"([^\"]+)\""#) ?? "UNKNOWN"
        let family = firstMatch(in: analytics, pattern: #"\"family\"\s*:\s*\"([^\"]+)\""#)
        let subfamily = firstMatch(in: analytics, pattern: #"\"subfamily\"\s*:\s*\"([^\"]+)\""#)
        let classification = ZARACategoryClassifier.classify(
            section: section,
            family: family,
            subfamily: subfamily,
            styleNumber: identity.styleNumber
        )

        var metadata = ProductMetadata()
        metadata.styleNo = identity.styleNumber
        metadata.externalVariantID = identity.catentryID
        metadata.externalProductReference = identity.productReference
        metadata.variantSelectionMethod = identity.resolutionSource.rawValue
        metadata.variantSelectionConfidence = identity.resolutionSource
            == .urlVariantVerifiedByEmbeddedAnalytics ? 1 : 0.9
        metadata.categoryMappingPolicyVersion = ZARACategoryClassifier.policyVersion
        metadata.brandCode = "zara"
        metadata.brandEnglishName = "ZARA"
        metadata.sourceCategoryPath = classification.path
        metadata.sourceCategoryDepth1 = classification.sectionName
        metadata.sourceCategoryDepth2 = family
        metadata.sourceCategoryDepth3 = subfamily
        metadata.categoryDepth1Code = section
        metadata.categoryDepth1Name = classification.sectionName
        metadata.categoryDepth2Code = family.map { "\(section):\($0)" }
        metadata.categoryDepth2Name = family
        metadata.categoryDepth3Code = subfamily.map { "\(section):\(family ?? "unknown"):\($0)" }
        metadata.categoryDepth3Name = subfamily
        metadata.structuredFacts = [
            "section": section,
            "family": family,
            "subfamily": subfamily
        ].compactMapValues { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        metadata.genderCodes = [classification.gender.taxonomyCode]
        metadata.imageURLStrings = imageURL.map { [$0] } ?? []
        metadata.finalPrice = price
        metadata.normalPrice = price
        metadata.currencyCode = "KRW"

        return ParsedProductInfo(
            sourceURL: sourceURL,
            sourceType: .officialStore,
            sourceName: "ZARA 공식몰",
            brandName: "ZARA",
            productName: productName,
            category: classification.category,
            detailCategory: classification.detailCategory,
            sizes: [],
            productID: identity.internalProductID,
            imageURLString: imageURL,
            price: price,
            canonicalURLString: sourceURL.absoluteString,
            sourceCategoryPath: classification.path,
            sourceCategoryDepth1: classification.sectionName,
            sourceCategoryDepth2: family,
            sourceCategoryDepth3: subfamily,
            productTargetGender: classification.gender,
            productMetadata: metadata,
            measurementAvailability: .unavailable
        )
    }

    private static func analyticsObject(in html: String) -> String? {
        let source = html as NSString
        guard let regex = try? NSRegularExpression(
            pattern: #"zara\.analyticsData\s*=\s*\{"#,
            options: [.caseInsensitive]
        ),
              let match = regex.firstMatch(
                in: html,
                range: NSRange(html.startIndex..<html.endIndex, in: html)
              ) else {
            return nil
        }
        let objectStart = NSMaxRange(match.range) - 1
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        for offset in objectStart..<source.length {
            let character = source.character(at: offset)
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == 92 { // backslash
                    isEscaped = true
                } else if character == 34 { // quote
                    isInsideString = false
                }
                continue
            }
            if character == 34 {
                isInsideString = true
            } else if character == 123 { // opening brace
                depth += 1
            } else if character == 125 { // closing brace
                depth -= 1
                if depth == 0 {
                    return source.substring(
                        with: NSRange(location: objectStart, length: offset - objectStart + 1)
                    )
                }
            }
        }
        return nil
    }

    private static func productJSONLD(in html: String) -> [String: Any]? {
        let scripts = matches(in: html, pattern: #"<script[^>]+type=[\"']application/ld\+json[\"'][^>]*>(.*?)</script>"#)
        for script in scripts {
            guard let data = script.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let dictionary = object as? [String: Any],
               string(dictionary["@type"])?.localizedCaseInsensitiveContains("product") == true {
                return dictionary
            }
        }
        return nil
    }

    private static func offerPrice(_ value: Any?) -> Int? {
        if let dictionary = value as? [String: Any] {
            if let price = integer(dictionary["price"]) { return price }
            if let variants = dictionary["hasVariant"] as? [Any] {
                return variants.compactMap { offerPrice($0) }.first
            }
            if let offer = dictionary["offers"] { return offerPrice(offer) }
        }
        if let values = value as? [Any] { return values.compactMap { offerPrice($0) }.first }
        return nil
    }

    private static func variantIDs(in value: Any?) -> Set<String> {
        if let dictionary = value as? [String: Any] {
            var result = Set<String>()
            if let urlString = string(dictionary["url"]),
               let url = URL(string: urlString),
               let variantID = variantID(from: url) {
                result.insert(variantID)
            }
            for nestedKey in ["offers", "hasVariant"] {
                result.formUnion(variantIDs(in: dictionary[nestedKey]))
            }
            return result
        }
        if let values = value as? [Any] {
            return values.reduce(into: Set<String>()) { result, item in
                result.formUnion(variantIDs(in: item))
            }
        }
        return []
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? String, let decimal = Double(value) { return Int(decimal) }
        return nil
    }

    nonisolated private static func string(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stringArray(_ value: Any?) -> [String] {
        if let value = string(value) { return [value] }
        return (value as? [Any])?.compactMap(string) ?? []
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).replacingOccurrences(of: #"\\\""#, with: "\"")
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).compactMap {
            guard $0.numberOfRanges > 1, let range = Range($0.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }
}

private enum ZARASizeGuideParser {
    private static let mappingVersion = "zara_kr_measure_guide_verified_subset_v4"

    static func parseActualGarmentMeasurements(
        data: Data,
        category: ClothingCategory
    ) throws -> [ParsedProductSize] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let guide = response.measureGuideInfo, !guide.sizes.isEmpty else {
            // `sizeGuideInfo` is intentionally not a fallback: its values are
            // body-size guidance, not product garment measurements.
            throw ProductURLParserError.automaticParsingUnavailable
        }

        return guide.sizes.compactMap { size in
            let records = size.measures.compactMap { measure -> ParsedMeasurement? in
                guard let dimension = measure.dimensions.first(where: { $0.unitID == "cm" }),
                      let value = Double(dimension.value), value.isFinite, value > 0 else { return nil }
                let mapping = verifiedMapping(
                    for: measure.tableTitleZone,
                    category: category.serviceGroup
                )
                let rawInfo = [
                    "raw_zone_id=\(measure.zoneID)",
                    measure.descriptionZone,
                    mapping.map {
                        "canonical=\($0.code.rawValue);basis_status=VERIFIED"
                    }
                ].compactMap { $0 }.joined(separator: ";")
                return ParsedMeasurement(
                    value: value,
                    measurementCode: mapping?.code ?? .unknown,
                    displayKind: mapping?.displayKind ?? .unknown,
                    methodSource: "zara",
                    methodProfile: "zara_kr_measure_guide",
                    inputSource: .importedSizeChart,
                    mappingVersion: mappingVersion,
                    // `zoneId` (A/B/C...) changes meaning by garment family.
                    // Keep the stable semantic key as rawCode and preserve the
                    // original zone ID in rawInfo.
                    rawCode: measure.tableTitleZone,
                    rawLabel: measure.tableTitleZone,
                    rawInfo: rawInfo.isEmpty ? nil : rawInfo,
                    rawValueText: dimension.value,
                    evidenceLevel: mapping == nil ? .unknown : .officialText,
                    semanticStatus: mapping == nil ? .unknownDefinition : .mapped
                )
            }
            guard !records.isEmpty else { return nil }
            return ParsedProductSize(
                id: ParsedProductSize.stableID(for: size.name),
                name: size.name,
                measurements: GarmentMeasurements(
                    shoulder: firstValue(.shoulder, records),
                    chest: firstValue(.chest, records),
                    totalLength: firstValue(.totalLength, records),
                    sleeveLength: firstValue(.sleeveLength, records),
                    waist: firstValue(.waist, records),
                    hip: firstValue(.hip, records),
                    thigh: firstValue(.thigh, records),
                    rise: firstValue(.rise, records),
                    hem: firstValue(.hem, records)
                ),
                measurementRecords: records
            )
        }
    }

    static func hasComparisonReadySize(
        _ sizes: [ParsedProductSize],
        category: ClothingCategory
    ) -> Bool {
        sizes.contains { size in
            let mappedKinds = Set(
                size.measurementRecords.compactMap { record in
                    record.semanticStatus == .mapped ? record.displayKind : nil
                }
            )
            switch category.serviceGroup {
            case .top:
                return mappedKinds.count >= 2
                    && !mappedKinds.intersection([.shoulder, .chest]).isEmpty
            case .outer:
                return mappedKinds.count >= 2 && mappedKinds.contains(.chest)
            case .bottom:
                return mappedKinds.contains(.waist) && mappedKinds.contains(.hip)
            case .dress:
                return mappedKinds.intersection([.chest, .waist, .hip]).count >= 2
            default:
                return false
            }
        }
    }

    /// ZARA's official KR modal says these are garment measurements taken with
    /// the item laid flat. The reviewed upper-garment instructions define chest
    /// edge-to-edge at armhole height, back width between shoulder sleeve seams,
    /// and sleeve length from that seam to the cuff. Front length starts at a
    /// shoulder seam (not the existing HPS contract), while arm width has no
    /// canonical FitMatch code, so those two fields remain raw-only.
    private static func verifiedMapping(
        for rawCode: String,
        category: ClothingCategory
    ) -> (code: MeasurementCode, displayKind: MeasurementDisplayKind)? {
        switch (category, rawCode.lowercased()) {
        case (.top, "zone-name-chest"), (.outer, "zone-name-chest"):
            return (.chestWidthPitToPit, .chest)
        case (.top, "zone-name-back-width"), (.outer, "zone-name-back-width"):
            return (.shoulderWidthSeamToSeam, .shoulder)
        case (.top, "zone-name-sleeve-length"), (.outer, "zone-name-sleeve-length"):
            return (.sleeveShoulderSeamToCuff, .sleeveLength)
        case (.bottom, "zone-name-waist"):
            return (.waistWidthEdgeToEdge, .waist)
        case (.bottom, "zone-name-hips"):
            return (.hipWidthAtWidest, .hip)
        case (.bottom, "zone-name-front-rise"):
            return (.riseCrotchToWaistFront, .rise)
        case (.dress, "zone-name-chest"):
            return (.chestWidthPitToPit, .chest)
        case (.dress, "zone-name-waist-full-body"):
            return (.waistWidthEdgeToEdge, .waist)
        case (.dress, "zone-name-hips"):
            return (.hipWidthAtWidest, .hip)
        default:
            return nil
        }
    }

    private static func firstValue(_ kind: MeasurementDisplayKind, _ records: [ParsedMeasurement]) -> Double {
        records.first(where: { $0.displayKind == kind })?.value ?? 0
    }

    private struct Response: Decodable {
        let measureGuideInfo: Guide?
    }

    private struct Guide: Decodable {
        let sizes: [Size]
    }

    private struct Size: Decodable {
        let name: String
        let measures: [Measure]
    }

    private struct Measure: Decodable {
        let zoneID: String
        let tableTitleZone: String
        let descriptionZone: String?
        let dimensions: [Dimension]

        enum CodingKeys: String, CodingKey {
            case zoneID = "zoneId"
            case tableTitleZone
            case descriptionZone
            case dimensions
        }
    }

    private struct Dimension: Decodable {
        let unitID: String
        let value: String

        enum CodingKeys: String, CodingKey {
            case unitID = "unitId"
            case value
        }
    }
}

enum ZARACategoryClassifier {
    /// Mirrors the reviewed ZARA source-category contract. Exact structured
    /// paths are authoritative; broad family inference remains a fail-closed
    /// embedded fallback for offline/new-category handling.
    static let policyVersion = "zara-kr-structured-category-2026-08-25-v5"

    private struct ExactMapping {
        let category: ClothingCategory
        let detail: ClosetDetailCategory
    }

    private static let exactMappings: [String: ExactMapping] = [
        "MAN|셔츠|B. Camisería": .init(category: .top, detail: .shirt),
        "MAN|셔츠|F. Camisería": .init(category: .top, detail: .shirt),
        "MAN|브레이저|Blasier": .init(category: .outer, detail: .blazer),
        "MAN|바지|F. Pant Resto": .init(category: .bottom, detail: .longPants),
        "MAN|바지|B. Pant Denim": .init(category: .bottom, detail: .denim),
        "MAN|스웨터|B. Jersey M/C": .init(category: .top, detail: .knitTop),
        "MAN|스포츠 재킷|B. Cazadora": .init(category: .outer, detail: .jacket),
        "MAN|버뮤다반바지|F.Bermuda Resto": .init(category: .bottom, detail: .shorts),
        "MAN|BERMUDA|ATH Bottoms": .init(category: .bottom, detail: .shorts),
        "MAN|BERMUDA|ATH Short": .init(category: .bottom, detail: .shorts),
        "MAN|BERMUDA|B. Bermuda Rest": .init(category: .bottom, detail: .shorts),
        "MAN|BERMUDA|Bermuda Denim": .init(category: .bottom, detail: .denim),
        "MAN|BERMUDA|F.Bermuda Rest": .init(category: .bottom, detail: .shorts),
        "MAN|PANTY/UNDERPANT|ATH Underwear": .init(category: .underwear, detail: .menBriefs),
        "MAN|PANTY/UNDERPANT|Underwear": .init(category: .underwear, detail: .menBriefs),
        "MAN|스웨트 셔츠|F. Sudadera": .init(category: .top, detail: .sweatshirt),
        "MAN|티셔츠|F. Camiseta": .init(category: .top, detail: .shortSleeve),
        "MAN|티셔츠|Camiseta M/L": .init(category: .top, detail: .longSleeve),
        "MAN|바지|Sastrería Pant.": .init(category: .bottom, detail: .longPants),
        "MAN|스포츠 재킷|F. Cazadora": .init(category: .outer, detail: .jacket),
        "WOMAN|티셔츠|C.CTAS BASICAS": .init(category: .top, detail: .shortSleeve),
        "WOMAN|티셔츠|C.CTAS FANTASI": .init(category: .top, detail: .shortSleeve),
        "WOMAN|티셔츠|C.CTAS POSICIO": .init(category: .top, detail: .shortSleeve),
        "WOMAN|드레스|C.VESTIDO FANTA": .init(category: .dress, detail: .onePiece),
        "WOMAN|드레스|B.DRESS": .init(category: .dress, detail: .onePiece),
        "WOMAN|드레스|W.DRESS": .init(category: .dress, detail: .onePiece),
        "WOMAN|셔츠|B.SHIRT": .init(category: .top, detail: .shirt),
        "WOMAN|가디건|KNIT CARDIGAN": .init(category: .outer, detail: .cardigan),
        "WOMAN|스포츠 재킷|T.SHORT-OUTWEAR": .init(category: .outer, detail: .jacket),
        "WOMAN|버뮤다반바지|T.BERMUDAS": .init(category: .bottom, detail: .shorts),
        "WOMAN|BERMUDA|C-LEGGING": .init(category: .bottom, detail: .shorts),
        "WOMAN|BERMUDA|ST. BERMUDA": .init(category: .bottom, detail: .shorts),
        "WOMAN|BERMUDA|W.BERMUDAS": .init(category: .bottom, detail: .shorts),
        "WOMAN|BRA|SUJE CON B": .init(category: .underwear, detail: .womenBra),
        "WOMAN|BRA|SUJETADOR": .init(category: .underwear, detail: .womenBra),
        "WOMAN|PANTY/UNDERPANT|BRAGA": .init(category: .underwear, detail: .womenPanty),
        "WOMAN|브레이저|B.BLAZER": .init(category: .outer, detail: .blazer),
        "WOMAN|치마|T.SKIRT": .init(category: .bottom, detail: .skirt),
        "WOMAN|바지|B.PANTS": .init(category: .bottom, detail: .longPants),
        "WOMAN|바지|C.PTON-LEGGING": .init(category: .bottom, detail: .longPants),
        "WOMAN|바지|L. PANT. PIJAMA": .init(category: .bottom, detail: .longPants),
        "WOMAN|스포츠 재킷|B.SHORT-OUTWEAR": .init(category: .outer, detail: .jacket)
    ]

    /// User-reviewed exceptions are scoped to the stable URL style number.
    /// The same ZARA subfamily can contain structurally different garments,
    /// so these decisions must not rewrite every product in that subfamily.
    private static let exactProductMappings: [String: ExactMapping] = [
        "01934230": .init(category: .bottom, detail: .denim),
        "07782343": .init(category: .outer, detail: .jacket)
    ]

    static func classify(
        section: String,
        family: String?,
        subfamily: String?,
        styleNumber: String? = nil
    ) -> Classification {
        let haystack = [family, subfamily].compactMap { $0 }.joined(separator: " ").lowercased()
        let gender: UserGender = section.uppercased() == "MAN" ? .men : (section.uppercased() == "WOMAN" ? .women : .unknown)
        let sectionName = gender == .men ? "남성" : (gender == .women ? "여성" : section)
        let path = (["ZARA", sectionName, family, subfamily].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).joined(separator: " > ")

        guard gender != .unknown,
              !isMixedFamily(haystack),
              !isExcludedFamily(haystack) else {
            return Classification(
                sectionName: sectionName,
                gender: gender,
                category: .other,
                detailCategory: .other,
                path: path
            )
        }

        if let styleNumber,
           let exact = exactProductMappings[styleNumber] {
            return Classification(
                sectionName: sectionName,
                gender: gender,
                category: exact.category,
                detailCategory: exact.detail,
                path: path
            )
        }

        if let family, let subfamily,
           let exact = exactMappings["\(section.uppercased())|\(family)|\(subfamily)"] {
            return Classification(
                sectionName: sectionName,
                gender: gender,
                category: exact.category,
                detailCategory: exact.detail,
                path: path
            )
        }

        // Generic fallback must not let a source family and leaf that describe
        // different garment domains silently choose whichever keyword happens
        // to be checked first. Reviewed exact mappings above remain authoritative.
        if hasStructuredDomainConflict(family: family, subfamily: subfamily) {
            return Classification(
                sectionName: sectionName,
                gender: gender,
                category: .other,
                detailCategory: .other,
                path: path
            )
        }

        let category: ClothingCategory
        let detail: ClosetDetailCategory

        if contains(haystack, ["dress", "드레스", "원피스"]) { category = .dress; detail = .onePiece }
        else if contains(haystack, ["skirt", "스커트", "치마"]) { category = .bottom; detail = .skirt }
        else if contains(haystack, ["coat", "코트"]) { category = .outer; detail = .coat }
        else if contains(haystack, ["blazer", "블레이저", "브레이저"]) { category = .outer; detail = .blazer }
        else if contains(haystack, ["jacket", "재킷", "자켓"]) { category = .outer; detail = .jacket }
        else if contains(haystack, ["cardigan", "가디건"]) { category = .outer; detail = .cardigan }
        // Do not match bare "short": it appears in terms such as "short sleeve".
        else if contains(haystack, ["shorts", "쇼츠", "반바지", "버뮤다"]) { category = .bottom; detail = .shorts }
        else if contains(haystack, ["jean", "denim", "진", "데님"]) { category = .bottom; detail = .denim }
        else if contains(haystack, ["trouser", "pants", "바지", "팬츠"]) { category = .bottom; detail = .longPants }
        else if contains(haystack, ["polo", "폴로"]) { category = .top; detail = .poloShirt }
        else if contains(haystack, ["tank", "sleeveless", "민소매", "탱크"]) { category = .top; detail = .sleeveless }
        else if contains(haystack, ["long sleeve", "긴팔"]) { category = .top; detail = .longSleeve }
        else if contains(haystack, ["t-shirt", "tshirt", "티셔츠"]) { category = .top; detail = .shortSleeve }
        else if contains(haystack, ["sweat", "스웨트", "맨투맨"]) { category = .top; detail = .sweatshirt }
        else if contains(haystack, ["hood", "후드"]) { category = .top; detail = .hoodie }
        else if contains(haystack, ["shirt", "셔츠"]) { category = .top; detail = .shirt }
        else if contains(haystack, ["knit", "sweater", "니트", "스웨터"]) { category = .top; detail = .knitTop }
        else { category = .other; detail = .other }

        return Classification(sectionName: sectionName, gender: gender, category: category, detailCategory: detail, path: path)
    }

    private static func isMixedFamily(_ value: String) -> Bool {
        contains(value, [
            "탑 | 바디수트", "top | bodysuit", "top | body",
            "스웨트셔츠 | 조거 팬츠", "sweatshirt | jogger",
            // Shadow corpus proves these source families span multiple FitMatch
            // domains or require a taxonomy decision that is still review-only.
            "tops and others", "overall", "jumpsuit", "점프수트",
            "overshirt", "오버셔츠", "waistcoat"
        ])
    }

    private static func hasStructuredDomainConflict(family: String?, subfamily: String?) -> Bool {
        guard let familyDomain = inferredDomain(from: family),
              let subfamilyDomain = inferredDomain(from: subfamily) else {
            return false
        }
        return familyDomain.serviceGroup != subfamilyDomain.serviceGroup
    }

    private static func inferredDomain(from value: String?) -> ClothingCategory? {
        guard let value else { return nil }
        let normalized = value.lowercased()

        if contains(normalized, ["dress", "드레스", "원피스"]) { return .dress }
        if contains(normalized, ["skirt", "스커트", "치마"]) { return .bottom }
        if contains(normalized, ["coat", "코트", "blazer", "블레이저", "브레이저",
                                 "jacket", "재킷", "자켓", "cardigan", "가디건"]) { return .outer }
        if contains(normalized, ["shorts", "쇼츠", "반바지", "버뮤다", "jean", "denim",
                                 "데님", "trouser", "pants", "바지", "팬츠", "legging"]) { return .bottom }
        if contains(normalized, ["polo", "폴로", "tank", "sleeveless", "민소매", "탱크",
                                 "t-shirt", "tshirt", "티셔츠", "sweat", "스웨트", "맨투맨",
                                 "hood", "후드", "shirt", "셔츠", "knit", "sweater", "니트", "스웨터"]) { return .top }
        return nil
    }

    private static func isExcludedFamily(_ value: String) -> Bool {
        contains(value, [
            "accessory", "액세서리", "perfume", "향수", "beauty", "뷰티",
            "home", "홈", "campaign", "캠페인", "view all", "모두 보기",
            "bag", "백", "shoe", "슈즈"
        ])
    }

    private static func contains(_ text: String, _ values: [String]) -> Bool {
        values.contains { text.contains($0) }
    }

    struct Classification {
        let sectionName: String
        let gender: UserGender
        let category: ClothingCategory
        let detailCategory: ClosetDetailCategory
        let path: String
    }
}

private extension ParsedProductInfo {
    func withNotice(_ notice: String) -> ParsedProductInfo {
        var copy = self
        copy.parserNotice = notice
        return copy
    }
}
