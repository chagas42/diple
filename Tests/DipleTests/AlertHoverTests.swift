import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct AlertHoverTests {
    static let reply = Event(
        id: "t/replied", kind: .repliedToYou, key: "o/r#1",
        url: URL(string: "https://github.com/o/r/pull/1")!,
        title: "Marina replied to you", body: "o/r#1 · fix", threadId: "T1"
    )

    final class Pointer {
        var at: CGPoint
        init(_ at: CGPoint) { self.at = at }
    }

    static let away = CGPoint(x: -1000, y: -1000)

    func notch(_ p: Pointer) -> NotchController {
        let n = NotchController()
        n.pointer = { p.at }
        return n
    }

    var alertCenter: CGPoint {
        let g = NotchGeometry.current()
        let r = g.rect(g.alert)
        return CGPoint(x: r.midX, y: r.midY)
    }

    @Test func movingOverAnAlertKeepsItInsteadOfOpeningThePanel() {
        let p = Pointer(Self.away)
        let n = notch(p)
        n.alert(Self.reply)
        n.checkPointer()

        p.at = alertCenter
        n.checkPointer()
        p.at.x += 40
        n.checkPointer()

        #expect(n.state == .alert(Self.reply))
    }

    @Test func anAlertUnderThePointerIsNotDismissedWhileHovered() {
        let n = notch(Pointer(alertCenter))
        n.alert(Self.reply)
        n.checkPointer()
        #expect(n.state == .alert(Self.reply))
    }

    @Test func leavingTheAlertClosesItShortlyAfter() async throws {
        let p = Pointer(alertCenter)
        let n = notch(p)
        n.alert(Self.reply)
        n.checkPointer()

        n.afterHover = .milliseconds(20)
        p.at = Self.away
        n.checkPointer()
        for _ in 0..<100 where n.state != .active {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(n.state == .active)
    }
}
