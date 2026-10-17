import Foundation
import Testing
@testable import Diple

struct ActivityTooltipTests {
    static let tuesday = Calendar.current.date(from: DateComponents(year: 2025, month: 9, day: 16, hour: 12))!

    @Test func namesTheDayAndCountsReviewsInTheRightNumber() {
        #expect(ActivityDay(date: Self.tuesday, reviews: 12).tooltip == "Tue, Sep 16 — 12 reviews")
        #expect(ActivityDay(date: Self.tuesday, reviews: 1).tooltip == "Tue, Sep 16 — 1 review")
        #expect(ActivityDay(date: Self.tuesday, reviews: 0).tooltip == "Tue, Sep 16 — No reviews")
    }
}
