import SwiftUI
import UIKit

private struct KeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(KeyboardDismissInstaller().frame(width: 0, height: 0))
    }
}

private struct KeyboardDismissInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> KeyboardDismissInstallerView {
        let view = KeyboardDismissInstallerView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: KeyboardDismissInstallerView, context: Context) {
        uiView.coordinator = context.coordinator
        uiView.installIfNeeded()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var currentView: UIView? = touch.view
            while let view = currentView {
                if view is UIControl || view is UITextView {
                    return false
                }
                currentView = view.superview
            }
            return true
        }

        @objc func dismissKeyboard() {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }
}

private final class KeyboardDismissInstallerView: UIView {
    weak var coordinator: KeyboardDismissInstaller.Coordinator?
    private weak var installedWindow: UIWindow?
    private weak var tapGesture: UITapGestureRecognizer?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installIfNeeded()
    }

    func installIfNeeded() {
        guard let window, installedWindow !== window else {
            return
        }

        if let tapGesture {
            installedWindow?.removeGestureRecognizer(tapGesture)
        }

        guard let coordinator else {
            return
        }

        let gesture = UITapGestureRecognizer(target: coordinator, action: #selector(KeyboardDismissInstaller.Coordinator.dismissKeyboard))
        gesture.cancelsTouchesInView = false
        gesture.delegate = coordinator
        window.addGestureRecognizer(gesture)
        installedWindow = window
        tapGesture = gesture
    }

    deinit {
        if let tapGesture {
            installedWindow?.removeGestureRecognizer(tapGesture)
        }
    }
}

extension View {
    func dismissesKeyboardOnBackgroundTap() -> some View {
        modifier(KeyboardDismissModifier())
    }
}
