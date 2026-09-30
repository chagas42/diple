import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct FocusTests {
    @Test func aMacOSFocusTurnsItOn() {
        var focused: Bool? = false
        let f = Focus()
        f.read = { focused }
        f.check()
        #expect(!f.isOn)

        focused = true
        f.check()
        #expect(f.system)
        #expect(f.isOn)
    }

    @Test func clickingTheEyeFocusesWithoutAMacOSFocus() {
        let f = Focus()
        f.read = { false }
        f.toggle()
        #expect(f.isOn)
        f.toggle()
        #expect(!f.isOn)
    }

    @Test func notFollowingIgnoresTheMacOSFocus() {
        let f = Focus()
        f.read = { true }
        f.follows = false
        f.check()
        #expect(!f.isOn)
    }

    @Test func noPermissionReadsAsNotFocused() {
        let f = Focus()
        f.read = { nil }
        f.check()
        #expect(!f.isOn)
    }

    @Test func focusedNotificationsArePassiveAndSilent() {
        let n = Notifier()
        let e = Event(id: "x", kind: .commented, key: "o/r#1", url: URL(string: "https://github.com")!,
                      title: "t", body: "b")
        #expect(n.content(for: e, force: false).interruptionLevel != .passive)

        n.quiet = { true }
        let c = n.content(for: e, force: false)
        #expect(c.interruptionLevel == .passive)
        #expect(c.sound == nil)
    }

    @Test func theFirstMinuteCountsSeconds() {
        #expect(FocusCover.lasted(42) == "42 s")
        #expect(FocusCover.lasted(59.9) == "59 s")
        #expect(FocusCover.lasted(60) == "1 min")
        #expect(FocusCover.lasted(12 * 60 + 30) == "12 min")
    }

    @Test func leavingFocusKeepsTheCoverForItsGoodbye() {
        let n = NotchController()
        n.focus(true)
        let since = n.focusedSince
        #expect(since != nil)
        #expect(n.focusEnded == nil)

        n.focus(false)
        #expect(n.focusedSince == since)
        #expect(n.focusEnded != nil)
        #expect(!n.eye.focused)

        n.focus(true)
        #expect(n.focusEnded == nil)
        #expect(n.eye.focused)
    }
}
