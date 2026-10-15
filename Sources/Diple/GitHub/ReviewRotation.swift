import Foundation

struct ReviewRotation: Sendable, Equatable {
    enum Algorithm: String, Sendable, CaseIterable, Identifiable {
        case roundRobin = "ROUND_ROBIN"
        case loadBalance = "LOAD_BALANCE"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .roundRobin:  "Round robin"
            case .loadBalance: "Load balance"
            }
        }

        var detail: String {
            switch self {
            case .roundRobin:  "Takes turns, whoever was asked longest ago goes next."
            case .loadBalance: "Asks whoever has the fewest open review requests."
            }
        }
    }

    var enabled = false
    var algorithm = Algorithm.loadBalance
    var reviewers = 2
    var notifyTeam = true

    static let reviewerRange = 1...5

    init(enabled: Bool = false, algorithm: Algorithm = .loadBalance, reviewers: Int = 2, notifyTeam: Bool = true) {
        self.enabled = enabled
        self.algorithm = algorithm
        self.reviewers = reviewers
        self.notifyTeam = notifyTeam
    }

    init?(team: [String: Any]?) {
        guard let team, let enabled = team["reviewRequestDelegationEnabled"] as? Bool else { return nil }
        self.enabled = enabled
        algorithm = (team["reviewRequestDelegationAlgorithm"] as? String).flatMap(Algorithm.init(rawValue:)) ?? .loadBalance
        reviewers = team["reviewRequestDelegationMemberCount"] as? Int ?? 2
        notifyTeam = team["reviewRequestDelegationNotifyTeam"] as? Bool ?? true
    }

    var summary: String {
        guard enabled else { return "Off: everyone in the team is asked for every review." }
        let people = reviewers == 1 ? "1 person" : "\(reviewers) people"
        return "\(algorithm.title) picks \(people) for each review request"
            + (notifyTeam ? ", and the whole team is notified." : ", and only they are notified.")
    }

    static func mutation(teamId: String, _ r: ReviewRotation) -> String {
        """
        mutation UpdateReviewRotation($id: ID!) {
          updateTeamReviewAssignment(input: {
            id: $id, enabled: \(r.enabled), algorithm: \(r.algorithm.rawValue),
            teamMemberCount: \(r.reviewers), notifyTeam: \(r.notifyTeam)
          }) { team { \(fields) } }
        }
        """
    }

    static let fields = """
    reviewRequestDelegationEnabled reviewRequestDelegationAlgorithm \
    reviewRequestDelegationMemberCount reviewRequestDelegationNotifyTeam
    """

    static func needsScope(_ error: Error) -> Bool {
        guard case ClientError.graphql(let messages) = error else { return false }
        return messages.contains { $0.localizedCaseInsensitiveContains("scope") }
    }

    static func filterNote(_ teams: [String]) -> String? {
        guard !teams.isEmpty else { return nil }
        let names = teams.count == 1 ? teams[0] : teams.dropLast().joined(separator: ", ") + " and " + teams[teams.count - 1]
        return "\(names) \(teams.count == 1 ? "uses" : "use") review rotation, so reviews GitHub assigns to you always show, whatever you pick here."
    }

    static let scopeCommand = "gh auth refresh -h github.com -s admin:org"
}

struct TeamFit: Sendable, Equatable {
    var requests: Int
    var repos: [String]

    enum Verdict: Equatable { case works, ownsButQuiet, neverAsked }

    var verdict: Verdict {
        requests > 0 ? .works : repos.isEmpty ? .neverAsked : .ownsButQuiet
    }

    static func repos(owning slug: String, org: String, in files: [String: String]) -> [String] {
        let handle = "@\(org)/\(slug)".lowercased()
        return files.filter { _, text in
            text.split(separator: "\n").contains { line in
                let rule = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
                return rule.split(whereSeparator: \.isWhitespace).dropFirst().contains { $0.lowercased() == handle }
            }
        }.keys.sorted()
    }

