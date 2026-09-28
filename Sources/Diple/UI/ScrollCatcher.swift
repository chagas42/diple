import AppKit
import SwiftUI

struct ScrollCatcher: NSViewRepresentable {
    enum Move: Sendable {
        case zoom(by: CGFloat, at: CGPoint)
        case pan(by: CGSize)
    }

    let onMove: (Move) -> Void

    func makeNSView(context: Context) -> Catcher {
        let v = Catcher()
        v.onMove = onMove
        return v
    }

    func updateNSView(_ v: Catcher, context: Context) { v.onMove = onMove }

    final class Catcher: NSView {
        var onMove: ((Move) -> Void)?

        override var acceptsFirstResponder: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func scrollWheel(with event: NSEvent) {
            let where_ = convert(event.locationInWindow, from: nil)
            let at = CGPoint(x: where_.x, y: bounds.height - where_.y)

            let wheel = !event.hasPreciseScrollingDeltas
            let zooming = wheel || event.modifierFlags.contains(.command)

            if zooming {
                let steps = event.scrollingDeltaY
                guard steps != 0 else { return }
                let factor = pow(1.0015, wheel ? steps * 6 : steps)
                onMove?(.zoom(by: factor, at: at))
            } else {
                onMove?(.pan(by: CGSize(width: event.scrollingDeltaX,
                                        height: event.scrollingDeltaY)))
            }
        }
    }
}
