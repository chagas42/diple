import Foundation
import Testing
@testable import Diple

struct ActivityHistoryTests {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return c
    }

    static func day(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)!
    }

    static let today = day("2026-09-30").addingTimeInterval(15 * 3600)

    func payload(_ occurred: [String], next: String?) -> Data {
        let info: [String: Any] = ["hasNextPage": next != nil, "endCursor": next ?? NSNull()]
        let nodes: [[String: Any]] = occurred.map { ["reviews": ["nodes": [["submittedAt": $0]]]] } + [[:]]
        let obj: [String: Any] = ["data": ["search": ["pageInfo": info, "nodes": nodes]]]
        return try! JSONSerialization.data(withJSONObject: obj)
    }

    @Test func windowsCoverTheSpanWithoutOverlapping() {
        let windows = ActivityHistory.windows(from: Self.day("2026-04-01"), to: Self.day("2026-06-15"))
        #expect(windows.first?.hasPrefix("2026-04-0") == true)
        #expect(windows.last?.hasSuffix("2026-06-15") == true || windows.last?.hasSuffix("2026-06-14") == true)
        let bounds = windows.map { $0.components(separatedBy: "..") }
        for (a, b) in zip(bounds, bounds.dropFirst()) {
            #expect(a[1] < b[0])
        }
    }

    @Test func aPageYieldsEachReviewAndTheCursorOnlyWhenThereIsMore() throws {
        let more = try ActivityHistory.page(payload(["2026-09-29T12:00:00Z", "2026-09-28T12:00:00Z"], next: "abc"))
        #expect(more.occurred.count == 2)
        #expect(more.next == "abc")
        let last = try ActivityHistory.page(payload(["2026-09-27T12:00:00Z"], next: nil))
        #expect(last.next == nil)
    }

    @Test func reviewsAreCountedOnTheLocalDayNotTheUTCOne() throws {
        let page = try ActivityHistory.page(payload(["2026-09-30T01:30:00Z", "2026-09-29T20:00:00Z"], next: nil))
        let counts = ActivityHistory.perDay(page.occurred, calendar: Self.calendar)
        #expect(counts[Self.day("2026-09-29")] == 2)
        #expect(counts[Self.day("2026-09-30")] == nil)
    }

    @Test func withNoCoveredHistoryTheWholeGridIsFetched() {
        let from = ActivityHistory.refetchFrom(today: Self.today, cachedFrom: nil, calendar: Self.calendar)
        #expect(from == ActivityHistory.grid(endingOn: Self.today, calendar: Self.calendar).first)
    }

    @Test func withTheGridCoveredOnlyTheLastDaysAreFetchedAgain() {
        let start = ActivityHistory.grid(endingOn: Self.today, calendar: Self.calendar).first!
        let from = ActivityHistory.refetchFrom(today: Self.today, cachedFrom: start, calendar: Self.calendar)
        #expect(from == Self.day("2026-09-29"))
    }

    @Test func aCacheFromBeforeHistoryWasFetchedIsNotTrusted() {
        let late = Self.day("2026-09-15")
        let from = ActivityHistory.refetchFrom(today: Self.today, cachedFrom: late, calendar: Self.calendar)
        #expect(from == ActivityHistory.grid(endingOn: Self.today, calendar: Self.calendar).first)
    }

    @Test func mergingKeepsOlderDaysAndReplacesTheRefetchedOnes() {
        let old = [
            ActivityDay(date: Self.day("2026-06-01"), reviews: 7),
            ActivityDay(date: Self.day("2026-09-29"), reviews: 1),
        ]
        let fresh = [Self.day("2026-09-29"): 4, Self.day("2026-09-30"): 2]
        let days = ActivityHistory.merged(old: old, fresh: fresh, from: Self.day("2026-09-29"),
                                          today: Self.today, calendar: Self.calendar)
        #expect(days.count == ActivityHistory.days)
        #expect(days.last?.date == Self.day("2026-09-30"))
        let by = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0.reviews) })
        #expect(by[Self.day("2026-06-01")] == 7)
        #expect(by[Self.day("2026-09-29")] == 4)
        #expect(by[Self.day("2026-09-30")] == 2)
    }
}
