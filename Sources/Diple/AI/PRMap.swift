import Foundation

struct MapNode: Identifiable, Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case domain, changed, affected, context
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    var detail: String
    let path: String?
    let line: Int?
    let isDirectory: Bool
    var additions: Int = 0
    var deletions: Int = 0
    var files: Int = 0
    var prs: [Int] = []

    var churn: Int { additions + deletions }
    var diff: String? { churn > 0 ? "+\(additions) −\(deletions)" : nil }
}

struct MapEdge: Identifiable, Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case contains, relates, feels, explains
    }

    var id: String { "\(from)>\(to)" }
    let from: String
    let to: String
    let kind: Kind
    let label: String?
}

struct MapSize: Codable, Sendable, Equatable {
    var files = 0
    var additions = 0
    var deletions = 0
    var domains = 0
    var modules = 0
    var prs = 1

    var lines: Int { additions + deletions }
}

struct PRMap: Codable, Sendable, Equatable {
    var repo = ""
    var base = ""
    var head = ""
    var stack: [Int] = []
    var intent = ""
    var deltas: [String] = []
    var nodes: [MapNode] = []
    var edges: [MapEdge] = []
    var size = MapSize()
    var hidden = 0
    var enriched = false

    var layoutKey: String { "\(repo)@\(stack.map(String.init).joined(separator: "+"))" }

    func nodes(_ kind: MapNode.Kind) -> [MapNode] { nodes.filter { $0.kind == kind } }
}

struct ChangedFile: Sendable, Equatable {
    let path: String
    let additions: Int
    let deletions: Int
}

struct PRFiles: Sendable, Equatable {
    let number: Int
    let base: String
    let head: String
    let files: [ChangedFile]
}

extension GitHubClient {
    func changedFiles(repo: String, pr: Int) async throws -> PRFiles {
        let parts = repo.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return PRFiles(number: pr, base: "", head: "", files: []) }

        var files: [ChangedFile] = []
        var base = ""
        var head = ""
        var cursor: String?

        for _ in 0..<30 {
            let after = cursor.map { ", after: \"\($0)\"" } ?? ""
            let json = try await raw("""
            { repository(owner: "\(parts[0])", name: "\(parts[1])") {
                pullRequest(number: \(pr)) {
                  baseRefOid
                  headRefOid
                  files(first: 100\(after)) {
                    pageInfo { hasNextPage endCursor }
                    nodes { path additions deletions }
                  }
                }
            } }
            """)

            let data = json["data"] as? [String: Any]
            let repository = data?["repository"] as? [String: Any]
            let pull = repository?["pullRequest"] as? [String: Any]
            base = (pull?["baseRefOid"] as? String) ?? base
            head = (pull?["headRefOid"] as? String) ?? head

            let connection = pull?["files"] as? [String: Any]
            for n in connection?["nodes"] as? [[String: Any]] ?? [] {
                guard let path = n["path"] as? String else { continue }
                files.append(ChangedFile(
                    path: path,
                    additions: (n["additions"] as? Int) ?? 0,
                    deletions: (n["deletions"] as? Int) ?? 0
                ))
            }

            let page = connection?["pageInfo"] as? [String: Any]
            guard (page?["hasNextPage"] as? Bool) == true,
                  let next = page?["endCursor"] as? String else { break }
            cursor = next
        }
        return PRFiles(number: pr, base: base, head: head, files: files)
    }
}

enum Domains {
    private static let containers: Set<String> = [
        "src", "lib", "libs", "app", "internal", "pkg", "modules", "features",
        "domains", "domain", "source", "server", "client",
    ]
    private static let workspaces: Set<String> = ["apps", "packages", "services", "crates", "plugins", "Sources"]

