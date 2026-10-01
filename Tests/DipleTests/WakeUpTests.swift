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

    @Test func turningTheEyeOffMidWakeEndsIt() async {
        let log = Log()
        let n = notch(log: log) { n, step in if step == 3 { n.arrange(showsEye: false, countOnLeft: false) } }
        n.settleBeforeFirstFrame()
        n.fallAsleep()
        await n.wake()
        #expect(log.steps.count == 3)
        #expect(!n.asleep)
        #expect(!n.waking)
        #expect(n.state == .active)
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

    @Test func theNapPicksTheWakeUp() {
        #expect(Nap(resting: 20) == .short)
        #expect(Nap(resting: Nap.shortest) == .medium)
        #expect(Nap(resting: 20 * 60) == .medium)
        #expect(Nap(resting: Nap.longest) == .long)
        #expect(Nap(resting: 8 * 60 * 60) == .long)
    }

    @Test func withTheEyeOffARestShutsNothing() {
        let n = notch(log: Log())
        n.settleBeforeFirstFrame()
        n.arrange(showsEye: false, countOnLeft: false)
        n.restStarted()
        #expect(!n.waking)
        #expect(n.eye.lid == 1)
    }

    @Test func aShortRestComesBackWithQuickZs() {
        let n = notch(log: Log())
        n.settleBeforeFirstFrame()
        n.restStarted()
        #expect(n.waking)
        #expect(n.eye.lid == 0)
        #expect(!n.asleep)

        n.back(after: 30)
        #expect(n.asleep)
        #expect(n.dozesQuickly)
        #expect(n.waking)
    }

    @Test func aLongRestComesBackDozing() {
        let n = notch(log: Log())
        n.settleBeforeFirstFrame()
        n.restStarted()
        n.back(after: 3 * 60 * 60)
        #expect(n.asleep)
        #expect(!n.dozesQuickly)
        #expect(n.waking)
    }

    @Test func aLongerRestDozesFirst() async {
        let short = Log(), medium = Log(), long = Log()
        for (log, nap) in [(short, Nap.short), (medium, .medium), (long, .long)] {
            let n = notch(log: log)
            n.settleBeforeFirstFrame()
            n.restStarted()
            await n.wake(after: nap)
            #expect(n.eye.lid == 1)
            #expect(!n.waking)
        }
        #expect(short.steps.count < medium.steps.count)
        #expect(medium.steps.count < long.steps.count)
    }

    @Test func comingBackOverAFullScreenAppSkipsTheWake() {
        let full = NotchFullScreenTests.Flag(false)
        let log = Log()
        let n = notch(log: log)
        n.fullScreen = { full.on }
        n.settleBeforeFirstFrame()
        n.restStarted()
        full.on = true
        n.back(after: 600)
        #expect(n.state == .hidden)
        #expect(!n.waking)
    }

    @Test func aLockedMacWaitsForTheUnlock() {
        var now = Date(timeIntervalSince1970: 0)
        var rested: TimeInterval?
        let w = RestWatcher()
        w.clock = { now }
        w.onBack = { rested = $0 }

        w.rest()
        w.lock()
        now += 600
        w.back()
        #expect(rested == nil)

        now += 30
        w.unlock()
        #expect(rested == 600)
    }

    @Test func sleepAndScreenNotificationsCountAsOneRest() {
        var now = Date(timeIntervalSince1970: 0)
        var rests = 0
        var backs: [TimeInterval] = []
        let w = RestWatcher()
        w.clock = { now }
        w.onRest = { rests += 1 }
        w.onBack = { backs.append($0) }

        w.rest()
        now += 5
        w.rest()
        now += 90
        w.back()
        w.back()

        #expect(rests == 1)
        #expect(backs == [95])
    }

    @Test func aPokeSquintsSoreAndReopens() async {
        let log = Log()
        var squinted = false
        var complained = false
        let n = notch(log: log) { n, _ in
            if n.eye.sore && n.eye.lid < 0.2 { squinted = true }
            if n.eye.complaining { complained = true }
        }
        n.settleBeforeFirstFrame()
        n.fallAsleep()

        await n.ouch()

        #expect(squinted)
        #expect(complained)
        #expect(n.eye.pokes == 1)
        #expect(n.eye.complaint == EyeState.complaints[0])
        #expect(!n.eye.complaining)
        #expect(!n.eye.sore)
        #expect(n.eye.lid == 1)
        #expect(!n.waking)
    }
}
