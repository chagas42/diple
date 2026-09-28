import AppKit
import SwiftUI

struct ScrollCatcher: NSViewRepresentable {
    enum Move: Sendable {
        case zoom(by: CGFloat, at: CGPoint)
        case pan(by: CGSize)
    }

    let onMove: (Move) -> Void

    func makeNSView(context: Context) -> NSView {
        let anchor = NSView()
        context.coordinator.watch(anchor)
        return anchor
    }

    func updateNSView(_ v: NSView, context: Context) {
        context.coordinator.onMove = onMove
    }

    func makeCoordinator() -> Coordinator { Coordinator(onMove) }

    static func dismantleNSView(_ v: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        var onMove: (Move) -> Void
        private var monitor: Any?
        private weak var anchor: NSView?

        init(_ onMove: @escaping (Move) -> Void) { self.onMove = onMove }

        func watch(_ view: NSView) {
            anchor = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let anchor = self.anchor, let window = anchor.window,
                      event.window === window
                else { return event }

                let inView = anchor.convert(event.locationInWindow, from: nil)
                guard anchor.bounds.contains(inView) else { return event }

                let at = CGPoint(x: inView.x, y: anchor.bounds.height - inView.y)
                let wheel = !event.hasPreciseScrollingDeltas
                let zooming = wheel || event.modifierFlags.contains(.command)

                if zooming {
                    let steps = event.scrollingDeltaY
                    guard steps != 0 else { return nil }
                    self.onMove(.zoom(by: pow(1.0015, wheel ? steps * 6 : steps), at: at))
                } else {
                    self.onMove(.pan(by: CGSize(width: event.scrollingDeltaX,
                                                height: event.scrollingDeltaY)))
                }
                return nil
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
