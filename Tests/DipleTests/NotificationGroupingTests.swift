import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct NotificationGroupingTests {
    static func event(_ key: String) -> Event {
        Event(id: key, kind: .commented, key: key, url: URL(string: "https://example.invalid")!,
              title: "", body: "")
    }

    static func notifier(stackPerPR: Bool) -> Notifier {
        let n = Notifier()
        n.settings.stackPerPR = stackPerPR
        return n
    }

    static func thread(_ key: String, _ n: Notifier) -> String {
        n.content(for: event(key), force: false).threadIdentifier
    }

    @Test func byDefaultNotificationsFromDifferentPRsStackTogether() {
        let n = Notifier()
        #expect(Self.thread("acme/api#1", n) == Self.thread("acme/web#2", n))
    }

    @Test func stackingPerPRSeparatesPRs() {
        let n = Self.notifier(stackPerPR: true)
        #expect(Self.thread("acme/api#1", n) != Self.thread("acme/web#2", n))
    }

    @Test func stackingPerPRKeepsOnePRTogether() {
        let n = Self.notifier(stackPerPR: true)
        #expect(Self.thread("acme/api#1", n) == Self.thread("acme/api#1", n))
        #expect(!Self.thread("acme/api#1", n).isEmpty)
    }

    @Test func settingsSavedBeforeTheOptionExistedStackTogether() throws {
        let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"quietHoursOn":false}"#.utf8))
        #expect(!old.stackPerPR)
    }

    @Test func theChoiceSurvivesASave() throws {
        var s = Settings()
        s.stackPerPR = true
        let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        #expect(back.stackPerPR)
    }
}
