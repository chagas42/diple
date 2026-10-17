import Foundation

struct ResolveRun: Sendable, Equatable {
    var steps: [String] = []
    var outcome: ConflictResolver.Outcome?
    var folder: URL?

    var running: Bool { outcome == nil }
}

extension AppModel {
    func resolveRun(_ key: String) -> ResolveRun? { resolves[key] }

    func canResolveConflicts(_ pr: PR) -> Bool {
        pr.conflicts && (pr.isMine || pr.canPush == true)
    }

    func resolveConflicts(_ pr: PR) async {
        guard resolves[pr.key]?.running != true else { return }
        resolves[pr.key] = ResolveRun()

        func say(_ line: String) { resolves[pr.key]?.steps.append(line) }
        func finish(_ outcome: ConflictResolver.Outcome) { resolves[pr.key]?.outcome = outcome }

        if queries.answersLocally {
            for line in ["fetching \(pr.baseRef)", "running npm test before the merge", "merging \(pr.baseRef)",
                         "Claude is resolving 1 file (try 1)", "running npm test after the merge",
                         "committing the merge", "pushing to \(pr.headRef)"] {
                say(line)
                try? await Task.sleep(for: .milliseconds(450))
            }
            finish(.pushed(commit: "4f1c2a9e", report: .init(
                files: ["src/orders/orders-module.ts"],
                summary: "src/orders/orders-module.ts: kept the overage guard from the PR and the provider lookup from main.",
                checks: "npm test passed"
            )))
            return
        }

        guard let origin = settings.localPath(pr.repo) else {
            finish(.failed(step: "clone", reason: "Diple needs a local clone of \(pr.repo). Point at it in Settings → Repositories."))
            return
        }
        let lock = ResolveLock.at(Self.resolveFolder(pr))
        guard lock.acquire() else {
            finish(.failed(step: "lock", reason: "Already resolving \(pr.key) on this Mac, in another Diple."))
            return
        }
        defer { lock.release() }
        say("preparing a worktree for \(pr.key)")
        let folder: URL
        do {
            folder = try await Self.resolveWorktree(origin: origin, pr: pr)
        } catch {
            finish(.failed(step: "worktree", reason: error.localizedDescription))
            return
        }
        resolves[pr.key]?.folder = folder

        let originURL = (try? await Worktree.git(["remote", "get-url", "origin"], in: origin))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let job = ConflictResolver.Job(
            folder: folder, title: pr.title, baseRef: pr.baseRef, headRef: pr.headRef,
            pushURL: ConflictResolver.pushURL(origin: originURL, repo: pr.repo, headRepo: pr.headRepo),
            pushes: settings.pushesResolvedConflicts && pr.isMine
        )
        let resolver = ConflictResolver(claude: ConflictResolver.liveClaude(model: settings.aiModel))
        let key = pr.key
        let outcome = await resolver.resolve(job) { [weak self] line in
            await MainActor.run { self?.resolves[key]?.steps.append(line) }
        }
        finish(outcome)

        if outcome.isDone {
            _ = try? await Worktree.git(["worktree", "remove", "--force", folder.path], in: origin)
            resolves[pr.key]?.folder = nil
            await reread(pr)
        }
    }

    func pushResolved(_ pr: PR) async {
        guard let run = resolves[pr.key], case .committed(let commit, let report) = run.outcome,
              let folder = run.folder, let origin = settings.localPath(pr.repo) else { return }
        let originURL = (try? await Worktree.git(["remote", "get-url", "origin"], in: origin))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let url = ConflictResolver.pushURL(origin: originURL, repo: pr.repo, headRepo: pr.headRepo)
        resolves[pr.key]?.steps.append("pushing to \(pr.headRef)")
        let push = await Shell.live.git(["push", url, "HEAD:refs/heads/\(pr.headRef)"], in: folder)
        guard push.ok else {
            resolves[pr.key]?.outcome = .failed(step: "push", reason: ConflictResolver.tail(push.output))
            return
        }
        resolves[pr.key]?.outcome = .pushed(commit: commit, report: report)
        _ = try? await Worktree.git(["worktree", "remove", "--force", folder.path], in: origin)
        resolves[pr.key]?.folder = nil
        await reread(pr)
    }

    func dismissResolve(_ pr: PR) { resolves[pr.key] = nil }

    static func resolveFolder(_ pr: PR) -> URL {
        Worktree.root.appendingPathComponent("\(pr.repo.replacingOccurrences(of: "/", with: "-"))-\(pr.number)-resolve")
    }

    static func resolveWorktree(origin: URL, pr: PR) async throws -> URL {
        let review = try await Worktree.prepare(origin: origin, repo: pr.repo, pr: pr.number, base: pr.baseRef, head: pr.head ?? "")
        let target = review.deletingLastPathComponent().appendingPathComponent(review.lastPathComponent + "-resolve")
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try? await Worktree.git(["worktree", "remove", "--force", target.path], in: origin)
        }
        try await Worktree.git(["worktree", "add", "--detach", target.path, "refs/diple/pr-\(pr.number)"], in: origin)
        return target
    }
}

extension ConflictResolver.Outcome {
    var isDone: Bool {
        switch self {
        case .pushed, .alreadyResolved: true
        case .committed, .failed: false
        }
    }
}
