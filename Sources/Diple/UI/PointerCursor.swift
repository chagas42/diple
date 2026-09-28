import AppKit
import SwiftUI

private struct PointerCursor: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content.onHover { inside in
            guard active else { return }
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

extension View {
    func clickable(_ active: Bool = true) -> some View {
        modifier(PointerCursor(active: active))
    }
}