    static func locate(_ path: String) -> (domain: String, module: String) {
        let dirs = path.split(separator: "/").dropLast().map(String.init)
        guard !dirs.isEmpty else { return ("root", "root") }

        var i = 0
        while i < dirs.count {
            let s = dirs[i]
            if workspaces.contains(s), i + 1 < dirs.count {
                i += 2
                continue
            }
            if containers.contains(s) {
                i += 1
                continue
            }
            break
        }

        if i >= dirs.count {
            let all = dirs.joined(separator: "/")
            return (all, all)
        }
        let domain = dirs[...i].joined(separator: "/")
        let module = i + 1 < dirs.count ? dirs[...(i + 1)].joined(separator: "/") : domain
        return (domain, module)
    }

    static func name(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}

enum MapScan {
    static let maxDomains = 7
    static let maxModules = 10

    private struct Tally {
        var additions = 0
        var deletions = 0
        var files = 0
        var prs = Set<Int>()
        var top: ChangedFile?

        var churn: Int { additions + deletions }

        mutating func add(_ f: ChangedFile, pr: Int) {
            additions += f.additions
            deletions += f.deletions
            files += 1
            prs.insert(pr)
            if Self.rank(f) > (top.map(Self.rank) ?? (-1, -1)) { top = f }
        }

        private static func rank(_ f: ChangedFile) -> (Int, Int) {
            (Dependents.isTest(f.path) ? 0 : 1, f.additions + f.deletions)
        }
    }

    static func build(repo: String, prs: [PRFiles]) -> PRMap {
        var modules: [String: Tally] = [:]
        var domains: [String: Tally] = [:]
        var owner: [String: String] = [:]
        var seen = Set<String>()
        var size = MapSize()

        for pr in prs {
            for f in pr.files {
                let (d, m) = Domains.locate(f.path)
                owner[m] = d
                modules[m, default: Tally()].add(f, pr: pr.number)
                domains[d, default: Tally()].add(f, pr: pr.number)
                seen.insert(f.path)
                size.additions += f.additions
                size.deletions += f.deletions
            }
        }
        size.files = seen.count
        size.domains = domains.count
        size.modules = modules.count
        size.prs = max(prs.count, 1)

        let keptDomains = domains
            .sorted { $0.value.churn > $1.value.churn }
            .prefix(maxDomains)
            .map(\.key)
        let keptDomainSet = Set(keptDomains)

        let keptModules = modules
            .filter { keptDomainSet.contains(owner[$0.key] ?? "") }
            .sorted { $0.value.churn > $1.value.churn }
            .prefix(maxModules)
            .map(\.key)
        let keptModuleSet = Set(keptModules)

        var nodes: [MapNode] = []
        var edges: [MapEdge] = []

        for d in keptDomains {
            guard let t = domains[d] else { continue }
            let drawn = keptModules.filter { owner[$0] == d }.count
            let total = modules.keys.filter { owner[$0] == d }.count
            let more = total - drawn
            nodes.append(MapNode(
                id: "d:\(d)", kind: .domain,
                title: Domains.name(d), subtitle: d,
                detail: "\(t.files) file\(t.files == 1 ? "" : "s") · \(total) module\(total == 1 ? "" : "s")"
                    + (more > 0 ? " · \(more) not drawn" : ""),
                path: d == "root" ? nil : d, line: nil, isDirectory: true,
                additions: t.additions, deletions: t.deletions, files: t.files,
                prs: t.prs.sorted()
            ))
        }

        for m in keptModules {
            guard let t = modules[m], let d = owner[m] else { continue }
            let top = t.top.map { Domains.name($0.path) } ?? ""
            nodes.append(MapNode(
                id: "m:\(m)", kind: .changed,
                title: m == d ? "\(Domains.name(m)) · top level" : Domains.name(m),
                subtitle: m,
                detail: "\(t.files) file\(t.files == 1 ? "" : "s")" + (top.isEmpty ? "" : " · most in \(top)"),
                path: t.top?.path, line: nil, isDirectory: false,
                additions: t.additions, deletions: t.deletions, files: t.files,
                prs: t.prs.sorted()
            ))
            edges.append(MapEdge(from: "d:\(d)", to: "m:\(m)", kind: .contains, label: nil))
        }

        return PRMap(
            repo: repo,
            base: prs.first?.base ?? "",
            head: prs.last?.head ?? "",
            stack: prs.map(\.number),
            intent: "",
            deltas: [],
            nodes: nodes,
            edges: edges,
            size: size,
            hidden: modules.count - keptModuleSet.count,
            enriched: false
        )
    }
}

struct MapAnswer: Decodable, Sendable {
    struct Domain: Decodable, Sendable {
        let id: String
        let summary: String
    }
    struct Edge: Decodable, Sendable {
        let from: String
        let to: String
        let label: String?
    }
    struct Affected: Decodable, Sendable {
        let name: String
        let path: String
        let line: Int?
        let from: String?
        let why: String
    }
    struct Context: Decodable, Sendable {
        let title: String
        let why: String
        let location: String?
        let about: String?
    }

