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

    var isScrollHidden: Bool {
        hiddenReasons.contains(.scrolling)
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
    @StateObject private var coordinator = RootChromeScrollCoordinator()

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: RootChromeScrollSnapshot.self) { geometry in
                RootChromeScrollSnapshot(geometry: geometry)
            } action: { _, snapshot in
                coordinator.handle(snapshot: snapshot) { visible in
                    tabBarVisibilityController.setScrollVisible(
                        visible,
                        tab: tab,
                        source: "native scroll"
                    )
                }
            }
            .onScrollPhaseChange { oldPhase, newPhase in
                coordinator.handlePhaseChange(from: oldPhase, to: newPhase)
            }
            .onDisappear {
                coordinator.reset()
                tabBarVisibilityController.showScroll(tab: tab, source: "screen disappear")
            }
            .onAppear {
                coordinator.reset()
                tabBarVisibilityController.showScroll(tab: tab, source: "screen appear")
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
            .onScrollPhaseChange { oldPhase, newPhase in
                coordinator.handlePhaseChange(from: oldPhase, to: newPhase)
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
                || tabBarVisibilityController.isScrollHidden == visible else { return }
        tabBarVisibilityController.setScrollVisible(visible, tab: tab, source: source)
        if isTopChromeVisible != visible {
            isTopChromeVisible = visible
        }
    }
}

private struct RootChromeScrollSnapshot: Equatable {
    let rawOffset: CGFloat
    let minOffset: CGFloat
    let maxOffset: CGFloat
    let clampedOffset: CGFloat
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
        self.minOffset = minOffset
        self.maxOffset = maxOffset
        self.clampedOffset = clampedOffset

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

@MainActor
private final class RootChromeScrollCoordinator: ObservableObject {
    private var previousRawOffset: CGFloat?
    private var previousMaxOffset: CGFloat?
    private var latestSnapshot: RootChromeScrollSnapshot?
    private var scrollPhase: ScrollPhase = .idle
    private var isBottomLocked = false
    private var didReachBottomInCurrentGesture = false
    private var isWaitingForNewGestureAfterBottom = false
    private var isNewGestureAfterBottom = false
    private var newGestureStartOffset: CGFloat?
    private var isApplyingVisibilityChange = false
    private var pendingVisibility: Bool?
    private var isApplyScheduled = false
    private let layoutChangeEpsilon: CGFloat = 1
    private let minimumScrollDelta: CGFloat = 2
    private let bottomBoundaryTolerance: CGFloat = 2
    private let bottomUnlockDistance: CGFloat = 24

    func handle(snapshot: RootChromeScrollSnapshot, apply: @escaping (Bool) -> Void) {
        latestSnapshot = snapshot

        if isApplyingVisibilityChange {
            previousRawOffset = snapshot.rawOffset
            previousMaxOffset = snapshot.maxOffset
            return
        }

        guard snapshot.isScrollable else {
            previousRawOffset = snapshot.rawOffset
            previousMaxOffset = snapshot.maxOffset
            isBottomLocked = false
            clearBottomGestureState()
            schedule(visible: true, apply: apply)
            return
        }

        guard let previousRawOffset, let previousMaxOffset else {
            self.previousRawOffset = snapshot.rawOffset
            self.previousMaxOffset = snapshot.maxOffset
            isBottomLocked = snapshot.rawOffset >= snapshot.maxOffset - bottomBoundaryTolerance
            return
        }

        let maxOffsetChanged = abs(snapshot.maxOffset - previousMaxOffset) > layoutChangeEpsilon
        self.previousRawOffset = snapshot.rawOffset
        self.previousMaxOffset = snapshot.maxOffset

        if snapshot.rawOffset <= 0 || snapshot.boundaryState == .top {
            isBottomLocked = false
            clearBottomGestureState()
            schedule(visible: true, apply: apply)
            return
        }

        if maxOffsetChanged {
            if snapshot.boundaryState == .bottom || snapshot.boundaryState == .bottomOverscroll {
                lockAtBottom(apply: apply)
            }
            return
        }

        let delta = snapshot.rawOffset - previousRawOffset
        let distanceFromBottom = max(0, snapshot.maxOffset - snapshot.rawOffset)

        if snapshot.boundaryState == .bottom
            || snapshot.boundaryState == .bottomOverscroll
            || snapshot.rawOffset >= snapshot.maxOffset - bottomBoundaryTolerance {
            lockAtBottom(apply: apply)
            return
        }

        if isBottomLocked {
            guard isNewGestureAfterBottom,
                  isUserInteractionPhase,
                  !didReachBottomInCurrentGesture,
                  let newGestureStartOffset,
                  snapshot.rawOffset <= newGestureStartOffset - minimumScrollDelta,
                  distanceFromBottom >= bottomUnlockDistance else { return }
            isBottomLocked = false
            isWaitingForNewGestureAfterBottom = false
            isNewGestureAfterBottom = false
            self.newGestureStartOffset = nil
            schedule(visible: true, apply: apply)
            return
        }

        guard isUserInteractionPhase,
              !didReachBottomInCurrentGesture,
              abs(delta) >= minimumScrollDelta else { return }
        schedule(visible: delta < 0, apply: apply)
    }

