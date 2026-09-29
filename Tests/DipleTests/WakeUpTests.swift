import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct WakeUpTests {
    final class Log {
        var steps: [(NotchState, CGFloat)] = []
    }

    func notch(fullScreen: Bool = false, log: Log, during: ((NotchController, Int) -> Void)? = nil) -> NotchController {
        let n = NotchController()
        n.wakes = true
        n.fullScreen = { fullScreen }
        n.pointer = { CGPoint(x: -1000, y: -1000) }
        n.nap = { [weak n] _ in
            guard let n else { return }
            log.steps.append((n.state, n.eye.lid))
            during?(n, log.steps.count)
        }
        return n
    }

    @Test func itDozesWithTheEyeClosedAndEndsAwake() async {
        let log = Log()
        let n = notch(log: log)
        n.settleBeforeFirstFrame()
        n.fallAsleep()
        #expect(n.state == .active)
        #expect(n.eye.lid == 0)
        #expect(n.asleep)

        await n.wake()

        #expect(log.steps.first?.1 == 0)
        #expect(log.steps.contains { $0.1 == 0.45 })
        #expect(log.steps.filter { $0.1 == 0.05 }.count == 3)
        #expect(log.steps.contains { $0.1 == 0.12 })
        #expect(!n.asleep)
        #expect(n.state == .active)
        #expect(n.eye.lid == 1)
        #expect(!n.waking)
    }

    @Test func overAFullScreenAppItStaysAsleep() async {
        let log = Log()
        let n = notch(fullScreen: true, log: log)
        n.settleBeforeFirstFrame()
        n.fallAsleep()
        await n.wake()
        #expect(n.state == .hidden)
        #expect(!n.waking)
    }

    @Test func openingThePanelMidWakeEndsItAwake() async {
        let log = Log()
        let n = notch(log: log) { n, step in if step == 3 { n.open() } }
        n.settleBeforeFirstFrame()
        n.fallAsleep()
        await n.wake()
        #expect(n.state == .open)
        #expect(n.eye.lid == 1)
        #expect(!n.waking)
    }
}
