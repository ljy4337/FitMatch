import SwiftUI
import Combine

@MainActor
final class TabBarVisibilityController: ObservableObject {
    @Published private(set) var isVisible = true

    func show(tab: AppTab? = nil, reason: String = "") {
        guard !isVisible else { return }
        print("[TabBarVisibility] show tab=\(tab?.logName ?? "unknown") reason=\(reason)")
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            isVisible = true
        }
    }

    func hide(tab: AppTab? = nil, reason: String = "") {
        guard isVisible else { return }
        print("[TabBarVisibility] hide tab=\(tab?.logName ?? "unknown") reason=\(reason)")
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            isVisible = false
        }
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
                .frame(height: 0)
            }
            .onPreferenceChange(TabBarScrollOffsetPreferenceKey.self) { currentOffset in
                handleOffset(currentOffset)
            }
            .onDisappear {
                lastOffset = nil
                hideAccumulation = 0
                tabBarVisibilityController.show(tab: tab, reason: "screen disappear")
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
            tabBarVisibilityController.show(tab: tab, reason: "top")
            return
        }

        if delta < 0 {
            hideAccumulation += abs(delta)
            if hideAccumulation >= 40 {
                tabBarVisibilityController.hide(tab: tab, reason: "scroll down")
            }
        } else if delta > 12 {
            hideAccumulation = 0
            tabBarVisibilityController.show(tab: tab, reason: "scroll up")
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
            .frame(height: 0)
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
