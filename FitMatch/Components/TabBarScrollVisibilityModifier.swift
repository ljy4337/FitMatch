import SwiftUI
import Combine

enum TabBarHiddenReason: String, Hashable {
    case navigationDetail
    case scrolling
    case modalFlow
}

@MainActor
final class TabBarVisibilityController: ObservableObject {
    @Published private var hiddenReasons: Set<TabBarHiddenReason> = []

    var isVisible: Bool {
        hiddenReasons.isEmpty
    }

    func hide(tab: AppTab? = nil, reason: TabBarHiddenReason, source: String = "") {
        guard !hiddenReasons.contains(reason) else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            _ = hiddenReasons.insert(reason)
        }
        print("[TabBarVisibility] hide tab=\(tab?.logName ?? "unknown") reason=\(reason.rawValue) source=\(source) active=\(activeReasonLog)")
    }

    func show(tab: AppTab? = nil, reason: TabBarHiddenReason, source: String = "") {
        release(tab: tab, reason: reason, source: source)
    }

    func hideScroll(tab: AppTab? = nil, source: String = "") {
        hide(tab: tab, reason: .scrolling, source: source)
    }

    func showScroll(tab: AppTab? = nil, source: String = "") {
        release(tab: tab, reason: .scrolling, source: source)
    }

    func release(tab: AppTab? = nil, reason: TabBarHiddenReason, source: String = "") {
        guard hiddenReasons.contains(reason) else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            _ = hiddenReasons.remove(reason)
        }
        print("[TabBarVisibility] release tab=\(tab?.logName ?? "unknown") reason=\(reason.rawValue) source=\(source) active=\(activeReasonLog)")
    }

    private var activeReasonLog: String {
        hiddenReasons.map(\.rawValue).sorted().joined(separator: ",")
    }
}

private struct BottomTabBarScrollVisibilityModifier: ViewModifier {
    @EnvironmentObject private var tabBarVisibilityController: TabBarVisibilityController
    let tab: AppTab
    @StateObject private var scrollState = ScrollVisibilityState()

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { previousOffset, currentOffset in
                handleScrollOffset(previous: previousOffset, current: currentOffset)
            }
            .onDisappear {
                scrollState.reset()
                tabBarVisibilityController.showScroll(tab: tab, source: "screen disappear")
            }
            .onAppear {
                scrollState.reset()
                tabBarVisibilityController.showScroll(tab: tab, source: "screen appear")
            }
    }

    private func handleScrollOffset(previous previousOffset: CGFloat, current currentOffset: CGFloat) {
        guard previousOffset.isFinite, currentOffset.isFinite else { return }

        let delta = currentOffset - previousOffset

        guard abs(delta) >= 1 else {
            return
        }

        if currentOffset <= 2 {
            scrollState.reset()
            tabBarVisibilityController.showScroll(tab: tab, source: "native scroll top")
            return
        }

        if delta > 0 {
            if scrollState.recordScroll(delta: delta, threshold: 12) == .hide {
                tabBarVisibilityController.hideScroll(tab: tab, source: "native scroll down")
            }
        } else {
            if scrollState.recordScroll(delta: delta, threshold: 12) == .show {
                tabBarVisibilityController.showScroll(tab: tab, source: "native scroll up")
            }
        }
    }
}

private struct RootChromeScrollVisibilityModifier: ViewModifier {
    @EnvironmentObject private var tabBarVisibilityController: TabBarVisibilityController
    let tab: AppTab
    @Binding var isTopChromeVisible: Bool
    @StateObject private var scrollState = ScrollVisibilityState()

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { previousOffset, currentOffset in
                handleScrollOffset(previous: previousOffset, current: currentOffset)
            }
            .onDisappear {
                scrollState.reset()
                tabBarVisibilityController.showScroll(tab: tab, source: "screen disappear")
                setTopChromeVisible(true, source: "screen disappear")
            }
            .onAppear {
                scrollState.reset()
                tabBarVisibilityController.showScroll(tab: tab, source: "screen appear")
                setTopChromeVisible(true, source: "screen appear")
            }
    }

    private func handleScrollOffset(previous previousOffset: CGFloat, current currentOffset: CGFloat) {
        guard previousOffset.isFinite, currentOffset.isFinite else { return }

        let delta = currentOffset - previousOffset

        guard abs(delta) >= 1 else {
            return
        }

        if currentOffset <= 2 {
            scrollState.reset()
            tabBarVisibilityController.showScroll(tab: tab, source: "native scroll top")
            setTopChromeVisible(true, source: "native scroll top")
            return
        }

        if delta > 0 {
            if scrollState.recordScroll(delta: delta, threshold: 12) == .hide {
                tabBarVisibilityController.hideScroll(tab: tab, source: "native scroll down")
                setTopChromeVisible(false, source: "native scroll down")
            }
        } else {
            if scrollState.recordScroll(delta: delta, threshold: 12) == .show {
                tabBarVisibilityController.showScroll(tab: tab, source: "native scroll up")
                setTopChromeVisible(true, source: "native scroll up")
            }
        }
    }

    private func setTopChromeVisible(_ visible: Bool, source: String) {
        guard isTopChromeVisible != visible else { return }

        print("[TopChromeScroll] tab=\(tab.logName) action=\(visible ? "show" : "hide") source=\(source)")
        withAnimation(.easeInOut(duration: 0.25)) {
            isTopChromeVisible = visible
        }
    }
}

@MainActor
private final class ScrollVisibilityState: ObservableObject {
    private var hideAccumulation: CGFloat = 0
    private var showAccumulation: CGFloat = 0

    func reset() {
        hideAccumulation = 0
        showAccumulation = 0
    }

    func recordScroll(delta: CGFloat, threshold: CGFloat) -> ScrollVisibilityAction? {
        if delta > 0 {
            hideAccumulation += delta
            showAccumulation = 0
            guard hideAccumulation >= threshold else { return nil }
            hideAccumulation = 0
            return .hide
        }

        showAccumulation += abs(delta)
        hideAccumulation = 0
        guard showAccumulation >= threshold else { return nil }
        showAccumulation = 0
        return .show
    }
}

private enum ScrollVisibilityAction {
    case hide
    case show
}

private struct TopChromeScrollVisibilityModifier: ViewModifier {
    @Binding var isVisible: Bool

    func body(content: Content) -> some View {
        content.onAppear {
            isVisible = true
        }
    }
}

extension View {
    func hidesBottomTabBarOnScroll(tab: AppTab) -> some View {
        modifier(BottomTabBarScrollVisibilityModifier(tab: tab))
    }

    func hidesBottomTabBarOnScroll(tab: AppTab, topChrome isVisible: Binding<Bool>) -> some View {
        modifier(RootChromeScrollVisibilityModifier(tab: tab, isTopChromeVisible: isVisible))
    }

    func tracksTabBarVisibilityOnScroll(_ tab: AppTab) -> some View {
        hidesBottomTabBarOnScroll(tab: tab)
    }

    func hidesTabBarOnScroll() -> some View {
        self
    }

    func hidesTopChromeOnScroll(_ isVisible: Binding<Bool>) -> some View {
        modifier(TopChromeScrollVisibilityModifier(isVisible: isVisible))
    }
}
