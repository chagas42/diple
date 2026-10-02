import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct RankingModeTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return c
    }

    func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    func days(from: String, to: String, reviews: (Date) -> Int) -> [ActivityDay] {
        var out: [ActivityDay] = []
        var d = date(from + " 00:00")
        let end = date(to + " 00:00")
        while d <= end {
            out.append(ActivityDay(date: d, reviews: reviews(d)))
            d = calendar.date(byAdding: .day, value: 1, to: d)!
        }
        return out
    }

    @Test func rankingStartsOff() throws {
        #expect(Settings().rankingMode == .off)
        let old = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        #expect(old.rankingMode == .off)
    }

    @Test func offHidesTheTab() {
        let model = AppModel(client: GitHubClient(transport: StubTransport { _ in .init() }, tokens: CountingTokens()),
                             store: Store(directory: StoreDiffTests.tempDirectory()))
        #expect(!model.notchTabs.contains(.ranking))
        model.notchTab = .ranking
        model.settings.rankingMode = .pace
        #expect(model.notchTabs.contains(.ranking))
        model.settings.rankingMode = .off
        #expect(model.notchTab == .queue)
    }

    @Test func myPaceComparesWithTheShareOfTheUsualSoFar() {
        let history = days(from: "2026-08-03", to: "2026-10-02") { _ in 1 }
        let p = Pace.of(.week, days: history, now: date("2026-10-02 12:00"), calendar: calendar)
        #expect(p.current == 5)
        #expect(p.usual == 7)
        #expect(p.mood == .onPace)
    }

    @Test func aBusyWeekIsAheadAndAQuietOneIsLighter() {
        let busy = days(from: "2026-08-03", to: "2026-10-02") { d in d >= date("2026-09-28 00:00") ? 4 : 1 }
        #expect(Pace.of(.week, days: busy, now: date("2026-10-02 12:00"), calendar: calendar).mood == .ahead)
        let quiet = days(from: "2026-08-03", to: "2026-10-02") { d in d >= date("2026-09-28 00:00") ? 0 : 1 }
        #expect(Pace.of(.week, days: quiet, now: date("2026-10-02 12:00"), calendar: calendar).mood == .lighter)
    }

    @Test func mondayMorningIsNotLighter() {
        let history = days(from: "2026-08-03", to: "2026-10-05") { _ in 1 }
        let p = Pace.of(.week, days: history, now: date("2026-10-05 09:00"), calendar: calendar)
        #expect(p.mood == .early)
    }

    @Test func withoutAFullPeriodThereIsNoUsual() {
        let history = days(from: "2026-09-29", to: "2026-10-02") { _ in 2 }
        let p = Pace.of(.week, days: history, now: date("2026-10-02 12:00"), calendar: calendar)
        #expect(p.usual == nil)
        #expect(p.mood == .noHistory)
    }

    @Test func onlyTheTeamBoardFetchesTheRanking() async {
        let gh = TabsGitHub()
        let model = TabLoadingTests.model(gh)
        model.settings.rankingMode = .pace
        await model.refresh()
        model.loadTab(.ranking)
        await model.tabsSettled()
        #expect(!gh.transport.queries.contains { $0.contains("issueCount") })
    }
}
