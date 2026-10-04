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
        let cutoff = RankPeriod.day(from)

        let targets = Array(people.prefix(30))
        let searches = targets.enumerated().map { i, p in
            """
              u\(i): search(query: "is:pr org:\(org) reviewed-by:\(p.login) created:>=\(cutoff)", \
            type: ISSUE, first: 1) { issueCount }
            """
        }.joined(separator: "\n")

        let json = try await raw("{\n\(searches)\n}")
        let data = json["data"] as? [String: Any] ?? [:]
        return targets.enumerated().compactMap { i, p in
            guard let n = (data["u\(i)"] as? [String: Any])?["issueCount"] as? Int else { return nil }
            return RankRow(person: p, reviews: n)
        }
        .sorted { $0.reviews > $1.reviews }
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