    func headline(team: String) -> String {
        switch verdict {
        case .works:        "\(requests) PRs asked \(team) in 30 days"
        case .ownsButQuiet: "No PRs asked \(team) in 30 days"
        case .neverAsked:   "No PRs ask \(team) as a team"
        }
    }

    func explanation(org: String, team: String, slug: String) -> String {
        let where_ = repos.isEmpty ? "" : " Code owner in " + repos.prefix(3).joined(separator: ", ") + (repos.count > 3 ? " +\(repos.count - 3)" : "") + "."
        switch verdict {
        case .works:
            return "\(requests) pull requests asked \(team) for review in the last 30 days, so the rotation applies to them.\(where_)"
        case .ownsButQuiet:
            return "\(team) is a code owner, but no pull request asked it in the last 30 days, so the rotation has had nothing to do.\(where_)"
        case .neverAsked:
            return "No pull request asks \(team) as a team, so a rotation would never kick in. It works when the team is the reviewer, like `* @\(org)/\(slug)` in CODEOWNERS."
        }
    }
}

struct RotationRead: Sendable, Equatable {
    var rotation: ReviewRotation
    var orgAdmin: Bool
}

enum TeamAccess: Equatable {
    case orgOwner, maintainer, member

    init(team: GitHubClient.TeamRef, orgAdmin: Bool) {
        self = orgAdmin ? .orgOwner : team.canAdminister ? .maintainer : .member
    }

    func short(org: String) -> String {
        switch self {
        case .orgOwner:   "Owner of \(org)"
        case .maintainer: "Team maintainer"
        case .member:     "View only"
        }
    }

    func explanation(org: String, team: String) -> String {
        switch self {
        case .orgOwner:   "Owner of \(org), so you can change this."
        case .maintainer: "Maintainer of \(team), so you can change this."
        case .member:     "Only \(team) maintainers and \(org) owners change this."
        }
    }
}

struct RotationSimulation: Equatable {
    var loads: [Int]
    var cursor = 0

    init(people: Int) {
        loads = (0..<people).map { [4, 0, 3, 1, 4, 1, 0, 2, 3, 1][$0 % 10] }
    }

    mutating func pick(_ r: ReviewRotation, author: Int) -> [Int] {
        let others = loads.indices.filter { $0 != author }
        guard !others.isEmpty else { return [] }
        let picked: [Int]
        if !r.enabled {
            picked = others
        } else {
            let n = min(r.reviewers, others.count)
            switch r.algorithm {
            case .roundRobin:
                let order = (0..<loads.count).map { (cursor + $0) % loads.count }.filter { $0 != author }
                picked = Array(order.prefix(n))
                cursor = ((picked.last ?? cursor) + 1) % loads.count
            case .loadBalance:
                picked = Array(others.sorted { (loads[$0], $0) < (loads[$1], $1) }.prefix(n))
            }
        }
        for i in picked { loads[i] += 1 }
        return picked
    }

    mutating func settle(_ reviews: Int) {
        for k in 0..<reviews {
            guard let busiest = loads.indices.max(by: { (loads[$0], $1) < (loads[$1], $0) }), loads[busiest] > 0 else { return }
            finish(k.isMultiple(of: 3) ? (busiest + 2) % loads.count : busiest)
        }
    }

    mutating func finish(_ i: Int) {
        guard loads.indices.contains(i), loads[i] > 0 else { return }
        loads[i] -= 1
    }
}

extension GitHubClient {
    func fetchOrgTeams(org: String) async throws -> [TeamRef] {
        let json = try await raw("""
        { organization(login: "\(org)") {
            teams(first: 100, orderBy: {field: NAME, direction: ASC}) { nodes { id slug name viewerCanAdminister members { totalCount } } }
        } }
        """)
        let nodes = ((((json["data"] as? [String: Any])?["organization"] as? [String: Any])?["teams"] as? [String: Any])?["nodes"]
            as? [[String: Any]]) ?? []
        return nodes.compactMap { n in
            guard let slug = n["slug"] as? String else { return nil }
            return TeamRef(slug: slug, name: (n["name"] as? String) ?? slug,
                           members: ((n["members"] as? [String: Any])?["totalCount"] as? Int) ?? 0,
                           nodeId: n["id"] as? String, canAdminister: n["viewerCanAdminister"] as? Bool ?? false)
        }
    }

