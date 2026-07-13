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

private struct TabBarScrollOffsetPreferenceKey: PreferenceKey {
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

private struct TabBarScrollContentObserverModifier: ViewModifier {
    @EnvironmentObject private var tabBarVisibilityController: TabBarVisibilityController
    let tab: AppTab
    @State private var lastOffset: CGFloat?
    @State private var hideAccumulation: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(alignment: .top) {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TabBarScrollOffsetPreferenceKey.self,
                        value: proxy.frame(in: .named(coordinateSpaceName(for: tab))).minY
                    )
                }
                .frame(height: 1)
            }
            .onPreferenceChange(TabBarScrollOffsetPreferenceKey.self) { currentOffset in
                handleOffset(currentOffset)
            }
            .onDisappear {
                lastOffset = nil
                hideAccumulation = 0
                tabBarVisibilityController.release(tab: tab, reason: .scrolling, source: "screen disappear")
            }
            .onAppear {
                lastOffset = nil
                hideAccumulation = 0
                tabBarVisibilityController.release(tab: tab, reason: .scrolling, source: "screen appear")
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
            tabBarVisibilityController.release(tab: tab, reason: .scrolling, source: "top")
            return
        }

        if delta < 0 {
            hideAccumulation += abs(delta)
            if hideAccumulation >= 40 {
                tabBarVisibilityController.hide(tab: tab, reason: .scrolling, source: "scroll down")
            }
        } else if delta > 12 {
            hideAccumulation = 0
            tabBarVisibilityController.release(tab: tab, reason: .scrolling, source: "scroll up")
        }
    }
}

private func coordinateSpaceName(for tab: AppTab) -> String {
    "FitMatchTabScroll-\(tab.logName)"
}

struct TabBarScrollSentinel: View {
    let tab: AppTab

    var body: some View {
        Color.clear
            .frame(height: 1)
            .tracksTabBarVisibilityOnScroll(tab)
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

    func tracksTabBarVisibilityOnScroll(_ tab: AppTab) -> some View {
        modifier(TabBarScrollContentObserverModifier(tab: tab))
    }

    func hidesTabBarOnScroll() -> some View {
        self
    }

    func hidesTopChromeOnScroll(_ isVisible: Binding<Bool>) -> some View {
        modifier(TopChromeScrollVisibilityModifier(isVisible: isVisible))
    }
}
