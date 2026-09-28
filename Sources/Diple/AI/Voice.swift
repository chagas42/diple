import Foundation

struct Voice: Sendable {
    let samples: [String]
    let houseRules: String?

    var isEmpty: Bool { samples.isEmpty && houseRules == nil }

    static func yours(in queue: Queue, limit: Int = 24) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for pr in queue.all {
            for thread in pr.threads {
                for c in thread.comments
                where !c.isBot && c.author == queue.viewer {
                    let body = c.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard body.count > 24, body.count < 700 else { continue }
                    guard seen.insert(body).inserted else { continue }
                    out.append(body)
                }
            }
        }
        return Array(out.prefix(limit))
    }

    static func houseRules(in folder: URL) -> String? {
        let candidates = ["CLAUDE.md", ".claude/CLAUDE.md", "AGENTS.md", "CONTRIBUTING.md"]
        for name in candidates {
            let url = folder.appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if let section = toneSection(of: text) { return section }
        }
        return nil
    }

    private static func toneSection(of text: String) -> String? {
        let wanted = ["tom de voz", "tone of voice", "tone", "voz", "voice",
                      "writing", "escrita", "review", "comment"]
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var picked: [String] = []
        var capturing = false
        var depth = 0

        while !lines.isEmpty {
            let line = lines.removeFirst()
            let t = line.trimmingCharacters(in: .whitespaces).lowercased()

            if t.hasPrefix("#") {
                let level = t.prefix(while: { $0 == "#" }).count
                let heading = t.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if capturing, level <= depth { break }
                if !capturing, wanted.contains(where: { heading.contains($0) }) {
                    capturing = true
                    depth = level
                    picked.append(line)
                    continue
                }
            }
            if capturing { picked.append(line) }
        }

        let body = picked.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.count > 40 else { return nil }
        return String(body.prefix(2400))
    }

    var brief: String {
        var parts: [String] = []

        if let rules = houseRules {
            parts.append("""
            The repository states how review comments should read. These rules win over
            everything else about voice, including the samples below:

            \(rules)
            """)
        }

        if !samples.isEmpty {
            let shown = samples.prefix(14)
                .map { "- \($0.replacingOccurrences(of: "\n", with: " "))" }
                .joined(separator: "\n")
            parts.append("""
            Write every comment in the voice of the person who will post it. These are
            review comments they have written before — match their length, their
            directness, how much they explain before they point, whether they hedge,
            and the language they write in. Do not imitate the pull request author, and
            do not fall back to a neutral assistant voice.

            \(shown)
            """)
        }

        return parts.joined(separator: "\n\n")
    }
}
