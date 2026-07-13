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
    @State private var hideAccumulation: CGFloat = 0
    @State private var showAccumulation: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { previousOffset, currentOffset in
                handleScrollOffset(previous: previousOffset, current: currentOffset)
            }
            .onDisappear {
                hideAccumulation = 0
                showAccumulation = 0
                tabBarVisibilityController.showScroll(tab: tab, source: "screen disappear")
            }
            .onAppear {
                hideAccumulation = 0
                showAccumulation = 0
                tabBarVisibilityController.showScroll(tab: tab, source: "screen appear")
            }
    }

    private func handleScrollOffset(previous previousOffset: CGFloat, current currentOffset: CGFloat) {
        guard previousOffset.isFinite, currentOffset.isFinite else { return }

        let delta = currentOffset - previousOffset

        print("[TabBarScroll] tab=\(tab.logName) previousOffset=\(String(format: "%.1f", previousOffset)) currentOffset=\(String(format: "%.1f", currentOffset)) delta=\(String(format: "%.1f", delta))")

        guard abs(delta) >= 1 else {
            return
        }

        if currentOffset <= 2 {
            hideAccumulation = 0
            showAccumulation = 0
            print("[TabBarScroll] action=showScroll source=native scroll top tab=\(tab.logName)")
            tabBarVisibilityController.showScroll(tab: tab, source: "native scroll top")
            return
        }

        if delta > 0 {
            hideAccumulation += delta
            showAccumulation = 0
            if hideAccumulation >= 12 {
                print("[TabBarScroll] action=hideScroll source=native scroll down tab=\(tab.logName)")
                tabBarVisibilityController.hideScroll(tab: tab, source: "native scroll down")
            }
        } else {
            showAccumulation += abs(delta)
            hideAccumulation = 0
            if showAccumulation >= 12 {
                print("[TabBarScroll] action=showScroll source=native scroll up tab=\(tab.logName)")
                tabBarVisibilityController.showScroll(tab: tab, source: "native scroll up")
            }
        }
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
