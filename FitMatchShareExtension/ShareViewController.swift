import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private enum AppGroup {
        static let identifier = "group.io.github.ljy4337.FitMatch"
    }

    private enum Key {
        static let pendingProductURL = "pendingProductURL"
        static let pendingProductURLCreatedAt = "pendingProductURLCreatedAt"
    }

    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let openButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)

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
            if let url {
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
                let url = (item as? String).flatMap(URL.init(string:))
                DispatchQueue.main.async {
                    completion(url)
                }
            }
            return
        }

        completion(nil)
    }

    private func savePendingURL(_ url: URL) {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        defaults?.set(url.absoluteString, forKey: Key.pendingProductURL)
        defaults?.set(Date(), forKey: Key.pendingProductURLCreatedAt)
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func showCompletedState() {
        activityIndicator.stopAnimating()
        titleLabel.text = "FitMatch에 추가했어요!"
        messageLabel.text = "보러가기를 누르면 비교 화면에서 바로 사이즈를 계산합니다."
        openButton.isHidden = false
        closeButton.isHidden = false
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
        openButton.isEnabled = false
        openButton.setTitle("FitMatch 여는 중", for: .normal)
        messageLabel.text = "FitMatch 앱으로 이동하고 있습니다."
        openContainingApp()
    }

    @objc
    private func closeButtonTapped() {
        completeRequest()
    }

    private func openContainingApp() {
        guard let url = URL(string: "fitmatch://compare") else {
            completeRequest()
            return
        }

        extensionContext?.open(url) { [weak self] didOpen in
            guard let self else {
                return
            }

            if didOpen {
                self.completeRequest()
                return
            }

            let didRequestOpen = self.openURLUsingApplication(url) || self.openURLUsingResponderChain(url)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.openButton.isEnabled = true
                self.openButton.setTitle("다시 보러가기", for: .normal)
                self.messageLabel.text = didRequestOpen
                    ? "FitMatch 앱 열기를 요청했습니다. 이동하지 않으면 FitMatch 앱을 직접 열어주세요."
                    : "앱 열기 요청이 차단됐습니다. FitMatch 앱을 직접 열면 비교 화면에서 이어서 진행됩니다."
            }
        }
    }

    @discardableResult
    private func openURLUsingApplication(_ url: URL) -> Bool {
        guard let applicationClass = NSClassFromString("UIApplication") as? NSObject.Type else {
            return false
        }

        let sharedApplicationSelector = NSSelectorFromString("sharedApplication")
        guard applicationClass.responds(to: sharedApplicationSelector),
              let application = applicationClass.perform(sharedApplicationSelector)?.takeUnretainedValue() as? NSObject
        else {
            return false
        }

        let openURLSelector = NSSelectorFromString("openURL:")
        guard application.responds(to: openURLSelector) else {
            return false
        }

        application.perform(openURLSelector, with: url)
        return true
    }

    @discardableResult
    private func openURLUsingResponderChain(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = view

        while let currentResponder = responder {
            if currentResponder.responds(to: selector) {
                currentResponder.perform(selector, with: url)
                return true
            }

            responder = currentResponder.next
        }

        return false
    }

}
