import Foundation
import Testing
@testable import Diple

@Suite struct RankPeriodTests {
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

    func start(_ p: RankPeriod, _ now: String) -> String {
        RankPeriod.day(p.since(now: date(now), calendar: calendar), calendar: calendar)
    }

    @Test func aWeekStartsOnMonday() {
        #expect(start(.week, "2026-10-02 15:00") == "2026-09-28")
        #expect(start(.week, "2026-10-04 23:59") == "2026-09-28")
        #expect(start(.week, "2026-10-05 00:01") == "2026-10-05")
    }

    @Test func aMonthStartsOnTheFirst() {
        #expect(start(.month, "2026-10-02 15:00") == "2026-10-01")
        #expect(start(.month, "2026-09-30 23:59") == "2026-09-01")
    }

    @Test func aQuarterIsACalendarQuarter() {
        #expect(start(.quarter, "2026-10-02 15:00") == "2026-10-01")
        #expect(start(.quarter, "2026-09-30 23:59") == "2026-07-01")
        #expect(start(.quarter, "2026-02-14 10:00") == "2026-01-01")
    }

    @Test func aPeriodStartsAtLocalMidnight() {
        let s = RankPeriod.week.since(now: date("2026-10-02 15:00"), calendar: calendar)
        #expect(calendar.component(.hour, from: s) == 0)
        #expect(calendar.component(.weekday, from: s) == 2)
    }

    @Test func theStartDayIsTheLocalDateNotUTC() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let f = DateFormatter()
        f.calendar = tokyo
        f.timeZone = tokyo.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let monday = RankPeriod.week.since(now: f.date(from: "2026-10-05 09:00")!, calendar: tokyo)
        #expect(RankPeriod.day(monday, calendar: tokyo) == "2026-10-05")
    }
}
