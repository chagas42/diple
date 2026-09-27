import Foundation

struct Reviewer: Sendable {
    private static let allowedTools = [
        "Read", "Grep", "Glob",
        "Bash(git diff:*)", "Bash(git log:*)", "Bash(git show:*)", "Bash(git status:*)",
    ].joined(separator: " ")

    private static let deniedTools = [
        "Write", "Edit", "MultiEdit", "NotebookEdit",
        "Bash(gh:*)", "Bash(git push:*)", "Bash(git commit:*)",
        "Bash(curl:*)", "WebFetch",
    ].joined(separator: " ")

    func review(pr: PR, base: String, in folder: URL, model: String, language: String) -> AsyncStream<ReviewStep> {
        AsyncStream { cont in
            let task = Task {
                guard let p = try? Tools.process("claude", [
                    "-p", prompt(pr: pr, base: base, language: language),
                    "--output-format", "stream-json",
                    "--verbose",
                    "--permission-mode", "dontAsk",
                    "--allowed-tools", Self.allowedTools,
                    "--disallowed-tools", Self.deniedTools,
                    "--model", model,
                ]) else {
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

                var buffer = Data()
                var result: String?

                for try await chunk in out.fileHandleForReading.bytes.chunks() {
                    guard !Task.isCancelled else { break }
                    buffer.append(chunk)
                    while let newline = buffer.firstIndex(of: 0x0A) {
                        let line = buffer[..<newline]
                        buffer = buffer[buffer.index(after: newline)...]
                        if let passo = parse(line, result: &result) {
                            cont.yield(passo)
                        }
                    }
                }

                p.waitUntilExit()

                guard let text = result else {
                    cont.yield(.failed("the session ended with no answer"))
                    cont.finish()
                    return
                }
                cont.yield(.done(Self.extract(text)))
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
                let alvo = ((c["input"] as? [String: Any])?["file_path"] as? String)
                    ?? ((c["input"] as? [String: Any])?["pattern"] as? String)
                    ?? ((c["input"] as? [String: Any])?["command"] as? String)
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

    static func extract(_ text: String) -> [Finding] {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return [] }
        let body = String(text[start...end])
        struct Envelope: Decodable { let findings: [Finding] }
        guard let date = body.data(using: .utf8),
              let env = try? JSONDecoder().decode(Envelope.self, from: date) else { return [] }
        return env.findings
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
