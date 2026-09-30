import Foundation

enum MapStep: Sendable {
    case session(String)
    case tool(String)
    case thinking
    case done(MapAnswer?)
    case failed(String)
}

enum MapSkill {
    struct Resolved: Sendable, Equatable {
        let command: String
        let pluginDir: URL?
        let source: String
    }

    static let personal = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/skills/diple-map/SKILL.md")

    static func resolve() -> Resolved {
        let fm = FileManager.default
        if fm.fileExists(atPath: personal.path) {
            return Resolved(command: "/diple-map", pluginDir: nil, source: "~/.claude/skills/diple-map")
        }
        for dir in candidates()
        where fm.fileExists(atPath: dir.appendingPathComponent(".claude-plugin/plugin.json").path) {
            return Resolved(command: "/diple:map", pluginDir: dir, source: "bundled with Diple")
        }
        return Resolved(command: "", pluginDir: nil, source: "inline prompt, plugin not found")
    }

    private static func candidates() -> [URL] {
        var list: [URL] = []
        if let r = Bundle.main.resourceURL {
            list.append(r.appendingPathComponent("plugin", isDirectory: true))
        }
        if let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            list.append(
                exe.deletingLastPathComponent()
                    .appendingPathComponent("../../Resources/plugin", isDirectory: true)
                    .standardizedFileURL
            )
        }
        return list
    }
}

private final class ProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}

actor Overdue {
    private(set) var value = false
    func mark() { value = true }
}

struct MapBuilder: Sendable {
    static let budgetSeconds: Double = 480

    private static let effort = "low"

    private static let allowedTools = [
        "Read", "Grep", "Glob", "Skill",
        "Bash(git diff:*)", "Bash(git log:*)", "Bash(git show:*)",
    ].joined(separator: " ")

    private static let deniedTools = [
        "Write", "Edit", "MultiEdit", "NotebookEdit",
        "Bash(gh:*)", "Bash(git push:*)", "Bash(git commit:*)",
        "Bash(curl:*)", "WebFetch", "WebSearch",
    ].joined(separator: " ")

