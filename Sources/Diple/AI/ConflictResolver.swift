import Foundation

struct Shell: Sendable {
    struct Result: Sendable, Equatable {
        let status: Int32
        let output: String
        var ok: Bool { status == 0 }
    }

    var run: @Sendable (_ executable: String, _ arguments: [String], _ folder: URL, _ timeout: TimeInterval) async -> Result

    static let live = Shell { executable, arguments, folder, timeout in
        await Task.detached(priority: .utility) {
            guard let p = try? Tools.process(executable, arguments) else {
                return Result(status: 127, output: "\(executable) was not found")
            }
            p.currentDirectoryURL = folder
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            p.standardInput = FileHandle.nullDevice
            let collected = Collected()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { collected.append(data) }
            }
            do { try p.run() } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                return Result(status: 126, output: error.localizedDescription)
            }
            let deadline = Date().addingTimeInterval(timeout)
            while p.isRunning, Date() < deadline { usleep(200_000) }
            var timedOut = false
            if p.isRunning { timedOut = true; p.terminate() }
            p.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
            collected.append(pipe.fileHandleForReading.readDataToEndOfFile())
            let text = collected.text + (timedOut ? "\n[stopped after \(Int(timeout))s]" : "")
            return Result(status: timedOut ? 124 : p.terminationStatus, output: text)
        }.value
    }

    func git(_ arguments: [String], in folder: URL) async -> Result {
        await run("git", arguments, folder, 300)
    }
}

private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ d: Data) { lock.lock(); data.append(d); lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
}

struct ConflictResolver: Sendable {
    struct Job: Sendable {
        let folder: URL
        let title: String
        let baseRef: String
        let headRef: String
        let pushURL: String
        let pushes: Bool
    }

    enum Outcome: Sendable, Equatable {
        case pushed(commit: String, report: Report)
        case committed(commit: String, report: Report)
        case failed(step: String, reason: String)
    }

    struct Report: Sendable, Equatable {
        var files: [String] = []
        var summary = ""
        var checks = "no test command found"
    }

    static let attempts = 3
    static let testTimeout: TimeInterval = 15 * 60

    var shell: Shell = .live
    var claude: @Sendable (_ prompt: String, _ folder: URL) async -> Shell.Result

    func resolve(_ job: Job, progress: @Sendable (String) async -> Void) async -> Outcome {
        let folder = job.folder
        var report = Report()

        await progress("fetching \(job.baseRef)")
        guard await shell.git(["fetch", "origin", job.baseRef], in: folder).ok else {
            return .failed(step: "fetch", reason: "could not fetch \(job.baseRef) from origin")
        }

        let command = TestCommand.detect(in: folder)
        var baselineGreen = false
        if let command {
            await progress("running \(command.label) before the merge")
            baselineGreen = await runChecks(command, in: folder).ok
            if !baselineGreen { report.checks = "\(command.label) already failed before the merge, so it was not used" }
        }

        await progress("merging \(job.baseRef)")
        let merge = await shell.git(["merge", "--no-edit", "--no-ff", "FETCH_HEAD"], in: folder)
        let conflicted = await conflictedFiles(in: folder)
        if !merge.ok, conflicted.isEmpty {
            return .failed(step: "merge", reason: Self.tail(merge.output))
        }
        report.files = conflicted

        if !conflicted.isEmpty {
            var remaining = conflicted
            for attempt in 1...Self.attempts where !remaining.isEmpty {
                await progress("Claude is resolving \(remaining.count) file\(remaining.count == 1 ? "" : "s") (try \(attempt))")
                let answer = await claude(Self.resolvePrompt(job: job, files: remaining), folder)
                if !answer.output.isEmpty { report.summary = Self.tail(answer.output, lines: 40) }
                remaining = Self.withMarkers(remaining, in: folder)
            }
            guard remaining.isEmpty else {
                return .failed(step: "resolve", reason: "conflict markers are still in \(remaining.joined(separator: ", "))")
            }
            _ = await shell.git(["add", "--"] + conflicted, in: folder)
        }

        if let command, baselineGreen {
            var result = await runChecks(command, in: folder)
            var attempt = 1
            while !result.ok, attempt <= Self.attempts {
                await progress("\(command.label) failed after the merge, Claude is fixing it (try \(attempt))")
                _ = await claude(Self.fixPrompt(job: job, command: command, output: result.output), folder)
                _ = await shell.git(["add", "-u"], in: folder)
                result = await runChecks(command, in: folder)
                attempt += 1
            }
            guard result.ok else {
                return .failed(step: "tests", reason: "\(command.label) still fails:\n" + Self.tail(result.output))
            }
            report.checks = "\(command.label) passed"
        }

        await progress("committing the merge")
        _ = await shell.git(["add", "-u"], in: folder)
        let staged = await shell.git(["diff", "--cached", "--name-only"], in: folder)
        let inMerge = await shell.git(["rev-parse", "-q", "--verify", "MERGE_HEAD"], in: folder)
        if inMerge.ok || !staged.output.isEmpty {
            let message = inMerge.ok ? ["--no-edit"] : ["-m", "fix: keep the checks passing after merging \(job.baseRef)"]
            let commit = await shell.git(["commit", "--no-verify"] + message, in: folder)
            guard commit.ok else { return .failed(step: "commit", reason: Self.tail(commit.output)) }
        }
        let sha = (await shell.git(["rev-parse", "HEAD"], in: folder)).output
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard job.pushes else { return .committed(commit: sha, report: report) }
        await progress("pushing to \(job.headRef)")
        let push = await shell.git(["push", job.pushURL, "HEAD:refs/heads/\(job.headRef)"], in: folder)
        guard push.ok else { return .failed(step: "push", reason: Self.tail(push.output)) }
        return .pushed(commit: sha, report: report)
    }

