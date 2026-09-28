import Foundation
import Testing
@testable import Diple

@Suite struct AlertSoundTests {
    static func at(weekday: Int, hour: Int) -> Date {
        var c = DateComponents()
        c.year = 2026
        c.month = 9
        c.day = 20 + weekday
        c.hour = hour
        return Calendar.current.date(from: c)!
    }

    static let sundayNight = at(weekday: 0, hour: 22)
    static let mondayAfternoon = at(weekday: 1, hour: 15)
    static let mondayNight = at(weekday: 1, hour: 22)

    static func event(_ kind: EventKind, test: Bool = false) -> Event {
        Event(id: "e", kind: kind, key: "acme/api#1", url: URL(string: "https://example.invalid")!,
              title: "", body: "", isTest: test)
    }

    @Test func aFailedCheckAtWorkPlaysBasso() {
        #expect(Settings().alertSound(Self.event(.checkFailed), now: Self.mondayAfternoon) == .plays("Basso"))
    }

    @Test func aFailedCheckOnASundayNightSaysItWasSilenced() {
        #expect(Settings().alertSound(Self.event(.checkFailed), now: Self.sundayNight) == .quietHours)
        #expect(Settings().alertSound(Self.event(.checkFailed), now: Self.mondayNight) == .quietHours)
    }

    @Test func aDirectReplyStillPlaysInQuietHours() {
        #expect(Settings().alertSound(Self.event(.repliedToYou), now: Self.sundayNight) == .plays("Glass"))
    }

    @Test func quietHoursOffPlaysAtNight() {
        var s = Settings()
        s.quietHoursOn = false
        #expect(s.alertSound(Self.event(.checkFailed), now: Self.mondayNight) == .plays("Basso"))
    }

    @Test func aKindTurnedOffInSettingsSaysMuted() {
        var s = Settings()
        s.alerts[EventKind.checkFailed.rawValue] = false
        #expect(s.alertSound(Self.event(.checkFailed), now: Self.mondayAfternoon) == .muted)
    }

    @Test func aSoundSetToNoneIsSilentNotQuiet() {
        var s = Settings()
        s.sounds[EventKind.checkFailed.rawValue] = ""
        #expect(s.alertSound(Self.event(.checkFailed), now: Self.mondayAfternoon) == .silent)
    }

    @Test func theTestButtonAlwaysPlaysBecauseItBypassesQuietHours() {
        #expect(Settings().alertSound(Self.event(.checkFailed, test: true), now: Self.sundayNight) == .plays("Basso"))
    }

    @Test func whatTheNotchSaysMatchesWhetherTheNotificationRings() {
        for now in [Self.sundayNight, Self.mondayAfternoon, Self.mondayNight] {
            for kind in EventKind.allCases {
                let s = Settings()
                let says = s.alertSound(Self.event(kind), now: now)
                let rings = s.shouldInterrupt(kind, now: now) && s.sound(kind) != nil
                if case .plays = says { #expect(rings) } else { #expect(!rings) }
            }
        }
    }
}