    func fetchMyRotatingTeams(org: String, viewer: String) async throws -> [String] {
        let json = try await raw("""
        { organization(login: "\(org)") {
            teams(first: 100, userLogins: ["\(viewer)"]) { nodes { name reviewRequestDelegationEnabled } }
        } }
        """)
        let nodes = ((((json["data"] as? [String: Any])?["organization"] as? [String: Any])?["teams"] as? [String: Any])?["nodes"]
            as? [[String: Any]]) ?? []
        return nodes.filter { $0["reviewRequestDelegationEnabled"] as? Bool == true }.compactMap { $0["name"] as? String }
    }

    func fetchCodeOwners(org: String) async throws -> [String: String] {
        let json = try await raw("""
        { organization(login: "\(org)") {
            repositories(first: 100, isArchived: false, orderBy: {field: PUSHED_AT, direction: DESC}) { nodes {
              name
              a: object(expression: "HEAD:.github/CODEOWNERS") { ... on Blob { text } }
              b: object(expression: "HEAD:CODEOWNERS") { ... on Blob { text } }
              c: object(expression: "HEAD:docs/CODEOWNERS") { ... on Blob { text } }
            } }
        } }
        """)
        let nodes = ((((json["data"] as? [String: Any])?["organization"] as? [String: Any])?["repositories"] as? [String: Any])?["nodes"]
            as? [[String: Any]]) ?? []
        var files: [String: String] = [:]
        for n in nodes {
            guard let name = n["name"] as? String else { continue }
            let text = ["a", "b", "c"].lazy.compactMap { (n[$0] as? [String: Any])?["text"] as? String }.first
            if let text { files[name] = text }
        }
        return files
    }

    func teamRequests(org: String, slug: String, since: Date) async throws -> Int {
        let day = ISO8601DateFormatter.string(from: since, timeZone: .gmt, formatOptions: [.withFullDate])
        let json = try await raw("""
        { search(type: ISSUE, first: 1, query: "is:pr org:\(org) team-review-requested:\(org)/\(slug) created:>=\(day)") { issueCount } }
        """)
        return ((json["data"] as? [String: Any])?["search"] as? [String: Any])?["issueCount"] as? Int ?? 0
    }

    func fetchRotation(org: String, slug: String) async throws -> RotationRead? {
        let json = try await raw("""
        { organization(login: "\(org)") { viewerCanAdminister team(slug: "\(slug)") { \(ReviewRotation.fields) } } }
        """)
        let organization = (json["data"] as? [String: Any])?["organization"] as? [String: Any]
        guard let rotation = ReviewRotation(team: organization?["team"] as? [String: Any]) else { return nil }
        return RotationRead(rotation: rotation, orgAdmin: organization?["viewerCanAdminister"] as? Bool ?? false)
    }

    func updateRotation(teamId: String, _ rotation: ReviewRotation) async throws -> ReviewRotation? {
        let payload = try await post(ReviewRotation.mutation(teamId: teamId, rotation), variables: ["id": teamId])
        let obj = try JSONSerialization.jsonObject(with: payload) as? [String: Any] ?? [:]
        if let errors = obj["errors"] as? [[String: Any]], !errors.isEmpty {
            throw ClientError.graphql(errors.compactMap { $0["message"] as? String })
        }
        let team = (((obj["data"] as? [String: Any])?["updateTeamReviewAssignment"] as? [String: Any])?["team"]) as? [String: Any]
        return ReviewRotation(team: team)
    }
}
