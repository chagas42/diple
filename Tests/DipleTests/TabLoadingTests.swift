import Foundation
import Testing
@testable import Diple

final class TabsGitHub: @unchecked Sendable {
    let github = FakeGitHub(.realistic())
    private let lock = NSLock()
    private var repoDelays: [String: Duration] = [:]
    private var rankingDelay: Duration = .zero
    private var teamDelay: Duration = .zero
    private(set) var transport: StubTransport!

    static let people = (0..<5).map { "p\($0)" }

    init() {
        transport = StubTransport { [self] q in self.reply(q) }
    }

    func delay(repo: String, _ d: Duration) { lock.withLock { repoDelays[repo] = d } }
    func delay(ranking d: Duration) { lock.withLock { rankingDelay = d } }
    func delay(team d: Duration) { lock.withLock { teamDelay = d } }

    static func cutoff(_ p: RankPeriod) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.string(from: p.since)
    }

    static func marker(_ q: String) -> Int {
        for p in RankPeriod.allCases where q.contains("created:>\(cutoff(p))") {
            switch p {
            case .week: return 7
            case .month: return 30
            case .quarter: return 90
            }
        }
        return -1
    }

    private func json(_ o: Any) -> Data { try! JSONSerialization.data(withJSONObject: o) }

    private func reply(_ q: String) -> StubTransport.Reply {
        let (repos, ranking, team) = lock.withLock { (repoDelays, rankingDelay, teamDelay) }
        if q.contains("query Beat") || q.contains("query Queue") || q.contains("query Detail") {
            return github.reply(q)
        }
        if q.contains("query RepoPRs") {
            let w = github.world
            let repo = w.all.map(\.repo).first { q.contains("name: \"\($0.split(separator: "/")[1])\"") } ?? ""
            let nodes = w.all.filter { $0.repo == repo }.map(FakeWorld.json)
            let body = json(["data": ["viewer": ["login": w.viewer], "repository": ["pullRequests": ["nodes": nodes]]]])
            return .init(body: body, delay: repos[repo] ?? .zero)
        }
        if q.contains("membersWithRole") {
            let nodes = Self.people.map { ["login": $0, "name": $0.uppercased(), "avatarUrl": "https://example.invalid/\($0).png"] }
            let body = json(["data": ["organization": ["membersWithRole": [
                "pageInfo": ["hasNextPage": false, "endCursor": NSNull()], "nodes": nodes,
            ]]]])
            return .init(body: body, delay: team)
        }
        if q.contains("issueCount") {
            let n = Self.marker(q)
            var data: [String: Any] = [:]
            for i in 0..<Self.people.count where q.contains("u\(i):") { data["u\(i)"] = ["issueCount": n] }
            return .init(body: json(["data": data]), delay: ranking)
        }
        return .init(body: json(["data": ["search": ["nodes": []]]]))
    }
}

@MainActor
@Suite struct TabLoadingTests {
    static func model(_ gh: TabsGitHub, store: Store? = nil, preloading: Bool = false) -> AppModel {
        let model = AppModel(
            client: GitHubClient(transport: gh.transport, tokens: CountingTokens(), metrics: Metrics()),
            store: store ?? Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        )
        model.preloadsTabs = preloading
        return model
    }

