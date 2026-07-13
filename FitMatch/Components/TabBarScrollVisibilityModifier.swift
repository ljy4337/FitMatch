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

struct TabBarScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TabBarScrollCoordinateSpaceModifier: ViewModifier {
    let tab: AppTab

    func body(content: Content) -> some View {
        content.coordinateSpace(name: coordinateSpaceName(for: tab))
    }
}

private struct BottomTabBarScrollVisibilityModifier: ViewModifier {
    @EnvironmentObject private var tabBarVisibilityController: TabBarVisibilityController
    let tab: AppTab
    @State private var lastOffset: CGFloat?
    @State private var hideAccumulation: CGFloat = 0
    @State private var showAccumulation: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(TabBarScrollOffsetPreferenceKey.self) { currentOffset in
                handleOffset(currentOffset)
            }
            .onDisappear {
                lastOffset = nil
                hideAccumulation = 0
                showAccumulation = 0
                tabBarVisibilityController.showScroll(tab: tab, source: "screen disappear")
            }
            .onAppear {
                lastOffset = nil
                hideAccumulation = 0
                showAccumulation = 0
                tabBarVisibilityController.showScroll(tab: tab, source: "screen appear")
            }
    }

    private func handleOffset(_ currentOffset: CGFloat) {
        guard currentOffset.isFinite else { return }

        let previousOffset = lastOffset ?? currentOffset
        let delta = currentOffset - previousOffset
        lastOffset = currentOffset

        print("[TabBarScroll] tab=\(tab.logName) currentOffset=\(String(format: "%.1f", currentOffset)) delta=\(String(format: "%.1f", delta))")

        if currentOffset >= -2 {
            hideAccumulation = 0
            showAccumulation = 0
            tabBarVisibilityController.showScroll(tab: tab, source: "top")
            return
        }

        if delta < 0 {
            hideAccumulation += abs(delta)
            showAccumulation = 0
            if hideAccumulation >= 12 {
                tabBarVisibilityController.hideScroll(tab: tab, source: "scroll down")
            }
        } else if delta > 0 {
            showAccumulation += delta
            hideAccumulation = 0
            if showAccumulation >= 12 {
                tabBarVisibilityController.showScroll(tab: tab, source: "scroll up")
            }
        }
    }
}

func coordinateSpaceName(for tab: AppTab) -> String {
    "FitMatchTabScroll-\(tab.logName)"
}

struct TabBarScrollSentinel: View {
    let tab: AppTab

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: TabBarScrollOffsetPreferenceKey.self,
                value: proxy.frame(in: .named(coordinateSpaceName(for: tab))).minY
            )
        }
        .frame(height: 1)
    }
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
    func fitMatchTabScrollCoordinateSpace(_ tab: AppTab) -> some View {
        modifier(TabBarScrollCoordinateSpaceModifier(tab: tab))
    }

    func hidesBottomTabBarOnScroll(tab: AppTab) -> some View {
        modifier(BottomTabBarScrollVisibilityModifier(tab: tab))
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