    func enrich(
        map: PRMap, titles: [Int: String], candidates: [Candidate],
        in folder: URL, model: String, language: String
    ) -> AsyncStream<MapStep> {
        let skill = MapSkill.resolve()
        let prompt = self.prompt(map: map, titles: titles, candidates: candidates, language: language, skill: skill)

        return AsyncStream { cont in
            let task = Task {
                var args = [
                    "-p", prompt,
                    "--output-format", "stream-json",
                    "--verbose",
                    "--permission-mode", "dontAsk",
                    "--allowed-tools", Self.allowedTools,
                    "--disallowed-tools", Self.deniedTools,
                    "--model", model,
                    "--effort", Self.effort,
                    "--strict-mcp-config",
                    "--max-turns", "30",
                ]
                if let dir = skill.pluginDir { args += ["--plugin-dir", dir.path] }

                guard let p = try? Tools.process("claude", args) else {
                    cont.yield(.failed(MissingTool(name: "claude").localizedDescription))
                    cont.finish()
                    return
                }
                p.currentDirectoryURL = folder
                let out = Pipe()
                p.standardOutput = out
                p.standardError = FileHandle.nullDevice

                do { try p.run() } catch {
                    cont.yield(.failed("could not run claude: \(error.localizedDescription)"))
                    cont.finish()
                    return
                }

                cont.yield(.session("skill: \(skill.source)"))

                let box = ProcessBox(p)
                var buffer = Data()
                var result: String?
                let overdue = Overdue()

                let watchdog = Task { [box] in
                    try? await Task.sleep(for: .seconds(Self.budgetSeconds))
                    guard !Task.isCancelled else { return }
                    await overdue.mark()
                    box.process.terminate()
                }
                defer { watchdog.cancel() }
                await withTaskCancellationHandler {
                    for await chunk in out.fileHandleForReading.bytes.chunks() {
                        buffer.append(chunk)
                        while let newline = buffer.firstIndex(of: 0x0A) {
                            let line = buffer[..<newline]
                            buffer = buffer[buffer.index(after: newline)...]
                            if let step = Self.parse(line, result: &result) { cont.yield(step) }
                        }
                    }
                } onCancel: {
                    box.process.terminate()
                }
                p.waitUntilExit()

                guard let text = result else {
                    let stopped = await overdue.value
                    cont.yield(.failed(stopped
                        ? "the session ran past \(Int(Self.budgetSeconds / 60)) minutes and was stopped"
                        : "the session ended with no answer"))
                    cont.finish()
                    return
                }
                cont.yield(.done(MapAnswer.parse(text)))
                cont.finish()
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    private static func parse(_ line: Data, result: inout String?) -> MapStep? {
        guard !line.isEmpty,
              let o = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              let kind = o["type"] as? String else { return nil }

        switch kind {
        case "system":
            guard (o["subtype"] as? String) == "init" else { return nil }
            return .session("session ready · \((o["model"] as? String) ?? "?")")

        case "assistant":
            let parts = ((o["message"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
            for c in parts where (c["type"] as? String) == "tool_use" {
                let name = (c["name"] as? String) ?? "?"
                let input = c["input"] as? [String: Any]
                let short: String?
                if let command = input?["command"] as? String {
                    short = String(command.split(separator: "\n").first ?? "").prefix(46).description
                } else {
                    let target = (input?["file_path"] as? String)
                        ?? (input?["pattern"] as? String)
                        ?? (input?["skill"] as? String)
                    short = target.map { String(($0.split(separator: "/").last ?? "").prefix(40)) }
                }
                return .tool(short.map { "\(name) \($0)" } ?? name)
            }
            return .thinking

        case "result":
            result = o["result"] as? String
            return nil

        default:
            return nil
        }
    }

    private func prompt(
        map: PRMap, titles: [Int: String], candidates: [Candidate],
        language: String, skill: MapSkill.Resolved
    ) -> String {
        let domains: [[String: Any]] = map.nodes(.domain).map {
            ["id": $0.id, "path": $0.subtitle, "files": $0.files, "additions": $0.additions, "deletions": $0.deletions]
        }
        let modules: [[String: Any]] = map.nodes(.changed).map {
            ["id": $0.id, "path": $0.subtitle, "files": $0.files,
             "additions": $0.additions, "deletions": $0.deletions,
             "mostChangedFile": $0.path ?? "", "prs": $0.prs]
        }
        let input: [String: Any] = [
            "repo": map.repo,
            "diff": "git diff \(map.base.isEmpty ? "origin/HEAD" : map.base)...HEAD",
            "prs": map.stack.map { ["number": $0, "title": titles[$0] ?? ""] as [String: Any] },
            "candidates": candidates.map {
                ["path": $0.path, "mentions": $0.mentions, "from": $0.from as Any] as [String: Any]
            },
            "language": language,
            "size": ["files": map.size.files, "lines": map.size.lines,
                     "domains": map.size.domains, "modulesNotDrawn": map.hidden],
            "domains": domains,
            "modules": modules,
        ]
        let json = (try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys]))
            .map { String(decoding: $0, as: UTF8.self) } ?? "{}"

        let head = skill.command.isEmpty
            ? "Draw the review map of this change. Explore with Grep before Read, stay under fifteen tool calls."
            : skill.command

        return """
        \(head)

        You are in a worktree with the head of \(map.stack.count > 1 ? "a stack of \(map.stack.count) PRs" : "the PR") checked out. \
        Use exactly this diff base and no other: `\(input["diff"] as? String ?? "")`.

        Input:
        \(json)

        Answer with this JSON only, no code fence and no text around it:
        {"intent":"...","deltas":["..."],"domains":[{"id":"d:...","summary":"..."}],\
        "edges":[{"from":"m:...","to":"m:...","label":"..."}],\
        "affected":[{"name":"...","path":"...","line":1,"from":"m:...","why":"..."}],\
        "context":[{"title":"...","why":"...","location":"...","about":"m:..."}]}
        """
    }
}
