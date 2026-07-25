import SwiftUI
import Combine

enum TabBarHiddenReason: String, Hashable {
    case navigationDetail
    case scrolling
    case modalFlow
}

enum FitMatchScrollContentMetrics {
    static let bottomClearance: CGFloat = 88
    static let minimumRootScrollExtent: CGFloat =
        FitMatchTopChromeMetrics.height + 24
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
        withAnimation(.easeOut(duration: 0.22)) {
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
        withAnimation(.easeOut(duration: 0.22)) {
            _ = hiddenReasons.remove(reason)
        }
    }
}

private struct BottomTabBarScrollVisibilityModifier: ViewModifier {
    @EnvironmentObject private var tabBarVisibilityController: TabBarVisibilityController
    let tab: AppTab
    @StateObject private var coordinator: RootChromeScrollCoordinator

    init(tab: AppTab) {
        self.tab = tab
        #if DEBUG
        _coordinator = StateObject(
            wrappedValue: RootChromeScrollCoordinator(
                tab: String(describing: tab),
                source: "bottom"
            )
        )
        #else
        _coordinator = StateObject(wrappedValue: RootChromeScrollCoordinator())
        #endif
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: RootChromeScrollSnapshot.self) { geometry in
                RootChromeScrollSnapshot(geometry: geometry)
            } action: { _, snapshot in
                coordinator.handle(snapshot: snapshot) { visible in
                    withAnimation(.easeOut(duration: 0.22)) {
                        tabBarVisibilityController.setScrollVisible(
                            visible,
                            tab: tab,
                            source: "native scroll"
                        )
                    }
                }
            }
            .onScrollPhaseChange { oldPhase, newPhase in
                coordinator.handlePhaseChange(from: oldPhase, to: newPhase) { visible in
                    withAnimation(.easeOut(duration: 0.22)) {
                        tabBarVisibilityController.setScrollVisible(
                            visible,
                            tab: tab,
                            source: "native scroll phase"
                        )
                    }
                }
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
    @StateObject private var coordinator: RootChromeScrollCoordinator
    @State private var bottomScrollClearance = FitMatchScrollContentMetrics.bottomClearance

    init(tab: AppTab, isTopChromeVisible: Binding<Bool>) {
        self.tab = tab
        _isTopChromeVisible = isTopChromeVisible
        #if DEBUG
        _coordinator = StateObject(
            wrappedValue: RootChromeScrollCoordinator(
                tab: String(describing: tab),
                source: "root"
            )
        )
        #else
        _coordinator = StateObject(wrappedValue: RootChromeScrollCoordinator())
        #endif
    }

    func body(content: Content) -> some View {
        content
            .contentMargins(.bottom, bottomScrollClearance, for: .scrollContent)
            .onScrollGeometryChange(for: RootChromeScrollSnapshot.self) { geometry in
                RootChromeScrollSnapshot(geometry: geometry)
            } action: { _, currentSnapshot in
                ensureMinimumScrollExtent(for: currentSnapshot)
                coordinator.handle(snapshot: currentSnapshot) { visible in
                    applyVisibility(visible, source: "native scroll")
                }
            }
            .onScrollPhaseChange { oldPhase, newPhase in
                coordinator.handlePhaseChange(from: oldPhase, to: newPhase) { visible in
                    applyVisibility(visible, source: "native scroll phase")
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

    private func ensureMinimumScrollExtent(for snapshot: RootChromeScrollSnapshot) {
        let missingExtent = FitMatchScrollContentMetrics.minimumRootScrollExtent
            - snapshot.maxOffset
        guard missingExtent > 1 else { return }
        bottomScrollClearance += missingExtent
    }

    private func applyVisibility(_ visible: Bool, source: String) {
        guard isTopChromeVisible != visible
                || tabBarVisibilityController.isScrollHidden == visible else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            tabBarVisibilityController.setScrollVisible(visible, tab: tab, source: source)
            if isTopChromeVisible != visible {
                isTopChromeVisible = visible
            }
        }
    }
}

private struct RootChromeScrollSnapshot: Equatable {
    let contentSizeHeight: CGFloat
    let containerSizeHeight: CGFloat
    let contentInsetTop: CGFloat
    let contentInsetBottom: CGFloat
    let rawOffset: CGFloat
    let minOffset: CGFloat
    let maxOffset: CGFloat
    let clampedOffset: CGFloat
    let boundaryState: ScrollBoundaryState

    init(geometry: ScrollGeometry) {
        contentSizeHeight = geometry.contentSize.height
        containerSizeHeight = geometry.containerSize.height
        contentInsetTop = geometry.contentInsets.top
        contentInsetBottom = geometry.contentInsets.bottom
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
    #if DEBUG
    private let diagnosticTab: String
    private let diagnosticSource: String
    private let diagnosticID = UUID().uuidString.prefix(6)
    private var lastDiagnosticSignature: String?
    #endif
    private var previousRawOffset: CGFloat?
    private var previousClampedOffset: CGFloat?
    private var previousMaxOffset: CGFloat?
    private var latestSnapshot: RootChromeScrollSnapshot?
    private var scrollPhase: ScrollPhase = .idle
    private var isBottomLocked = false
    private var didReachBottomInCurrentGesture = false
    private var isWaitingForNewGestureAfterBottom = false
    private var isNewGestureAfterBottom = false
    private var newGestureStartOffset: CGFloat?
    private var pendingVisibility: Bool?
    private var isApplyScheduled = false
    private var lastAppliedVisibility: Bool?
    private var accumulatedDownwardDistance: CGFloat = 0
    private let layoutChangeEpsilon: CGFloat = 1
    private let minimumScrollDelta: CGFloat = 2
    private let bottomBoundaryTolerance: CGFloat = 2
    private let bottomUnlockDistance: CGFloat = 24

    #if DEBUG
    init(tab: String = "none", source: String = "unknown") {
        diagnosticTab = tab
        diagnosticSource = source
    }
    #else
    init() {}
    #endif

    func handle(snapshot: RootChromeScrollSnapshot, apply: @escaping (Bool) -> Void) {
        latestSnapshot = snapshot

        if snapshot.rawOffset <= 0 || snapshot.boundaryState == .top {
            previousRawOffset = snapshot.rawOffset
            previousClampedOffset = snapshot.clampedOffset
            previousMaxOffset = snapshot.maxOffset
            accumulatedDownwardDistance = 0
            if isUserInteractionPhase || scrollPhase == .idle {
                setBottomLocked(false)
                clearBottomGestureState()
                schedule(visible: true, apply: apply)
            }
            return
        }

        guard snapshot.isScrollable else {
            previousRawOffset = snapshot.rawOffset
            previousClampedOffset = snapshot.clampedOffset
            previousMaxOffset = snapshot.maxOffset
            setBottomLocked(false)
            clearBottomGestureState()
            schedule(visible: true, apply: apply)
            return
        }

        guard let previousRawOffset,
              let previousClampedOffset,
              let previousMaxOffset else {
            self.previousRawOffset = snapshot.rawOffset
            self.previousClampedOffset = snapshot.clampedOffset
            self.previousMaxOffset = snapshot.maxOffset
            setBottomLocked(snapshot.rawOffset >= snapshot.maxOffset - bottomBoundaryTolerance)
            return
        }

        let maxOffsetChanged = abs(snapshot.maxOffset - previousMaxOffset) > layoutChangeEpsilon
        let rawDelta = snapshot.rawOffset - previousRawOffset
        let clampedDelta = snapshot.clampedOffset - previousClampedOffset
        self.previousRawOffset = snapshot.rawOffset
        self.previousClampedOffset = snapshot.clampedOffset
        self.previousMaxOffset = snapshot.maxOffset

        if maxOffsetChanged {
            #if DEBUG
            debugLog(event: "maxOffsetChanged", snapshot: snapshot)
            #endif
            if isBottomLocked,
               snapshot.maxOffset > previousMaxOffset,
               snapshot.boundaryState == .scrolling {
                setBottomLocked(false)
                clearBottomGestureState()
            }

            guard rawDelta != 0 else { return }
        }

        let distanceFromBottom = max(0, snapshot.maxOffset - snapshot.rawOffset)

        if snapshot.boundaryState == .bottom
            || snapshot.boundaryState == .bottomOverscroll
            || snapshot.rawOffset >= snapshot.maxOffset - bottomBoundaryTolerance {
            lockAtBottom()
            return
        }

        if isBottomLocked {
            guard isNewGestureAfterBottom,
                  isUserInteractionPhase,
                  !didReachBottomInCurrentGesture,
                  let newGestureStartOffset,
                  snapshot.rawOffset <= newGestureStartOffset - minimumScrollDelta,
                  distanceFromBottom >= bottomUnlockDistance else { return }
            setBottomLocked(false)
            isWaitingForNewGestureAfterBottom = false
            isNewGestureAfterBottom = false
            self.newGestureStartOffset = nil
            schedule(visible: true, apply: apply)
            return
        }

        guard !didReachBottomInCurrentGesture else { return }

        if clampedDelta > 0 {
            accumulateDownwardDistance(
                clampedDelta,
                apply: apply
            )
        } else if isUserInteractionPhase,
                  clampedDelta <= -minimumScrollDelta {
            accumulatedDownwardDistance = 0
            schedule(visible: true, apply: apply)
        }
    }

    func handlePhaseChange(
        from oldPhase: ScrollPhase,
        to newPhase: ScrollPhase,
        apply: @escaping (Bool) -> Void
    ) {
        scrollPhase = newPhase
        #if DEBUG
        if oldPhase != newPhase {
            debugLog(event: "phase", snapshot: latestSnapshot)
        }
        #endif

        if newPhase == .idle {
            didReachBottomInCurrentGesture = false
            isNewGestureAfterBottom = false
            newGestureStartOffset = nil
            previousRawOffset = latestSnapshot?.rawOffset
            previousClampedOffset = latestSnapshot?.clampedOffset
            previousMaxOffset = latestSnapshot?.maxOffset
            accumulatedDownwardDistance = 0
            if let latestSnapshot,
               !latestSnapshot.isScrollable || latestSnapshot.boundaryState == .top {
                setBottomLocked(false)
                clearBottomGestureState()
                schedule(visible: true, apply: apply)
            }
            return
        }

        let startedInteraction = isUserInteraction(newPhase)
            && !isUserInteraction(oldPhase)

        guard startedInteraction else { return }

        didReachBottomInCurrentGesture = false
        previousRawOffset = latestSnapshot?.rawOffset
        previousClampedOffset = latestSnapshot?.clampedOffset
        previousMaxOffset = latestSnapshot?.maxOffset
        accumulatedDownwardDistance = 0

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
        previousClampedOffset = nil
        previousMaxOffset = nil
        latestSnapshot = nil
        scrollPhase = .idle
        setBottomLocked(false)
        clearBottomGestureState()
        pendingVisibility = nil
        isApplyScheduled = false
        lastAppliedVisibility = nil
        accumulatedDownwardDistance = 0
        #if DEBUG
        lastDiagnosticSignature = nil
        #endif
    }

    private var isUserInteractionPhase: Bool {
        isUserInteraction(scrollPhase)
    }

    private func isUserInteraction(_ phase: ScrollPhase) -> Bool {
        phase == .tracking || phase == .interacting
    }

    private func accumulateDownwardDistance(
        _ distance: CGFloat,
        apply: @escaping (Bool) -> Void
    ) {
        accumulatedDownwardDistance += distance
        let hideThreshold = FitMatchTopChromeMetrics.height
        guard hideThreshold > 0,
              accumulatedDownwardDistance >= hideThreshold else { return }
        schedule(visible: false, apply: apply)
    }

    private func lockAtBottom() {
        setBottomLocked(true)
        didReachBottomInCurrentGesture = true
        isWaitingForNewGestureAfterBottom = true
        isNewGestureAfterBottom = false
        newGestureStartOffset = nil
    }

    private func clearBottomGestureState() {
        didReachBottomInCurrentGesture = false
        isWaitingForNewGestureAfterBottom = false
        isNewGestureAfterBottom = false
        newGestureStartOffset = nil
    }

    private func setBottomLocked(_ isLocked: Bool) {
        guard isBottomLocked != isLocked else { return }
        isBottomLocked = isLocked
        #if DEBUG
        debugLog(event: "bottomLock", snapshot: latestSnapshot)
        #endif
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
            guard self.lastAppliedVisibility != pendingVisibility else { return }
            self.lastAppliedVisibility = pendingVisibility
            #if DEBUG
            self.debugLog(
                event: "visibility",
                snapshot: self.latestSnapshot,
                visibility: pendingVisibility
            )
            #endif
            apply(pendingVisibility)
        }
    }

    #if DEBUG
    private func debugLog(
        event: String,
        snapshot: RootChromeScrollSnapshot?,
        visibility: Bool? = nil
    ) {
        let offset = snapshot.map { String(describing: $0.rawOffset) } ?? "nil"
        let maxOffset = snapshot.map { String(describing: $0.maxOffset) } ?? "nil"
        let contentSize = snapshot.map { String(describing: $0.contentSizeHeight) } ?? "nil"
        let containerSize = snapshot.map { String(describing: $0.containerSizeHeight) } ?? "nil"
        let insetTop = snapshot.map { String(describing: $0.contentInsetTop) } ?? "nil"
        let insetBottom = snapshot.map { String(describing: $0.contentInsetBottom) } ?? "nil"
        let boundary = snapshot.map { String(describing: $0.boundaryState) } ?? "nil"
        let visibility = visibility.map { String(describing: $0) } ?? "unchanged"
        let hideThreshold = FitMatchTopChromeMetrics.height
        let signature = [
            event,
            String(describing: scrollPhase),
            boundary,
            String(describing: isBottomLocked),
            visibility,
            maxOffset
        ].joined(separator: "|")
        guard lastDiagnosticSignature != signature else { return }
        lastDiagnosticSignature = signature
        print(
            "[ScrollDiagnostics] tab=\(diagnosticTab) source=\(diagnosticSource) "
                + "coordinator=\(diagnosticID) event=\(event) offset=\(offset) "
                + "contentSize=\(contentSize) containerSize=\(containerSize) "
                + "insetTop=\(insetTop) insetBottom=\(insetBottom) "
                + "maxOffset=\(maxOffset) phase=\(String(describing: scrollPhase)) "
                + "boundaryState=\(boundary) bottomLock=\(isBottomLocked) "
                + "hideThreshold=\(hideThreshold) "
                + "accumulatedDistance=\(accumulatedDownwardDistance) "
                + "visibility=\(visibility)"
        )
    }
    #endif
}

private enum ScrollBoundaryState: Equatable {
    case top
    case scrolling
    case bottom
    case bottomOverscroll
}

private struct TopChromeScrollVisibilityModifier: ViewModifier {
    @Binding var isVisible: Bool
    @StateObject private var coordinator: RootChromeScrollCoordinator

    init(isVisible: Binding<Bool>) {
        _isVisible = isVisible
        #if DEBUG
        _coordinator = StateObject(wrappedValue: RootChromeScrollCoordinator(source: "top"))
        #else
        _coordinator = StateObject(wrappedValue: RootChromeScrollCoordinator())
        #endif
    }

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
                coordinator.handlePhaseChange(from: oldPhase, to: newPhase) { visible in
                    setVisible(visible)
                }
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

        withAnimation(.easeOut(duration: 0.22)) {
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
