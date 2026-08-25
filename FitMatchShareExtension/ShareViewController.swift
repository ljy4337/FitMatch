import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private enum AppGroup {
        static let identifier = "group.com.ljy4337.fitmatch"
    }

    private enum Key {
        static let pendingProductURL = "pendingProductURL"
        static let pendingProductURLCreatedAt = "pendingProductURLCreatedAt"
        static let metricsCounters = "FitMatch.metrics.aggregate.v1"
        static let metricsLastUpdatedAt = "FitMatch.metrics.lastUpdatedAt.v1"
    }

    private enum DeepLink {
        static let compareURLString = "fitmatch://compare"
    }

    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let openButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private var isAttemptingOpen = false

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        handleSharedContent()
    }

    private func configureUI() {
        view.backgroundColor = .systemBackground

        let stackView = UIStackView(arrangedSubviews: [
            activityIndicator,
            titleLabel,
            messageLabel,
            openButton,
            closeButton
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 14
        stackView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = "FitMatch에 상품을 추가하고 있어요"
        titleLabel.font = .systemFont(ofSize: 19, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        messageLabel.text = "공유된 상품 URL을 저장하는 중입니다."
        messageLabel.font = .systemFont(ofSize: 14, weight: .regular)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        openButton.setTitle("보러가기", for: .normal)
        openButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        openButton.tintColor = .white
        openButton.backgroundColor = .label
        openButton.layer.cornerRadius = 14
        openButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        openButton.isHidden = true
        openButton.addTarget(self, action: #selector(openButtonTapped), for: .touchUpInside)

        closeButton.setTitle("닫기", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        closeButton.tintColor = .secondaryLabel
        closeButton.isHidden = true
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)

        activityIndicator.startAnimating()

        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func handleSharedContent() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments,
              !attachments.isEmpty
        else {
            showFailureState()
            return
        }

        loadFirstURL(from: attachments) { [weak self] url in
            if let url, self?.isSupportedProductURL(url) == true {
                self?.savePendingURL(url)
                self?.showCompletedState()
            } else {
                self?.showFailureState()
            }
        }
    }

    private func loadFirstURL(from attachments: [NSItemProvider], completion: @escaping (URL?) -> Void) {
        let urlType = UTType.url.identifier
        let plainTextType = UTType.plainText.identifier

        if let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(urlType) }) {
            provider.loadItem(forTypeIdentifier: urlType, options: nil) { item, _ in
                DispatchQueue.main.async {
                    completion(item as? URL)
                }
            }
            return
        }

        if let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(plainTextType) }) {
            provider.loadItem(forTypeIdentifier: plainTextType, options: nil) { item, _ in
                let url = (item as? String).flatMap(self.firstURL(in:))
                DispatchQueue.main.async {
                    completion(url)
                }
            }
            return
        }

        completion(nil)
    }

    private func firstURL(in text: String) -> URL? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        return detector.firstMatch(in: text, range: range)?.url
    }

    private func isSupportedProductURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "musinsa.com"
            || host.hasSuffix(".musinsa.com")
            || host == "musinsa.onelink.me"
            || host == "uniqlo.com"
            || host.hasSuffix(".uniqlo.com")
            || host == "zara.com"
            || host.hasSuffix(".zara.com")
    }

    private func savePendingURL(_ url: URL) {
        guard let defaults = UserDefaults(suiteName: AppGroup.identifier) else { return }
        defaults.set(url.absoluteString, forKey: Key.pendingProductURL)
        defaults.set(Date(), forKey: Key.pendingProductURLCreatedAt)
        recordShareReceived(url: url, defaults: defaults)
        #if DEBUG
        print("[FitMatchShareExtension] saved supported \(metricProvider(for: url)) URL")
        #endif
    }

    private func recordShareReceived(url: URL, defaults: UserDefaults) {
        let counterKey = "share.received|provider=\(metricProvider(for: url))"
        var counters = defaults.dictionary(forKey: Key.metricsCounters)?.compactMapValues {
            ($0 as? NSNumber)?.intValue
        } ?? [:]
        let current = counters[counterKey, default: 0]
        counters[counterKey] = current == Int.max ? Int.max : current + 1
        defaults.set(counters, forKey: Key.metricsCounters)
        defaults.set(Date(), forKey: Key.metricsLastUpdatedAt)
    }

    private func metricProvider(for url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        if host == "musinsa.com" || host.hasSuffix(".musinsa.com") || host == "musinsa.onelink.me" {
            return "musinsa"
        }
        if host == "uniqlo.com" || host.hasSuffix(".uniqlo.com") {
            return "uniqlo"
        }
        if host == "zara.com" || host.hasSuffix(".zara.com") {
            return "zara"
        }
        return "unsupported"
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func showCompletedState() {
        isAttemptingOpen = false
        activityIndicator.stopAnimating()
        titleLabel.text = "상품 링크를 FitMatch에 저장했어요"
        messageLabel.text = "FitMatch 앱에서 내 옷과 사이즈 비교를 이어갈 수 있어요."
        openButton.isEnabled = true
        openButton.setTitle("보러가기", for: .normal)
        openButton.isHidden = false
        closeButton.isHidden = false
        closeButton.setTitle("닫기", for: .normal)
    }

    private func showFailureState() {
        activityIndicator.stopAnimating()
        titleLabel.text = "상품 URL을 추가하지 못했어요"
        messageLabel.text = "상품 페이지 URL을 공유했는지 확인해 주세요."
        openButton.isHidden = true
        closeButton.isHidden = false
    }

    @objc
    private func openButtonTapped() {
        guard !isAttemptingOpen else { return }
        openButton.isEnabled = false
        openButton.setTitle("FitMatch 여는 중", for: .normal)
        messageLabel.text = "FitMatch 앱으로 이동하고 있습니다."
        isAttemptingOpen = true
        openContainingApp()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard self?.isAttemptingOpen == true else { return }
            self?.showOpenRetryState()
        }
    }

    @objc
    private func closeButtonTapped() {
        completeRequest()
    }

    private func openContainingApp() {
        guard let url = URL(string: DeepLink.compareURLString) else {
            showOpenRetryState()
            return
        }

        #if DEBUG
        print("[FitMatchShareExtension] request containing app open")
        #endif

        let didRequestOpen = openURLUsingResponderChain(url) { [weak self] success in
            self?.handleOpenResult(success, url: url, canTryExtensionContext: true)
        }
        if didRequestOpen {
            return
        }

        openURLUsingExtensionContext(url)
    }

    @discardableResult
    private func openURLUsingResponderChain(
        _ url: URL,
        completion: @escaping (Bool) -> Void
    ) -> Bool {
        var responder: UIResponder? = self

        while let currentResponder = responder {
            if let application = currentResponder as? UIApplication {
                #if DEBUG
                print("[FitMatchShareExtension] opening containing app through responder chain")
                #endif
                application.open(url, options: [:], completionHandler: completion)
                return true
            }

            responder = currentResponder.next
        }

        return false
    }

    private func openURLUsingExtensionContext(_ url: URL) {
        guard let extensionContext else {
            showOpenRetryState()
            return
        }

        extensionContext.open(url) { [weak self] success in
            self?.handleOpenResult(success, url: url, canTryExtensionContext: false)
        }
    }

    private func handleOpenResult(
        _ success: Bool,
        url: URL,
        canTryExtensionContext: Bool
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            #if DEBUG
            print("[FitMatchShareExtension] containing app open success: \(success)")
            #endif
            if success {
                self.isAttemptingOpen = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.completeRequest()
                }
            } else if canTryExtensionContext {
                self.openURLUsingExtensionContext(url)
            } else {
                self.showOpenRetryState()
            }
        }
    }

    private func showOpenRetryState() {
        isAttemptingOpen = false
        activityIndicator.stopAnimating()
        titleLabel.text = "상품 링크를 FitMatch에 저장했어요"
        messageLabel.text = "앱을 자동으로 열지 못했어요. 다시 시도해 주세요."
        openButton.isEnabled = true
        openButton.setTitle("FitMatch 다시 열기", for: .normal)
        openButton.isHidden = false
        closeButton.setTitle("닫기", for: .normal)
        closeButton.isHidden = false
    }
}
