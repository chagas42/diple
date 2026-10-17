import Foundation

struct Person: Identifiable, Sendable, Equatable, Codable {
    let login: String
    let name: String
    let avatar: URL
    var id: String { login }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.compactMap { $0.first }.map(String.init).joined()
        return s.isEmpty ? String(login.prefix(2)).uppercased() : s.uppercased()
    }
}

struct RankRow: Identifiable, Sendable, Equatable, Codable {
    let person: Person
    let reviews: Int
    var id: String { person.login }
}

struct ActivityDay: Identifiable, Sendable, Equatable, Codable {
    let date: Date
    let reviews: Int
    var id: TimeInterval { date.timeIntervalSince1970 }

    enum CodingKeys: String, CodingKey { case date, reviews }

    var tooltip: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, MMM d"
        let count = switch reviews {
        case 0: "No reviews"
        case 1: "1 review"
        default: "\(reviews) reviews"
        }
        return "\(f.string(from: date)) — \(count)"
    }
}

enum ActivityHistory {
    static let days = 182
    static let pagesPerWindow = 10
    static let windowDays = 30
    static let refetchedDays = 2

    struct Page {
        var occurred: [Date]
        var next: String?
    }

    static func page(_ payload: Data) throws -> Page {
        let obj = try JSONSerialization.jsonObject(with: payload) as? [String: Any] ?? [:]
        if let errors = obj["errors"] as? [[String: Any]], !errors.isEmpty {
            throw ClientError.graphql(errors.compactMap { $0["message"] as? String })
        }
        let search = (obj["data"] as? [String: Any])?["search"] as? [String: Any]
        let iso = ISO8601DateFormatter()
        let occurred = (search?["nodes"] as? [[String: Any]] ?? []).flatMap { pr in
            ((pr["reviews"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []).compactMap {
                ($0["submittedAt"] as? String).flatMap(iso.date(from:))
            }
        }
        let info = search?["pageInfo"] as? [String: Any]
        let next = (info?["hasNextPage"] as? Bool) == true ? info?["endCursor"] as? String : nil
        return Page(occurred: occurred, next: next)
    }

    static func windows(from: Date, to: Date) -> [String] {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let f = DateFormatter()
        f.calendar = utc
        f.timeZone = utc.timeZone
        f.dateFormat = "yyyy-MM-dd"
        var start = utc.startOfDay(for: from)
        let last = utc.startOfDay(for: to)
        var ranges: [String] = []
        while start <= last {
            let end = min(last, utc.date(byAdding: .day, value: windowDays - 1, to: start) ?? last)
            ranges.append("\(f.string(from: start))..\(f.string(from: end))")
            guard let next = utc.date(byAdding: .day, value: 1, to: end) else { break }
            start = next
        }
        return ranges
    }

    static func perDay(_ occurred: [Date], calendar: Calendar = .current) -> [Date: Int] {
        occurred.reduce(into: [:]) { $0[calendar.startOfDay(for: $1), default: 0] += 1 }
    }

    static func grid(endingOn today: Date, calendar: Calendar = .current) -> [Date] {
        let last = calendar.startOfDay(for: today)
        return (0..<days).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: last) }
    }

    static func refetchFrom(today: Date, cachedFrom: Date?, calendar: Calendar = .current) -> Date {
        let start = grid(endingOn: today, calendar: calendar).first ?? today
        guard let cachedFrom, cachedFrom <= start else { return start }
        let recent = calendar.date(byAdding: .day, value: -(refetchedDays - 1), to: calendar.startOfDay(for: today)) ?? start
        return max(start, recent)
    }

    static func merged(old: [ActivityDay], fresh: [Date: Int], from: Date, today: Date,
                       calendar: Calendar = .current) -> [ActivityDay] {
        let kept = Dictionary(old.map { (calendar.startOfDay(for: $0.date), $0.reviews) }, uniquingKeysWith: { a, _ in a })
        return grid(endingOn: today, calendar: calendar).map { day in
            ActivityDay(date: day, reviews: day >= from ? fresh[day] ?? 0 : kept[day] ?? 0)
        }
    }
}

