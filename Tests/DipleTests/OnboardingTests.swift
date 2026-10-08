import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct OnboardingTests {
    static func decode(_ json: String) throws -> Settings {
        try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
    }

    @Test func quietWeekendsBecomeMondayToFriday() throws {
        #expect(try Self.decode(#"{"quietOnWeekends": true}"#).workDays == Settings.weekdays)
        #expect(try Self.decode(#"{"quietOnWeekends": false}"#).workDays == Settings.everyDay)
        #expect(try Self.decode(#"{"workDays": [1, 7]}"#).workDays == [1, 7])
    }

    @Test func aSaturdayYouWorkIsNotQuiet() throws {
        var s = Settings()
        s.quietFrom = 23
        s.quietUntil = 6
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let saturdayNoon = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))!
        #expect(!s.shouldInterrupt(.reviewRequested, now: saturdayNoon))
        s.workDays.insert(7)
        #expect(s.shouldInterrupt(.reviewRequested, now: saturdayNoon))
    }

    @Test func teamsAreKeptPerOrganization() {
        var s = Settings()
        s.teams = ["SalvyLTD/engineering", "Eventt-Hub/core", "salvyltd/platform"]
        #expect(s.teams(in: "SalvyLTD") == ["engineering", "platform"])
        #expect(s.teams(in: "acme").isEmpty)
    }

    static func model() -> AppModel {
        AppModel(
            client: GitHubClient(transport: StubTransport { _ in .init(status: 200) }, tokens: CountingTokens(), metrics: Metrics()),
            store: Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        )
    }

    @Test func thePickedOrganizationWinsOverTheGuess() {
        let model = Self.model()
        #expect(model.org == "")
        model.settings.primaryOrg = "SalvyLTD"
        #expect(model.org == "SalvyLTD")
    }

    @Test func theOnboardingShowsUntilItIsFinished() {
        let model = Self.model()
        #expect(model.needsOnboarding)
        model.finishOnboarding()
        #expect(!model.needsOnboarding)
    }

    @Test func pickedTeamsAskForTheirMembersInsteadOfTheWholeOrg() {
        #expect(Queries.teams(org: "acme", slugs: ["b", "a"]).key == .teams(org: "acme", slugs: ["a", "b"]))
        #expect(QueryKey.teams(org: "acme", slugs: ["a", "b"]).id == "teams/acme/a,b")
    }
}
