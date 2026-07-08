import SwiftUI

private struct TabBarScrollVisibilityModifier: ViewModifier {
    @State private var isTabBarHidden = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { oldValue, newValue in
                updateVisibility(oldOffset: oldValue, newOffset: newValue)
            }
            .toolbar(isTabBarHidden ? .hidden : .visible, for: .tabBar)
            .animation(.easeInOut(duration: 0.18), value: isTabBarHidden)
    }

    private func updateVisibility(oldOffset: CGFloat, newOffset: CGFloat) {
        guard newOffset > 0 else {
            isTabBarHidden = false
            return
        }

        let delta = newOffset - oldOffset
        guard abs(delta) > 6 else {
            return
        }

        isTabBarHidden = delta > 0
    }
}

extension View {
    func hidesTabBarOnScroll() -> some View {
        modifier(TabBarScrollVisibilityModifier())
    }
}