    let intent: String
    let deltas: [String]?
    let domains: [Domain]?
    let edges: [Edge]?
    let affected: [Affected]?
    let context: [Context]?

    static func parse(_ text: String) -> MapAnswer? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              let body = String(text[start...end]).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MapAnswer.self, from: body)
    }
}

extension PRMap {
    func merged(_ a: MapAnswer, exists: (String) -> Bool) -> PRMap {
        var m = self
        m.intent = a.intent
        m.deltas = Array((a.deltas ?? []).prefix(3))

        let summaries = Dictionary((a.domains ?? []).map { ($0.id, $0.summary) }, uniquingKeysWith: { f, _ in f })
        m.nodes = m.nodes.map { n in
            guard n.kind == .domain, let s = summaries[n.id], !s.isEmpty else { return n }
            var copy = n
            copy.detail = s
            return copy
        }

        var known = Set(m.nodes.map(\.id))
        let changedIds = m.nodes(.changed).map(\.id)

        var relates: [MapEdge] = []
        var pairs = Set<String>()
        for e in a.edges ?? [] where e.from != e.to && known.contains(e.from) && known.contains(e.to) {
            guard pairs.insert("\(e.from)>\(e.to)").inserted else { continue }
            relates.append(MapEdge(from: e.from, to: e.to, kind: .relates, label: e.label))
            if relates.count == 12 { break }
        }
        m.edges += relates

        for x in (a.affected ?? []).prefix(6) {
            let clean = Self.clean(x.path)
            let id = "a:\(clean)"
            guard !known.contains(id), !clean.isEmpty else { continue }
            let (d, _) = Domains.locate(clean)
            let real = exists(clean)
            m.nodes.append(MapNode(
                id: id, kind: .affected,
                title: x.name.isEmpty ? Domains.name(clean) : x.name,
                subtitle: clean,
                detail: x.why,
                path: real ? clean : nil, line: x.line, isDirectory: false,
                prs: []
            ))
            known.insert(id)
            let source = x.from.flatMap { changedIds.contains($0) ? $0 : nil }
                ?? changedIds.first { $0.hasPrefix("m:\(d)") }
            if let s = source {
                m.edges.append(MapEdge(from: s, to: id, kind: .feels, label: nil))
            }
        }

        for (i, c) in (a.context ?? []).prefix(4).enumerated() {
            let id = "c:\(i)"
            let (location, line) = Self.split(c.location ?? "")
            let real = !location.isEmpty && exists(location)
            m.nodes.append(MapNode(
                id: id, kind: .context,
                title: c.title,
                subtitle: location,
                detail: c.why,
                path: real ? location : nil, line: line, isDirectory: false,
                prs: []
            ))
            if let about = c.about, known.contains(about) {
                m.edges.append(MapEdge(from: about, to: id, kind: .explains, label: nil))
            }
        }

        m.enriched = true
        return m
    }

    private static func clean(_ path: String) -> String {
        var p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while p.hasPrefix("./") { p.removeFirst(2) }
        while p.hasPrefix("/") { p.removeFirst() }
        return split(p).path
    }

    private static func split(_ location: String) -> (path: String, line: Int?) {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = trimmed.lastIndex(of: ":"),
              let n = Int(trimmed[trimmed.index(after: colon)...]) else { return (trimmed, nil) }
        return (String(trimmed[..<colon]), n)
    }
}
