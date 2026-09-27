import Foundation

struct MapBuilder: Sendable {
    func build(pr: PR, base: String, changed: [Module], in folder: URL, model: String, language: String) async -> PRMap? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [
            "claude", "-p", prompt(pr: pr, base: base, changed: changed, language: language),
            "--output-format", "json",
            "--permission-mode", "dontAsk",
            "--allowed-tools", "Read Grep Glob Bash(git diff:*) Bash(git log:*)",
            "--disallowed-tools", "Write Edit Bash(gh:*) Bash(git push:*) WebFetch",
            "--model", model,
        ]
        p.currentDirectoryURL = folder
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()

        do { try p.run() } catch { return nil }
        let date = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        guard let env = try? JSONSerialization.jsonObject(with: date) as? [String: Any],
              let text = env["result"] as? String else { return nil }

        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              let body = String(text[start...end]).data(using: .utf8) else { return nil }

        struct RawResponse: Decodable {
            let intent: String
            let deltas: [String]
            let affected: [Module]
            let context: [ContextNote]
        }
        guard let r = try? JSONDecoder().decode(RawResponse.self, from: body) else { return nil }

        return PRMap(
            intent: r.intent,
            deltas: Array(r.deltas.prefix(3)),
            changed: changed,
            affected: Array(r.affected.prefix(4)),
            context: Array(r.context.prefix(3))
        )
    }

    private func prompt(pr: PR, base: String, changed: [Module], language: String) -> String {
        let list = changed.map { "- \($0.path) (\($0.diff ?? ""))" }.joined(separator: "\n")
        return """
        You are in a worktree with PR #\(pr.number) of \(pr.repo) checked out.
        The diff is `git diff \(base.isEmpty ? "origin/HEAD" : base)...HEAD`.

        Title: \(pr.title)

        I already know which modules changed — they came from the diff:
        \(list)

        I need three things the diff alone does not give me.

        1. The intent: one sentence saying what this PR is trying to do, in the \
        voice of someone explaining it to a colleague. Do not describe the diff, \
        say the intent.

        2. What does NOT change but FEELS the change: at most 4 modules this PR \
        does not touch but which depend on what changed. For each one say in a few \
        words WHY it feels it. "Inherits the new throw without handling it" counts; \
        "uses that module" does not.

        3. What someone needs to KNOW to judge this PR that is not in the diff: at \
        most 3 subjects. An implicit business rule, a vendor contract, an invariant \
        the code assumes without writing down, a state machine. For each one say why \
        a review is weak without it, and where to read it if a file or doc exists.

        Explore the repository as much as you need. Write the prose in \(language). \
        Answer with this JSON only, no code fence:

        {"intent":"...",
         "deltas":["changes behaviour on 1 path","API contract intact"],
         "affected":[{"name":"worker queue","path":"src/workers",\
        "detail":"inherits the new throw without handling it"}],
         "context":[{"title":"Portability state machine",\
        "why":"the PR assumes EXPIRED goes back to PENDING, and that is written nowhere",\
        "location":"docs/portability/states.md"}]}
        """
    }
}
