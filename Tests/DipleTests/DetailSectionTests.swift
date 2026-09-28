import Testing
@testable import Diple

@MainActor
struct DetailSectionTests {
    @Test func eachPullRequestReopensOnTheTabItWasLeftOn() {
        let model = AppModel(store: Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics()))
        #expect(model.section(for: "o/r#1") == .conversation)

        model.remember(.map, for: "o/r#1")
        model.remember(.ai, for: "o/r#2")

        #expect(model.section(for: "o/r#1") == .map)
        #expect(model.section(for: "o/r#2") == .ai)
        #expect(model.section(for: "o/r#3") == .conversation)
    }
}
