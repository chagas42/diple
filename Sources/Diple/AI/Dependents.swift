import Foundation

struct Candidate: Sendable, Equatable {
    let path: String
    let mentions: [String]
    let from: String?
}

enum Dependents {
    private static let testMarkers = [".spec.", ".test.", "_test.", "Tests/", "/test/", "/tests/", "__tests__/"]
    private static let generic: Set<String> = [
        "index", "types", "utils", "constants", "helpers", "mod", "main", "init", "__init__",
    ]

    static func isTest(_ path: String) -> Bool {
        path.hasPrefix("test/") || path.hasPrefix("tests/") || testMarkers.contains { path.contains($0) }
    }

    static func find(changed: Set<String>, modules: Set<String>, in folder: URL, limit: Int = 15) async -> [Candidate] {
        let sources = changed.filter { !isTest($0) }.sorted().prefix(40)

        let found = await withTaskGroup(of: (String, [String]).self) { group in
            for file in sources {
                group.addTask {
                    let url = URL(fileURLWithPath: file)
                    let stem = url.lastPathComponent.split(separator: ".").first.map(String.init) ?? ""
                    let parent = url.deletingLastPathComponent().lastPathComponent
                    var needles = ["\(parent)/\(stem)"]
                    if !generic.contains(stem), !stem.isEmpty { needles.append(stem) }

                    for needle in needles {
                        let out = (try? await Worktree.git(["grep", "-l", "-F", needle, "--", "."], in: folder)) ?? ""
                        let hits = out.split(separator: "\n").map(String.init)
                            .filter { !changed.contains($0) && !isTest($0) }
                        if !hits.isEmpty { return (file, hits) }
                    }
                    return (file, [])
                }
            }
            var all: [(String, [String])] = []
            for await r in group { all.append(r) }
            return all
        }

        var mentions: [String: Set<String>] = [:]
        var score: [String: Double] = [:]
        var from: [String: String] = [:]
        for (file, hits) in found where !hits.isEmpty {
            let weight = 1 / log2(2 + Double(hits.count))
            let module = "m:\(Domains.locate(file).module)"
            for h in hits {
                mentions[h, default: []].insert(URL(fileURLWithPath: file).lastPathComponent)
                score[h, default: 0] += weight
                if from[h] == nil, modules.contains(module) { from[h] = module }
            }
        }

        return score
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map { Candidate(path: $0.key, mentions: (mentions[$0.key] ?? []).sorted(), from: from[$0.key]) }
    }
}