    private func runChecks(_ command: TestCommand, in folder: URL) async -> Shell.Result {
        for step in command.steps {
            let r = await shell.run(step.executable, step.arguments, folder, Self.testTimeout)
            if !r.ok { return r }
        }
        return Shell.Result(status: 0, output: "")
    }

    private func conflictedFiles(in folder: URL) async -> [String] {
        (await shell.git(["diff", "--name-only", "--diff-filter=U"], in: folder)).output
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    static func withMarkers(_ files: [String], in folder: URL) -> [String] {
        files.filter { file in
            guard let text = try? String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8) else { return false }
            return hasMarkers(text)
        }
    }

    static func hasMarkers(_ text: String) -> Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false).contains { line in
            line.hasPrefix("<<<<<<< ") || line.hasPrefix(">>>>>>> ") || line == "======="
        }
    }

    static func tail(_ text: String, lines: Int = 30) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func resolvePrompt(job: Job, files: [String]) -> String {
        """
        You are in a git worktree of the pull request "\(job.title)" (branch \(job.headRef)). \
        `git merge` of \(job.baseRef) into it stopped with conflicts in these files:

        \(files.map { "- \($0)" }.joined(separator: "\n"))

        Resolve every conflict so the result keeps what both sides meant: the pull request's change \
        and what \(job.baseRef) changed since. Read the surrounding code and `git log` on each side \
        when the intent is not obvious. Remove every conflict marker. Change only what the conflicts \
        need. Do not commit, push, merge, rebase or reset: Diple does that after you.

        When you are done, end with one line per file: `<path>: <what you kept from each side>`.
        """
    }

    static func fixPrompt(job: Job, command: TestCommand, output: String) -> String {
        """
        You are in a git worktree of the pull request "\(job.title)", right after merging \(job.baseRef) \
        into it. `\(command.label)` passed before the merge and fails now:

        ```
        \(tail(output, lines: 80))
        ```

        Fix the code so it passes, keeping the pull request's intent and what \(job.baseRef) changed. \
        Fix the cause in the merged code; do not delete or weaken tests. Do not commit, push, merge, \
        rebase or reset.
        """
    }

    static let allowedTools = [
        "Read", "Edit", "Write", "MultiEdit", "Grep", "Glob",
        "Bash(git diff:*)", "Bash(git status:*)", "Bash(git log:*)", "Bash(git show:*)",
    ].joined(separator: " ")

    static let deniedTools = [
        "Bash(git push:*)", "Bash(git commit:*)", "Bash(git merge:*)", "Bash(git rebase:*)",
        "Bash(git reset:*)", "Bash(git checkout:*)", "Bash(gh:*)", "Bash(curl:*)", "WebFetch", "WebSearch",
    ].joined(separator: " ")

    static func liveClaude(model: String, shell: Shell = .live) -> @Sendable (String, URL) async -> Shell.Result {
        { prompt, folder in
            await shell.run("claude", [
                "-p", prompt,
                "--permission-mode", "dontAsk",
                "--allowed-tools", allowedTools,
                "--disallowed-tools", deniedTools,
                "--strict-mcp-config",
                "--model", model,
            ], folder, 20 * 60)
        }
    }

    static func pushURL(origin: String, repo: String, headRepo: String?) -> String {
        guard let headRepo, headRepo.lowercased() != repo.lowercased(),
              let range = origin.range(of: repo, options: .caseInsensitive) else { return origin }
        return origin.replacingCharacters(in: range, with: headRepo)
    }
}

struct TestCommand: Sendable, Equatable {
    struct Step: Sendable, Equatable {
        let executable: String
        let arguments: [String]
    }

    let label: String
    let steps: [Step]

    static func detect(in folder: URL) -> TestCommand? {
        let fm = FileManager.default
        func has(_ name: String) -> Bool { fm.fileExists(atPath: folder.appendingPathComponent(name).path) }
        func read(_ name: String) -> String? { try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) }

        if has("Package.swift") {
            return TestCommand(label: "swift test", steps: [Step(executable: "swift", arguments: ["test"])])
        }
        if let pkg = read("package.json"),
           let json = try? JSONSerialization.jsonObject(with: Data(pkg.utf8)) as? [String: Any],
           let test = (json["scripts"] as? [String: Any])?["test"] as? String,
           !test.contains("no test specified") {
            let tool = has("pnpm-lock.yaml") ? "pnpm" : has("yarn.lock") ? "yarn" : has("bun.lockb") || has("bun.lock") ? "bun" : "npm"
            var steps: [Step] = []
            if !has("node_modules") {
                let install: [String] = switch tool {
                case "pnpm": ["install", "--frozen-lockfile"]
                case "yarn": ["install", "--frozen-lockfile"]
                case "bun":  ["install", "--frozen-lockfile"]
                default:     ["ci"]
                }
                steps.append(Step(executable: tool, arguments: install))
            }
            steps.append(Step(executable: tool, arguments: ["test"]))
            return TestCommand(label: "\(tool) test", steps: steps)
        }
        if has("Cargo.toml") {
            return TestCommand(label: "cargo test", steps: [Step(executable: "cargo", arguments: ["test"])])
        }
        if has("go.mod") {
            return TestCommand(label: "go test", steps: [Step(executable: "go", arguments: ["test", "./..."])])
        }
        if let make = read("Makefile"), make.split(separator: "\n").contains(where: { $0.hasPrefix("test:") }) {
            return TestCommand(label: "make test", steps: [Step(executable: "make", arguments: ["test"])])
        }
        return nil
    }
}
