import Foundation

enum DeepReview {
    static let skill = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/skills/diple-review/SKILL.md")

    static var available: Bool { FileManager.default.fileExists(atPath: skill.path) }
}

private final class ReviewProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}

struct Reviewer: Sendable {
    private static let allowedTools = [
        "Read", "Grep", "Glob",
        "Bash(git diff:*)", "Bash(git log:*)", "Bash(git show:*)", "Bash(git status:*)",
    ]

    private static let deepTools = ["Skill", "Agent"]

    private static let deniedTools = [
        "Write", "Edit", "MultiEdit", "NotebookEdit",
        "Bash(gh:*)", "Bash(git push:*)", "Bash(git commit:*)",
        "Bash(curl:*)", "WebFetch", "WebSearch",
    ].joined(separator: " ")

    func review(
        pr: PR, context: ReviewContext, viewer: String,
        in folder: URL, model: String, language: String
    ) -> AsyncStream<ReviewStep> {
        let deep = DeepReview.available
        let prompt = deep
            ? deepPrompt(pr: pr, context: context, viewer: viewer, language: language)
            : self.prompt(pr: pr, base: context.base, language: language)
        let allowed = (Self.allowedTools + (deep ? Self.deepTools : [])).joined(separator: " ")

        return AsyncStream { cont in
            let task = Task {
                guard let p = try? Tools.process("claude", [
                    "-p",
                    "--output-format", "stream-json",
                    "--verbose",
                    "--permission-mode", "dontAsk",
                    "--allowed-tools", allowed,
                    "--disallowed-tools", Self.deniedTools,
                    "--strict-mcp-config",
                    "--model", model,
                ]) else {
                    cont.yield(.failed(MissingTool(name: "claude").localizedDescription))
                    cont.finish()
                    return
                }
                p.currentDirectoryURL = folder

                let out = Pipe()
                let input = Pipe()
                p.standardOutput = out
                p.standardInput = input
                p.standardError = FileHandle.nullDevice

                do { try p.run() } catch {
                    cont.yield(.failed("could not run claude: \(error.localizedDescription)"))
                    cont.finish()
                    return
                }
                input.fileHandleForWriting.write(Data(prompt.utf8))
                try? input.fileHandleForWriting.close()
                if deep { cont.yield(.preparing("deep review · ~/.claude/skills/diple-review")) }

                let box = ReviewProcessBox(p)
                var buffer = Data()
                var result: String?
                await withTaskCancellationHandler {
                    for await chunk in out.fileHandleForReading.bytes.chunks() {
                        buffer.append(chunk)
                        while let newline = buffer.firstIndex(of: 0x0A) {
                            let line = buffer[..<newline]
                            buffer = buffer[buffer.index(after: newline)...]
                            if let passo = parse(line, result: &result) {
                                cont.yield(passo)
                            }
                        }
                    }
                } onCancel: {
                    box.process.terminate()
                }

                p.waitUntilExit()

                guard let text = result else {
                    cont.yield(.failed("the session ended with no answer"))
                    cont.finish()
                    return
                }
                switch Self.result(text) {
                case .success(var r):
                    r.deep = deep
                    cont.yield(.done(r))
                case .failure(let e):
                    cont.yield(.failed(e.message))
                }
                cont.finish()
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    private func parse(_ line: Data, result: inout String?) -> ReviewStep? {
        guard !line.isEmpty,
              let o = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              let kind = o["type"] as? String else { return nil }

        switch kind {
        case "system":
            guard (o["subtype"] as? String) == "init" else { return nil }
            let m = (o["model"] as? String) ?? "?"
            return .preparing("session ready · \(m)")

        case "assistant":
            let parts = ((o["message"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
            for c in parts where (c["type"] as? String) == "tool_use" {
                let name = (c["name"] as? String) ?? "?"
                let input = c["input"] as? [String: Any]
                let alvo = (input?["file_path"] as? String)
                    ?? (input?["pattern"] as? String)
                    ?? (input?["command"] as? String)
                    ?? (input?["skill"] as? String)
                    ?? (input?["description"] as? String)
                let curto = alvo.map { String($0.split(separator: "/").last ?? "").prefix(40) }
                return .tool(curto.map { "\(name) \($0)" } ?? name)
            }
            return .thinking

        case "result":
            result = o["result"] as? String
            return nil

        default:
            return nil
        }
    }

    struct Unusable: Error {
        let message: String
    }

    static func result(_ text: String) -> Result<ReviewResult, Unusable> {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              let data = String(text[start...end]).data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(Unusable(message: "the review did not answer in JSON"))
        }
        if let e = o["error"] as? String, !e.isEmpty {
            return .failure(Unusable(message: "the review stopped: \(e)"))
        }
        guard o["findings"] != nil || o["threads"] != nil else {
            return .failure(Unusable(message: "the review answered without findings or threads"))
        }

        func each<T: Decodable>(_ key: String, as _: T.Type) -> [T] {
            ((o[key] as? [Any]) ?? []).compactMap { item in
                guard let d = try? JSONSerialization.data(withJSONObject: item) else { return nil }
                return try? JSONDecoder().decode(T.self, from: d)
            }
        }

        return .success(ReviewResult(
            summary: (o["summary"] as? String) ?? "",
            findings: each("findings", as: Finding.self),
            threads: each("threads", as: ThreadVerdict.self),
            clean: (o["clean"] as? [String]) ?? [],
            dropped: (o["dropped"] as? [String]) ?? [],
            deep: false
        ))
    }

    private func deepPrompt(pr: PR, context: ReviewContext, viewer: String, language: String) -> String {
        func note(_ n: ReviewContext.Note) -> [String: Any] {
            ["id": n.id, "author": n.author, "bot": n.isBot, "at": n.at, "body": n.body]
        }
        let input: [String: Any] = [
            "repo": pr.repo,
            "language": language,
            "viewer": viewer,
            "base": context.base,
            "pr": [
                "number": pr.number, "title": pr.title, "url": pr.url.absoluteString,
                "author": context.author.isEmpty ? pr.author : context.author,
                "head": context.head, "body": context.body,
            ] as [String: Any],
            "stack": [["number": pr.number, "title": pr.title, "head": context.head] as [String: Any]],
            "threads": context.threads.map { t in
                [
                    "id": t.id, "path": t.path, "line": t.line.map { $0 as Any } ?? NSNull(),
                    "resolved": t.isResolved, "outdated": t.isOutdated,
                    "comments": t.comments.map(note),
                ] as [String: Any]
            },
            "conversation": context.conversation.map(note),
            "reviews": context.reviews.map {
                ["id": $0.id, "author": $0.author, "bot": $0.isBot, "state": $0.state, "body": $0.body] as [String: Any]
            },
        ]
        let json = (try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys]))
            .map { String(decoding: $0, as: UTF8.self) } ?? "{}"

        return """
        /diple-review

        Input:
        \(json)
        """
    }

    private func prompt(pr: PR, base: String, language: String) -> String {
        """
        You are in a worktree with PR #\(pr.number) of \(pr.repo) already checked out.

        PR title: \(pr.title)

        Review the changes in this PR. The diff is exactly \
        `git diff \(base.isEmpty ? "origin/HEAD" : base)...HEAD` — use that base and \
        no other, or you will be looking at the whole repository instead of the PR. \
        Read whatever files you need for context.

        Flag only what you could defend in a conversation: a real bug, an unhandled \
        case, a rule of this repository being broken, a test that does not \
        discriminate. Do not flag style, personal preference, or anything a linter \
        already catches. Follow this repository's conventions, including any \
        CLAUDE.md or review skill that lives here.

        If there is nothing worth raising, return an empty list. That is a \
        legitimate answer and a better one than inventing a finding.

        Write the prose fields in \(language), second person, direct, the way \
        someone comments on a colleague's PR.

        Answer with this JSON only, no code fence and no text around it:

        {"findings":[{"path":"relative/path.ts","line":214,\
        "category":"correctness|simplification|efficiency|test",\
        "verdict":"confirmed|plausible",\
        "summary":"one line saying what is wrong",\
        "detail":"two to four sentences explaining why",\
        "scenario":"concrete input that breaks it, and what happens"}]}

        Use "confirmed" only when you verified in the code that the problem exists. \
        Use "plausible" when it is a suspicion that depends on context you could \
        not check.
        """
    }
}

extension FileHandle.AsyncBytes {
    func chunks() -> AsyncStream<Data> {
        AsyncStream { cont in
            Task {
                var buffer = Data()
                do {
                    for try await b in self {
                        buffer.append(b)
                        if buffer.count >= 4096 || b == 0x0A {
                            cont.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                } catch {}
                if !buffer.isEmpty { cont.yield(buffer) }
                cont.finish()
            }
        }
    }
}
