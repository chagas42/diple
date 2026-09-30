import Foundation

enum Queries {
    static func team(org: String) -> CacheQuery<[Person]> {
        CacheQuery(
            key: .team(org: org), tags: [.team],
            staleAfter: .seconds(24 * 3600), forgetAfter: .seconds(7 * 24 * 3600), persists: true
        ) { try await $0.fetchTeam(org: org) }
    }

    static func ranking(org: String, period: RankPeriod, people: [Person]) -> CacheQuery<[RankRow]> {
        CacheQuery(
            key: .ranking(org: org, period: period, people: people.map(\.login)), tags: [.team],
            staleAfter: .seconds(period.freshFor), forgetAfter: .seconds(24 * 3600), persists: true
        ) { try await $0.fetchRanking(org: org, people: people, from: period.since) }
    }

    static func activity(org: String, login: String) -> CacheQuery<ActivityLog> {
        CacheQuery(
            key: .activity(org: org, login: login), tags: [.team],
            staleAfter: .seconds(3600), forgetAfter: .seconds(7 * 24 * 3600), persists: true
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
    func onError(_ handle: @escaping @Sendable (Error) async -> Void) -> CacheQuery<T> {
        let fetch = self.fetch
        return CacheQuery(
            key: key, tags: tags, staleAfter: staleAfter, forgetAfter: forgetAfter, persists: persists
        ) { github, old in
            do { return try await fetch(github, old) } catch {
                await handle(error)
                throw error
            }
        }
    }
}
