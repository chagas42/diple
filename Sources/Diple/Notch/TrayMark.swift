import SwiftUI

struct TrayMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let count: Int
    let focused: Bool
    var size: CGFloat = 12

    static func symbol(count: Int, focused: Bool) -> String {
        focused ? "moon.fill" : count > 0 ? "tray.full.fill" : "tray"
    }

    var body: some View {
        Image(systemName: Self.symbol(count: count, focused: focused))
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(focused ? FocusCover.indigo : .white.opacity(count > 0 ? 0.92 : 0.42))
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? 0 : count)
            .animation(.easeOut(duration: 0.25), value: focused)
            .animation(.easeOut(duration: 0.25), value: count > 0)
    }
}
