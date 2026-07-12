import SwiftUI
import UIKit

private struct TabBarVisibilityActionKey: EnvironmentKey {
    static let defaultValue: (Bool) -> Void = { _ in }
}

extension EnvironmentValues {
    var setFitMatchTabBarVisible: (Bool) -> Void {
        get { self[TabBarVisibilityActionKey.self] }
        set { self[TabBarVisibilityActionKey.self] = newValue }
    }
}

private struct TabBarScrollVisibilityModifier: ViewModifier {
    @Environment(\.setFitMatchTabBarVisible) private var setTabBarVisible
    @State private var lastOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background {
                ScrollOffsetObserver { offset in
                    let delta = offset - lastOffset
                    lastOffset = offset

                    guard abs(delta) > 6 else {
                        return
                    }

                    if offset < 12 {
                        setTabBarVisible(true)
                    } else {
                        setTabBarVisible(delta < 0)
                    }
                }
                .frame(width: 0, height: 0)
            }
    }
}

private struct TopChromeScrollVisibilityModifier: ViewModifier {
    @Binding var isVisible: Bool
    @State private var lastOffset: CGFloat = 0
    @State private var hiddenAccumulation: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background {
                ScrollOffsetObserver { offset in
                    let delta = offset - lastOffset
                    lastOffset = offset

                    if offset < 12 {
                        setVisible(true)
                        hiddenAccumulation = 0
                        return
                    }

                    if delta > 0 {
                        hiddenAccumulation += delta
                        if hiddenAccumulation > 40 {
                            setVisible(false)
                        }
                    } else if delta < -12 {
                        hiddenAccumulation = 0
                        setVisible(true)
                    }
                }
                .frame(width: 0, height: 0)
            }
    }

    private func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            isVisible = visible
        }
    }
}

private struct ScrollOffsetObserver: UIViewRepresentable {
    let onOffsetChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false

        DispatchQueue.main.async {
            context.coordinator.attach(to: view.enclosingScrollView)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            context.coordinator.attach(to: view.enclosingScrollView)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            context.coordinator.attach(to: view.enclosingScrollView)
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.attach(to: uiView.enclosingScrollView)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            context.coordinator.attach(to: uiView.enclosingScrollView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onOffsetChange: onOffsetChange)
    }

    final class Coordinator: NSObject {
        private let onOffsetChange: (CGFloat) -> Void
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?

        init(onOffsetChange: @escaping (CGFloat) -> Void) {
            self.onOffsetChange = onOffsetChange
        }

        func attach(to scrollView: UIScrollView?) {
            guard self.scrollView !== scrollView else {
                return
            }

            observation?.invalidate()
            self.scrollView = scrollView

            guard let scrollView else {
                return
            }

            observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                self?.onOffsetChange(scrollView.contentOffset.y)
            }
        }

        deinit {
            observation?.invalidate()
        }
    }
}

private extension UIView {
    var enclosingScrollView: UIScrollView? {
        var parent = superview
        while let current = parent {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }
            parent = current.superview
        }
        return nil
    }
}

extension View {
    func hidesTabBarOnScroll() -> some View {
        modifier(TabBarScrollVisibilityModifier())
    }

    func hidesTopChromeOnScroll(_ isVisible: Binding<Bool>) -> some View {
        modifier(TopChromeScrollVisibilityModifier(isVisible: isVisible))
    }
}
