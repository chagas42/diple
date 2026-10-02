import Testing
@testable import Diple

@Suite struct CodeThemeTests {
    @Test func everyThemeHasItsOwnID() {
        let ids = CodeTheme.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func oxocarbonDarkIsPickedByItsID() {
        #expect(CodeTheme.named("oxocarbon-dark") == .oxocarbonDark)
        #expect(CodeTheme.oxocarbonDark.dark)
    }

    @Test func anUnknownThemeFallsBackToDipleDark() {
        #expect(CodeTheme.named("not-a-theme") == .dipleDark)
        #expect(CodeTheme.named(nil) == .dipleDark)
    }
}