extension GitHubClient {
    struct Org: Sendable, Equatable, Identifiable {
        let login: String
        let name: String
        let avatar: URL?
        var id: String { login }
    }

    struct TeamRef: Sendable, Equatable, Identifiable {
        let slug: String
        let name: String
        let members: Int
        var nodeId: String?
        var canAdminister = false
        var id: String { slug }
    }

    func fetchMyOrganizations() async throws -> [Org] {
        let json = try await raw("{ viewer { organizations(first: 100) { nodes { login name avatarUrl(size: 96) } } } }")
        let nodes = (((json["data"] as? [String: Any])?["viewer"] as? [String: Any])?["organizations"] as? [String: Any])?["nodes"]
            as? [[String: Any]] ?? []
        return nodes.compactMap { n in
            guard let login = n["login"] as? String else { return nil }
            return Org(login: login, name: (n["name"] as? String) ?? login, avatar: (n["avatarUrl"] as? String).flatMap(URL.init))
        }
    }

    func fetchMyTeams(org: String, viewer: String) async throws -> [TeamRef] {
        let json = try await raw("""
        { organization(login: "\(org)") {
            teams(first: 100, userLogins: ["\(viewer)"]) { nodes { id slug name viewerCanAdminister members { totalCount } } }
        } }
        """)
        let nodes = ((((json["data"] as? [String: Any])?["organization"] as? [String: Any])?["teams"] as? [String: Any])?["nodes"]
            as? [[String: Any]]) ?? []
        return nodes.compactMap { n in
            guard let slug = n["slug"] as? String else { return nil }
            let count = ((n["members"] as? [String: Any])?["totalCount"] as? Int) ?? 0
            return TeamRef(slug: slug, name: (n["name"] as? String) ?? slug, members: count,
                           nodeId: n["id"] as? String, canAdminister: n["viewerCanAdminister"] as? Bool ?? false)
        }
    }