    func handlePhaseChange(from oldPhase: ScrollPhase, to newPhase: ScrollPhase) {
        scrollPhase = newPhase

        if newPhase == .idle {
            didReachBottomInCurrentGesture = false
            isNewGestureAfterBottom = false
            newGestureStartOffset = nil
            previousRawOffset = latestSnapshot?.rawOffset
            previousMaxOffset = latestSnapshot?.maxOffset
            return
        }

        let startedInteraction = isUserInteraction(newPhase)
            && !isUserInteraction(oldPhase)

        guard startedInteraction else { return }

        didReachBottomInCurrentGesture = false
        previousRawOffset = latestSnapshot?.rawOffset
        previousMaxOffset = latestSnapshot?.maxOffset

        if isBottomLocked && isWaitingForNewGestureAfterBottom && oldPhase == .idle {
            isNewGestureAfterBottom = true
            newGestureStartOffset = latestSnapshot?.rawOffset
        } else {
            isNewGestureAfterBottom = false
            newGestureStartOffset = nil
        }
    }

    func reset() {
        previousRawOffset = nil
        previousMaxOffset = nil
        latestSnapshot = nil
        scrollPhase = .idle
        isBottomLocked = false
        clearBottomGestureState()
        pendingVisibility = nil
        isApplyScheduled = false
        isApplyingVisibilityChange = false
    }

    private var isUserInteractionPhase: Bool {
        isUserInteraction(scrollPhase)
    }

    private func isUserInteraction(_ phase: ScrollPhase) -> Bool {
        phase == .tracking || phase == .interacting
    }

    private func lockAtBottom(apply: @escaping (Bool) -> Void) {
        isBottomLocked = true
        didReachBottomInCurrentGesture = true
        isWaitingForNewGestureAfterBottom = true
        isNewGestureAfterBottom = false
        newGestureStartOffset = nil
        schedule(visible: false, apply: apply)
    }

    private func clearBottomGestureState() {
        didReachBottomInCurrentGesture = false
        isWaitingForNewGestureAfterBottom = false
        isNewGestureAfterBottom = false
        newGestureStartOffset = nil
    }

    private func schedule(visible: Bool, apply: @escaping (Bool) -> Void) {
        guard !visible || !isBottomLocked else {
            pendingVisibility = false
            return
        }
        pendingVisibility = visible
        guard !isApplyScheduled else { return }
        isApplyScheduled = true

        DispatchQueue.main.async {
            self.isApplyScheduled = false
            guard let pendingVisibility = self.pendingVisibility else { return }
            self.pendingVisibility = nil
            guard !pendingVisibility || !self.isBottomLocked else { return }
            self.isApplyingVisibilityChange = true
            apply(pendingVisibility)

            DispatchQueue.main.async {
                self.previousRawOffset = nil
                self.previousMaxOffset = nil
                self.isApplyingVisibilityChange = false
            }
        }
    }
}

private enum ScrollBoundaryState: Equatable {
    case top
    case scrolling
    case bottom
    case bottomOverscroll
}

private struct TopChromeScrollVisibilityModifier: ViewModifier {
    @Binding var isVisible: Bool
    @StateObject private var coordinator = RootChromeScrollCoordinator()

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: RootChromeScrollSnapshot.self) { geometry in
                RootChromeScrollSnapshot(geometry: geometry)
            } action: { _, snapshot in
                coordinator.handle(snapshot: snapshot) { visible in
                    setVisible(visible)
                }
            }
            .onScrollPhaseChange { oldPhase, newPhase in
                coordinator.handlePhaseChange(from: oldPhase, to: newPhase)
            }
            .onDisappear {
                coordinator.reset()
                setVisible(true)
            }
            .onAppear {
                coordinator.reset()
                setVisible(true)
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
