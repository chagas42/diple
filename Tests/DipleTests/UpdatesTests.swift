import Testing
@testable import Diple

struct UpdatesTests {
    @Test func aHigherPartIsNewer() {
        #expect(Updates.isNewer("1.14.0", than: "1.13.3"))
        #expect(Updates.isNewer("2.0.0", than: "1.99.99"))
        #expect(Updates.isNewer("1.13.10", than: "1.13.9"))
    }

    @Test func theSameOrOlderIsNot() {
        #expect(!Updates.isNewer("1.13.3", than: "1.13.3"))
        #expect(!Updates.isNewer("1.13.2", than: "1.13.3"))
    }

    @Test func aMissingPartCountsAsZero() {
        #expect(!Updates.isNewer("1.13", than: "1.13.0"))
        #expect(Updates.isNewer("1.13.1", than: "1.13"))
    }
}
