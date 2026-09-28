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
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        let cutoff = fmt.string(from: from)

        let targets = Array(people.prefix(30))
        let searches = targets.enumerated().map { i, p in
            """
              u\(i): search(query: "is:pr org:\(org) reviewed-by:\(p.login) created:>\(cutoff)", \
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

    func fetchActivity(org: String, login: String, days: Int = 182) async throws -> [ActivityDay] {
        let json = try await raw("""
        { search(query: "is:pr org:\(org) reviewed-by:\(login) sort:updated", type: ISSUE, first: 100) {
            nodes { ... on PullRequest {
              reviews(first: 20, author: "\(login)") { nodes { submittedAt } }
            } }
        } }
        """)
        let nos = ((json["data"] as? [String: Any])?["search"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []

        let iso = ISO8601DateFormatter()
        var perDay: [String: Int] = [:]
        for pr in nos {
            let rs = (pr["reviews"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
            for r in rs {
                guard let s = r["submittedAt"] as? String, iso.date(from: s) != nil else { continue }
                perDay[String(s.prefix(10)), default: 0] += 1
            }
        }

        let cal = Calendar.current
        let hoje = cal.startOfDay(for: Date())
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.timeZone = .current

        return (0..<days).reversed().compactMap { atras in
            guard let d = cal.date(byAdding: .day, value: -atras, to: hoje) else { return nil }
            return ActivityDay(date: d, reviews: perDay[day.string(from: d)] ?? 0)
        }
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
