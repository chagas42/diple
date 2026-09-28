import AppKit
import SwiftUI

struct PointerArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Tracking() }
    func updateNSView(_ v: NSView, context: Context) {}

    final class Tracking: NSView {
        override func resetCursorRects() {
            discardCursorRects()
            addCursorRect(bounds, cursor: .pointingHand)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

extension View {
    func clickable(_ active: Bool = true) -> some View {
        overlay { if active { PointerArea().allowsHitTesting(false) } }
    }
}
