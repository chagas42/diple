import Foundation

struct Module: Identifiable, Codable, Sendable, Equatable {
    var id: String { name }
    let name: String
    let path: String

    let detail: String
    var additions: Int = 0
    var deletions: Int = 0

    var diff: String? { (additions + deletions) > 0 ? "+\(additions) −\(deletions)" : nil }
}

struct ContextNote: Identifiable, Codable, Sendable, Equatable {
    var id: String { title }
    let title: String
    let why: String
    let location: String?
}

struct PRMap: Codable, Sendable, Equatable {
    var intent: String = ""

    var deltas: [String] = []

    var changed: [Module] = []

    var affected: [Module] = []

    var context: [ContextNote] = []
}

extension GitHubClient {
    func baseAndModules(repo: String, pr: Int) async throws -> (base: String, modulos: [Module]) {
        let parts = repo.split(separator: "/")
        guard parts.count == 2 else { return ("", []) }

        let json = try await raw("""
        { repository(owner: "\(parts[0])", name: "\(parts[1])") {
            pullRequest(number: \(pr)) {
              baseRefOid
              baseRefName
              files(first: 100) { nodes { path additions deletions } }
            }
        } }
        """)

        let data = json["data"] as? [String: Any]
        let repositorio = data?["repository"] as? [String: Any]
        let pull = repositorio?["pullRequest"] as? [String: Any]
        let arquivos = pull?["files"] as? [String: Any]
        let nos = arquivos?["nodes"] as? [[String: Any]] ?? []
        let base = (pull?["baseRefOid"] as? String) ?? ""

        var porModulo: [String: (additions: Int, deletions: Int, arquivos: Int)] = [:]
        for f in nos {
            guard let path = f["path"] as? String else { continue }
            let key = Self.moduloDe(path)
            var current = porModulo[key] ?? (0, 0, 0)
            current.additions += (f["additions"] as? Int) ?? 0
            current.deletions += (f["deletions"] as? Int) ?? 0
            current.arquivos += 1
            porModulo[key] = current
        }

        let modulos = porModulo
            .map { key, v in
                Module(
                    name: key.split(separator: "/").last.map(String.init) ?? key,
                    path: key,
                    detail: "\(v.arquivos) path\(v.arquivos == 1 ? "" : "s")",
                    additions: v.additions, deletions: v.deletions
                )
            }
            .sorted { ($0.additions + $0.deletions) > ($1.additions + $1.deletions) }
            .prefix(4)
            .map { $0 }
        return (base, modulos)
    }

    private static func moduloDe(_ path: String) -> String {
        let p = path.split(separator: "/").dropLast()
        guard !p.isEmpty else { return "root" }
        return p.prefix(3).joined(separator: "/")
    }
}