    func fetchTeams(org: String, slugs: [String]) async throws -> [Person] {
        var seen = Set<String>()
        var people: [Person] = []
        for slug in slugs {
            let json = try await raw("""
            { organization(login: "\(org)") { team(slug: "\(slug)") {
                members(first: 100) { nodes { login name avatarUrl(size: 96) } }
            } } }
            """)
            let team = ((json["data"] as? [String: Any])?["organization"] as? [String: Any])?["team"] as? [String: Any]
            let nodes = (team?["members"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
            for n in nodes {
                guard let login = n["login"] as? String, seen.insert(login.lowercased()).inserted,
                      let url = (n["avatarUrl"] as? String).flatMap(URL.init) else { continue }
                people.append(Person(login: login, name: (n["name"] as? String) ?? login, avatar: url))
            }
        }
        return people
    }

    func fetchTeam(org: String) async throws -> [Person] {
        var people: [Person] = []
        var cursor: String?

        for _ in 0..<4 {
            let after = cursor.map { ", after: \"\($0)\"" } ?? ""
            let json = try await raw("""
            { organization(login: "\(org)") {
                membersWithRole(first: 100\(after)) {
                  pageInfo { hasNextPage endCursor }
                  nodes { login name avatarUrl(size: 96) }
                }
            } }
            """)

            let org = (json["data"] as? [String: Any])?["organization"] as? [String: Any]
            let members = org?["membersWithRole"] as? [String: Any]
            let nodes = members?["nodes"] as? [[String: Any]] ?? []

            people += nodes.compactMap { n in
                guard let login = n["login"] as? String,
                      let url = (n["avatarUrl"] as? String).flatMap(URL.init) else { return nil }
                return Person(login: login, name: (n["name"] as? String) ?? login, avatar: url)
            }

            let page = members?["pageInfo"] as? [String: Any]
            guard (page?["hasNextPage"] as? Bool) == true,
                  let next = page?["endCursor"] as? String else { break }
            cursor = next
        }
        return people
    }

    func fetchRanking(org: String, people: [Person], from: Date) async throws -> [RankRow] {
        guard !people.isEmpty else { return [] }
        let targets = Array(people.prefix(30))

        func search(_ p: Person, after: String?) -> String {
            let page = after.map { ", after: \"\($0)\"" } ?? ""
            return """
            search(query: "\(RankingPage.query(org: org, login: p.login, from: from))", \
            type: ISSUE, first: 100\(page)) { issueCount pageInfo { hasNextPage endCursor } \
            nodes { ... on PullRequest { reviews(author: "\(p.login)", last: 1) { nodes { submittedAt } } } } }
            """
        }

        let json = try await raw("{\n" + targets.enumerated().map { i, p in "  u\(i): " + search(p, after: nil) }.joined(separator: "\n") + "\n}")
        let data = json["data"] as? [String: Any] ?? [:]

        var rows: [RankRow] = []
        for (i, p) in targets.enumerated() {
            guard var page = RankingPage(data["u\(i)"], from: from) else { continue }
            var reviews = page.reviewed
            for _ in 0..<RankingPage.extraPages {
                guard let next = page.next else { break }
                let more = try await raw("{\n  u: " + search(p, after: next) + "\n}")
                guard let following = RankingPage((more["data"] as? [String: Any])?["u"], from: from) else { break }
                reviews += following.reviewed
                page = following
            }
            rows.append(RankRow(person: p, reviews: reviews))
        }
        return rows.sorted { $0.reviews > $1.reviews }
    }

    func fetchReviewCounts(org: String, login: String, from: Date, to: Date = Date()) async throws -> [Date: Int] {
        var occurred: [Date] = []
        for window in ActivityHistory.windows(from: from, to: to) {
            var cursor: String?
            for _ in 0..<ActivityHistory.pagesPerWindow {
                var variables = ["q": "is:pr org:\(org) reviewed-by:\(login) updated:\(window)", "login": login]
                if let cursor { variables["after"] = cursor }
                let payload = try await post("""
                query ReviewDays($q: String!, $login: String!, $after: String) {
                  search(query: $q, type: ISSUE, first: 100, after: $after) {
                    pageInfo { hasNextPage endCursor }
                    nodes { ... on PullRequest { reviews(first: 50, author: $login) { nodes { submittedAt } } } }
                  }
                }
                """, variables: variables)
                let page = try ActivityHistory.page(payload)
                occurred += page.occurred.filter { $0 >= from && $0 <= to }
                guard let next = page.next else { break }
                cursor = next
            }
        }
        return ActivityHistory.perDay(occurred)
    }

    func raw(_ query: String) async throws -> [String: Any] {
        let payload = try await post(query)
        let obj = try JSONSerialization.jsonObject(with: payload) as? [String: Any] ?? [:]
        if let errors = obj["errors"] as? [[String: Any]], !errors.isEmpty {
            throw ClientError.graphql(errors.compactMap { $0["message"] as? String })
        }
        return obj
    }
}

struct RankingPage {
    static let extraPages = 4

    let reviewed: Int
    let next: String?

    static func query(org: String, login: String, from: Date) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return "is:pr org:\(org) reviewed-by:\(login) updated:>=\(fmt.string(from: from))"
    }

    init?(_ value: Any?, from: Date) {
        guard let search = value as? [String: Any], search["issueCount"] is Int else { return nil }
        let fmt = ISO8601DateFormatter()
        let nodes = search["nodes"] as? [[String: Any]] ?? []
        reviewed = nodes.filter { node in
            let last = ((node["reviews"] as? [String: Any])?["nodes"] as? [[String: Any]])?.last
            guard let at = (last?["submittedAt"] as? String).flatMap(fmt.date(from:)) else { return false }
            return at >= from
        }.count
        let info = search["pageInfo"] as? [String: Any]
        next = (info?["hasNextPage"] as? Bool) == true ? info?["endCursor"] as? String : nil
    }
}
