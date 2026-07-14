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

    func setScrollVisible(_ visible: Bool, tab: AppTab? = nil, source: String = "") {
        if visible {
            guard hiddenReasons.contains(.scrolling) else { return }
            _ = hiddenReasons.remove(.scrolling)
        } else {
            guard !hiddenReasons.contains(.scrolling) else { return }
            _ = hiddenReasons.insert(.scrolling)
        }
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
    @StateObject private var coordinator = RootChromeScrollCoordinator()

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: RootChromeScrollSnapshot.self) { geometry in
                RootChromeScrollSnapshot(geometry: geometry)
            } action: { _, currentSnapshot in
                coordinator.handle(snapshot: currentSnapshot) { visible in
                    applyVisibility(visible, source: "native scroll")
                }
            }
            .onDisappear {
                coordinator.reset()
                applyVisibility(true, source: "screen disappear")
            }
            .onAppear {
                coordinator.reset()
                applyVisibility(true, source: "screen appear")
            }
    }

    private func applyVisibility(_ visible: Bool, source: String) {
        guard isTopChromeVisible != visible
                || tabBarVisibilityController.isVisible != visible else { return }
        tabBarVisibilityController.setScrollVisible(visible, tab: tab, source: source)
        if isTopChromeVisible != visible {
            isTopChromeVisible = visible
        }
    }
}

private struct RootChromeScrollSnapshot: Equatable {
    let rawOffset: CGFloat
    let maxOffset: CGFloat

    init(geometry: ScrollGeometry) {
        rawOffset = geometry.contentOffset.y + geometry.contentInsets.top
        maxOffset = max(
            0,
            geometry.contentSize.height
                - geometry.containerSize.height
                + geometry.contentInsets.top
                + geometry.contentInsets.bottom
        )
    }
}

@MainActor
private final class RootChromeScrollCoordinator: ObservableObject {
    private var previousRawOffset: CGFloat?
    private var wasBottomOverscrolling = false
    private var isApplyingVisibilityChange = false
    private var pendingVisibility: Bool?
    private var isApplyScheduled = false

    func handle(snapshot: RootChromeScrollSnapshot, apply: @escaping (Bool) -> Void) {
        if isApplyingVisibilityChange {
            previousRawOffset = snapshot.rawOffset
            return
        }

        guard let previousRawOffset else {
            self.previousRawOffset = snapshot.rawOffset
            wasBottomOverscrolling = snapshot.rawOffset > snapshot.maxOffset
            return
        }

        self.previousRawOffset = snapshot.rawOffset

        if snapshot.rawOffset <= 0 {
            wasBottomOverscrolling = false
            schedule(visible: true, apply: apply)
            return
        }

        let isBottomOverscrolling = snapshot.rawOffset > snapshot.maxOffset
        let delta = snapshot.rawOffset - previousRawOffset

        if wasBottomOverscrolling && delta < 0 {
            wasBottomOverscrolling = isBottomOverscrolling
            return
        }
        wasBottomOverscrolling = isBottomOverscrolling

        guard delta != 0 else { return }
        schedule(visible: delta < 0, apply: apply)
    }

    func reset() {
        previousRawOffset = nil
        wasBottomOverscrolling = false
        pendingVisibility = nil
        isApplyScheduled = false
        isApplyingVisibilityChange = false
    }

    private func schedule(visible: Bool, apply: @escaping (Bool) -> Void) {
        pendingVisibility = visible
        guard !isApplyScheduled else { return }
        isApplyScheduled = true

        DispatchQueue.main.async {
            self.isApplyScheduled = false
            guard let pendingVisibility = self.pendingVisibility else { return }
            self.pendingVisibility = nil
            self.isApplyingVisibilityChange = true
            apply(pendingVisibility)

            DispatchQueue.main.async {
                self.previousRawOffset = nil
                self.isApplyingVisibilityChange = false
            }
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