    static func waitUntil(_ timeout: Duration = .seconds(5), _ done: () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !done(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func theLastRepositoryClickedWins() async {
        let gh = TabsGitHub()
        gh.delay(repo: "acme/repo0", .milliseconds(300))
        let model = Self.model(gh)
        model.selectRepo("acme/repo0")
        model.selectRepo("acme/repo1")
        await Self.waitUntil { !model.loadingRepo }
        try? await Task.sleep(for: .milliseconds(450))
        #expect(!model.repoPRs.isEmpty)
        #expect(model.repoPRs.allSatisfy { $0.repo == "acme/repo1" })
        #expect(!model.loadingRepo)
    }

    @Test func changingThePeriodMidFetchLoadsTheNewPeriod() async {
        let gh = TabsGitHub()
        let model = Self.model(gh)
        await model.refresh()
        await model.prefetchSettled()
        gh.delay(ranking: .milliseconds(250))
        model.loadTab(.ranking)
        try? await Task.sleep(for: .milliseconds(30))
        model.rankPeriod = .week
        await Self.waitUntil { model.refreshingTab == nil && !model.ranking.isEmpty }
        try? await Task.sleep(for: .milliseconds(350))
        #expect(model.rankPeriod == .week)
        #expect(!model.ranking.isEmpty)
        #expect(model.ranking.allSatisfy { $0.reviews == 7 })
        #expect(model.refreshingTab == nil)
    }

    @Test func aCachedTeamIsRefreshedAlongsideTheRanking() async {
        let gh = TabsGitHub()
        let store = Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        let team = TabsGitHub.people.map { Person(login: $0, name: $0, avatar: URL(string: "https://example.invalid")!) }
        store.updateCache {
            $0.queries = [QueryKey.team(org: "acme").id: StoredQuery(
                data: try! JSONEncoder().encode(team), at: Date().addingTimeInterval(-2 * 24 * 3600)
            )]
        }
        let model = Self.model(gh, store: store)
        await model.refresh()
        await model.prefetchSettled()
        gh.delay(team: .milliseconds(400))
        gh.delay(ranking: .milliseconds(400))

        gh.transport.resetPeak()
        model.loadTab(.ranking)
        await Self.waitUntil { model.refreshingTab == nil }

        #expect(model.ranking.count == TabsGitHub.people.count)
        #expect(model.team.first?.name == "P0")
        #expect(gh.transport.peakConcurrency == 2)
    }

    @Test func theFirstRankingWaitsForTheTeamItNeeds() async {
        let gh = TabsGitHub()
        let model = Self.model(gh)
        await model.refresh()
        await model.prefetchSettled()
        gh.delay(team: .milliseconds(100))
        gh.transport.resetPeak()
        model.loadTab(.ranking)
        await Self.waitUntil { model.refreshingTab == nil }
        #expect(model.team.count == TabsGitHub.people.count)
        #expect(model.ranking.count == TabsGitHub.people.count)
        #expect(gh.transport.peakConcurrency == 1)
    }

    @Test func picksChangedWhileTheRankingPreloadsWinOverThePreload() async {
        let gh = TabsGitHub()
        gh.delay(ranking: .milliseconds(400))
        let store = Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        let model = Self.model(gh, store: store, preloading: true)
        await model.refresh()
        try? await Task.sleep(for: .milliseconds(60))

        gh.delay(ranking: .zero)
        model.toggleFollow("p1")
        model.toggleFollow("p2")
        await model.tabsSettled()
        await Self.waitUntil { model.refreshingTab == nil }
        try? await Task.sleep(for: .milliseconds(100))

        #expect(Set(model.ranking.map(\.person.login)) == ["p1", "p2"])
        let saved = QueryKey.ranking(org: "acme", period: model.rankPeriod, people: ["p1", "p2"]).id
        #expect(store.state.cache.queries?[saved] != nil)
    }

    @Test func openingATabDuringThePreloadSharesItsRequest() async {
        let gh = TabsGitHub()
        gh.delay(ranking: .milliseconds(200))
        let model = Self.model(gh, preloading: true)
        await model.refresh()
        model.loadTab(.ranking)
        await model.tabsSettled()
        #expect(gh.transport.queries.filter { $0.contains("issueCount") }.count == 1)
        #expect(model.ranking.count == TabsGitHub.people.count)
    }

    @Test func tabsAreReadyBeforeTheyAreOpened() async {
        let gh = TabsGitHub()
        let model = Self.model(gh, preloading: true)
        await model.refresh()
        await model.tabsSettled()
        #expect(model.team.count == TabsGitHub.people.count)
        #expect(model.ranking.count == TabsGitHub.people.count)
        #expect(model.refreshingTab == nil)

        let before = gh.transport.queries.count
        model.loadTab(.ranking)
        model.loadTab(.activity)
        #expect(model.refreshingTab == nil)
        #expect(gh.transport.queries.count == before)
    }
}

@MainActor
@Suite struct LaunchLookTests {
    @Test func theNotchShowsTheEyeAndCountFromTheStart() {
        #expect(NotchController().state == .active)
    }
}
