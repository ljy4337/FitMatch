import SwiftUI
import Combine

enum TabBarHiddenReason: String, Hashable {
    case navigationDetail
    case scrolling
    case modalFlow
}

enum FitMatchScrollContentMetrics {
    static let bottomClearance: CGFloat = 88
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
    }
}

private struct BottomTabBarScrollVisibilityModifier: ViewModifier {
    @EnvironmentObject private var tabBarVisibilityController: TabBarVisibilityController
    let tab: AppTab
    @StateObject private var scrollState = ScrollVisibilityState()
    private let minimumDelta: CGFloat = 3

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: ScrollVisibilitySnapshot.self) { geometry in
                ScrollVisibilitySnapshot(geometry: geometry)
            } action: { previousSnapshot, currentSnapshot in
                handleScroll(previous: previousSnapshot, current: currentSnapshot)
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

    private func handleScroll(previous previousSnapshot: ScrollVisibilitySnapshot, current currentSnapshot: ScrollVisibilitySnapshot) {
        guard currentSnapshot.isScrollable else {
            scrollState.reset()
            tabBarVisibilityController.showScroll(tab: tab, source: "content shorter than viewport")
            return
        }

        let delta = currentSnapshot.clampedOffset - previousSnapshot.clampedOffset

        if currentSnapshot.boundaryState == .top {
            scrollState.reset()
            tabBarVisibilityController.showScroll(tab: tab, source: "native scroll top")
            return
        }

        if currentSnapshot.boundaryState == .bottom || currentSnapshot.boundaryState == .bottomOverscroll {
            scrollState.reset()
            return
        }

        guard abs(delta) >= minimumDelta else { return }

        if delta > 0 {
            if scrollState.recordScroll(delta: delta) == .hide {
                tabBarVisibilityController.hideScroll(tab: tab, source: "native scroll down")
            }
        } else {
            if scrollState.recordScroll(delta: delta) == .show {
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
            .onScrollGeometryChange(for: ScrollVisibilitySnapshot.self) { geometry in
                ScrollVisibilitySnapshot(geometry: geometry)
            } action: { previousSnapshot, currentSnapshot in
                handleScroll(previous: previousSnapshot, current: currentSnapshot)
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

    private func handleScroll(previous previousSnapshot: ScrollVisibilitySnapshot, current currentSnapshot: ScrollVisibilitySnapshot) {
        guard currentSnapshot.isScrollable else {
            scrollState.reset()
            tabBarVisibilityController.showScroll(tab: tab, source: "content shorter than viewport")
            setTopChromeVisible(true, source: "content shorter than viewport")
            return
        }

        let delta = currentSnapshot.clampedOffset - previousSnapshot.clampedOffset

        if currentSnapshot.boundaryState == .top {
            scrollState.reset()
            tabBarVisibilityController.showScroll(tab: tab, source: "native scroll top")
            setTopChromeVisible(true, source: "native scroll top")
            return
        }

        if currentSnapshot.boundaryState == .bottom || currentSnapshot.boundaryState == .bottomOverscroll {
            scrollState.reset()
            return
        }

        guard delta != 0 else { return }

        if delta > 0 {
            if scrollState.recordScroll(delta: delta) == .hide {
                tabBarVisibilityController.hideScroll(tab: tab, source: "native scroll down")
                setTopChromeVisible(false, source: "native scroll down")
            }
        } else {
            scrollState.reset()
            tabBarVisibilityController.showScroll(tab: tab, source: "native scroll up")
            setTopChromeVisible(true, source: "native scroll up")
        }
    }

    private func setTopChromeVisible(_ visible: Bool, source: String) {
        guard isTopChromeVisible != visible else { return }

        withAnimation(.easeInOut(duration: 0.25)) {
            isTopChromeVisible = visible
        }
    }
}

private struct ScrollVisibilitySnapshot: Equatable {
    let rawOffset: CGFloat
    let clampedOffset: CGFloat
    let minOffset: CGFloat
    let maxOffset: CGFloat
    let boundaryState: ScrollBoundaryState

    init(geometry: ScrollGeometry) {
        let rawOffset = geometry.contentOffset.y + geometry.contentInsets.top
        let minOffset: CGFloat = 0
        let maxOffset = max(
            minOffset,
            geometry.contentSize.height
                - geometry.containerSize.height
                + geometry.contentInsets.top
                + geometry.contentInsets.bottom
        )
        let clampedOffset = min(max(rawOffset, minOffset), maxOffset)

        self.rawOffset = rawOffset
        self.clampedOffset = clampedOffset
        self.minOffset = minOffset
        self.maxOffset = maxOffset

        if rawOffset < minOffset {
            boundaryState = .top
        } else if rawOffset > maxOffset {
            boundaryState = .bottomOverscroll
        } else if clampedOffset <= minOffset + 2 {
            boundaryState = .top
        } else if clampedOffset >= maxOffset - 2 {
            boundaryState = .bottom
        } else {
            boundaryState = .scrolling
        }
    }

    var isScrollable: Bool {
        maxOffset > minOffset + 2
    }
}

private enum ScrollBoundaryState: Equatable {
    case top
    case scrolling
    case bottom
    case bottomOverscroll
}

@MainActor
private final class ScrollVisibilityState: ObservableObject {
    private var hideAccumulation: CGFloat = 0
    private var showAccumulation: CGFloat = 0
    private var lastActionDate = Date.distantPast
    private let hideThreshold: CGFloat = 30
    private let showThreshold: CGFloat = 20
    private let cooldownInterval: TimeInterval = 0.22

    func reset() {
        hideAccumulation = 0
        showAccumulation = 0
    }

    func recordScroll(delta: CGFloat) -> ScrollVisibilityAction? {
        if delta > 0 {
            hideAccumulation += delta
            showAccumulation = 0
            guard hideAccumulation >= hideThreshold else { return nil }
            guard canEmitAction() else {
                hideAccumulation = hideThreshold
                return nil
            }
            hideAccumulation = 0
            markActionEmitted()
            return .hide
        }

        showAccumulation += abs(delta)
        hideAccumulation = 0
        guard showAccumulation >= showThreshold else { return nil }
        guard canEmitAction() else {
            showAccumulation = showThreshold
            return nil
        }
        showAccumulation = 0
        markActionEmitted()
        return .show
    }

    private func canEmitAction() -> Bool {
        Date().timeIntervalSince(lastActionDate) >= cooldownInterval
    }

    private func markActionEmitted() {
        lastActionDate = Date()
    }
}

private enum ScrollVisibilityAction {
    case hide
    case show
}

private struct TopChromeScrollVisibilityModifier: ViewModifier {
    @Binding var isVisible: Bool
    @StateObject private var scrollState = ScrollVisibilityState()
    private let minimumDelta: CGFloat = 3

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: ScrollVisibilitySnapshot.self) { geometry in
                ScrollVisibilitySnapshot(geometry: geometry)
            } action: { previousSnapshot, currentSnapshot in
                handleScroll(previous: previousSnapshot, current: currentSnapshot)
            }
            .onDisappear {
                scrollState.reset()
                setVisible(true)
            }
            .onAppear {
                scrollState.reset()
                setVisible(true)
            }
    }

    private func handleScroll(previous previousSnapshot: ScrollVisibilitySnapshot, current currentSnapshot: ScrollVisibilitySnapshot) {
        guard currentSnapshot.isScrollable else {
            scrollState.reset()
            setVisible(true)
            return
        }

        let delta = currentSnapshot.clampedOffset - previousSnapshot.clampedOffset

        if currentSnapshot.boundaryState == .top {
            scrollState.reset()
            setVisible(true)
            return
        }

        if currentSnapshot.boundaryState == .bottom || currentSnapshot.boundaryState == .bottomOverscroll {
            scrollState.reset()
            return
        }

        guard abs(delta) >= minimumDelta else { return }

        if delta > 0 {
            if scrollState.recordScroll(delta: delta) == .hide {
                setVisible(false)
            }
        } else {
            if scrollState.recordScroll(delta: delta) == .show {
                setVisible(true)
            }
        }
    }

    private func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            isVisible = visible
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
