import Foundation
import Testing
@testable import Diple

@Suite struct PRRowTests {
    @Test func timesAreShort() {
        let now = Date()
        func ago(_ s: TimeInterval) -> String { PRRow.ago(now.addingTimeInterval(-s), now: now) }
        #expect(ago(20) == "now")
        #expect(ago(5 * 60) == "5m")
        #expect(ago(7 * 3600) == "7h")
        #expect(ago(3 * 86_400) == "3d")
        #expect(ago(14 * 86_400) == "2w")
        #expect(ago(90 * 86_400) == "3mo")
        #expect(ago(800 * 86_400) == "2y")
    }
}
