import Foundation

enum Queries {
    static func team(org: String) -> CacheQuery<[Person]> {
        CacheQuery(
            key: .team(org: org), tags: [.team],
            staleAfter: .seconds(24 * 3600), forgetAfter: .seconds(7 * 24 * 3600), persists: true
        ) { try await $0.fetchTeam(org: org) }
    }

    static func ranking(org: String, period: RankPeriod, logins: [String]) -> CacheQuery<[RankRow]> {
        let logins = logins.sorted()
        return CacheQuery(
            key: .ranking(org: org, period: period, people: logins), tags: [.team],
            staleAfter: .seconds(period.freshFor), forgetAfter: .seconds(24 * 3600), persists: true
        ) { try await $0.fetchRanking(org: org, people: logins.map(Person.placeholder), from: period.since) }
    }

    static let repos = CacheQuery<[RepoRef]>(
        key: .repos, staleAfter: .seconds(24 * 3600), forgetAfter: .seconds(30 * 24 * 3600), persists: true
    ) { try await $0.fetchRepos() }

    static func repoPRs(_ repo: String) -> CacheQuery<[PR]> {
        CacheQuery(
            key: .repoPRs(repo: repo), tags: [.repo(repo)],
            staleAfter: .seconds(60), forgetAfter: .seconds(1800)
        ) { try await $0.fetchRepoPRs(repo) }
    }

    static let perPRForgetAfter: Duration = .seconds(3600)

    static func reviewContext(_ pr: PR) -> CacheQuery<ReviewContext> {
        CacheQuery(
            key: .reviewContext(pr: pr.key, at: pr.updatedAt), tags: [.pr(pr.key)],
            staleAfter: .seconds(24 * 3600), forgetAfter: perPRForgetAfter
        ) { try await $0.reviewContext(repo: pr.repo, pr: pr.number) }
    }

    static func changedFiles(_ pr: PR) -> CacheQuery<PRFiles> {
        CacheQuery(
            key: .changedFiles(pr: pr.key, at: pr.updatedAt), tags: [.pr(pr.key)],
            staleAfter: .seconds(24 * 3600), forgetAfter: perPRForgetAfter
        ) { try await $0.changedFiles(repo: pr.repo, pr: pr.number) }
    }

    static func activity(org: String, login: String) -> CacheQuery<ActivityLog> {
        CacheQuery(
            key: .activity(org: org, login: login), tags: [.team],
            staleAfter: .seconds(3600), forgetAfter: .seconds(7 * 24 * 3600), persists: true,
            persistFor: .seconds(Double(ActivityHistory.days) * 24 * 3600)
        ) { github, old in
            let today = Date()
            let from = ActivityHistory.refetchFrom(today: today, cachedFrom: old?.from)
            let counts = try await github.fetchReviewCounts(org: org, login: login, from: from, to: today)
            let days = ActivityHistory.merged(old: old?.days ?? [], fresh: counts, from: from, today: today)
            return ActivityLog(days: days, from: min(old?.from ?? from, from))
        }
    }
}

struct ActivityLog: Codable, Sendable, Equatable {
    var days: [ActivityDay]
    var from: Date
}

extension CacheQuery {
    func onError(_ handle: @escaping @MainActor @Sendable (Error) -> Void) -> CacheQuery<T> {
        var q = self
        q.onError = handle
        return q
    }
}

extension Person {
    static func placeholder(_ login: String) -> Person {
        Person(login: login, name: login, avatar: URL(string: "https://github.com/\(login).png")!)
    }
}
