import Foundation

actor GitGate {
    static let shared = GitGate()

    private var held: Set<String> = []
    private var waiting: [String: [CheckedContinuation<Void, Never>]] = [:]

    func lock(_ key: String) async {
        if held.contains(key) {
            await withCheckedContinuation { c in
                waiting[key, default: []].append(c)
            }
        } else {
            held.insert(key)
        }
    }

    func unlock(_ key: String) {
        if var queue = waiting[key], !queue.isEmpty {
            let next = queue.removeFirst()
            waiting[key] = queue.isEmpty ? nil : queue
            next.resume()
        } else {
            held.remove(key)
        }
    }
}

enum Worktree {
    struct WorktreeError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".diple/worktrees", isDirectory: true)
    }

    static func localPath(_ repo: String, configured: [String: String]) -> URL? {
        if let p = configured[repo] {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        }
        let name = repo.split(separator: "/").last.map(String.init) ?? repo
        let casa = FileManager.default.homeDirectoryForCurrentUser
        let candidatos = ["@studies", "@work", "dev", "work", "Developer", "code", "src"]
            .map { casa.appendingPathComponent($0).appendingPathComponent(name) }
            + [casa.appendingPathComponent(name)]

        return candidatos.first { url in
            var folder: ObjCBool = false
            let existe = FileManager.default.fileExists(
                atPath: url.appendingPathComponent(".git").path, isDirectory: &folder
            )
            return existe
        }
    }

    static func existing(repo: String, pr: Int) -> URL? {
        let target = root.appendingPathComponent("\(repo.replacingOccurrences(of: "/", with: "-"))-\(pr)")
        return FileManager.default.fileExists(atPath: target.path) ? target : nil
    }

    @discardableResult
    static func prepare(origin: URL, repo: String, pr: Int, base: String = "", head: String = "") async throws -> URL {
        await GitGate.shared.lock(origin.path)
        defer { Task { await GitGate.shared.unlock(origin.path) } }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let name = "\(repo.replacingOccurrences(of: "/", with: "-"))-\(pr)"
        let target = root.appendingPathComponent(name)
        let ref = "refs/diple/pr-\(pr)"

        if FileManager.default.fileExists(atPath: target.path) {
            let current = try? await git(["rev-parse", "HEAD"], in: target)
            let wanted = head.isEmpty ? try? await git(["rev-parse", ref], in: origin) : head
            let same = current?.trimmingCharacters(in: .whitespacesAndNewlines)
                == wanted?.trimmingCharacters(in: .whitespacesAndNewlines)
            if same, current?.isEmpty == false { return target }
            _ = try? await git(["worktree", "remove", "--force", target.path], in: origin)
        }
        if await !hasFetched(origin: origin, pr: pr, base: base, head: head) {
            try await fetchPR(origin: origin, pr: pr, base: base)
        }
        _ = try await git(["worktree", "add", "--detach", target.path, ref], in: origin)
        return target
    }

    static func prefetchPR(origin: URL, pr: Int, base: String) async throws {
        await GitGate.shared.lock(origin.path)
        defer { Task { await GitGate.shared.unlock(origin.path) } }
        try await fetchPR(origin: origin, pr: pr, base: base)
    }

    static func fetchPR(origin: URL, pr: Int, base: String) async throws {
        var refs = ["+refs/pull/\(pr)/head:refs/diple/pr-\(pr)"]
        if !base.isEmpty { refs.append(base) }
        _ = try await git(["fetch", "origin"] + refs + ["--force"], in: origin)
    }

    static func hasFetched(origin: URL, pr: Int, base: String, head: String) async -> Bool {
        guard !head.isEmpty else { return false }
        let local = try? await git(["rev-parse", "refs/diple/pr-\(pr)"], in: origin)
        guard local?.trimmingCharacters(in: .whitespacesAndNewlines) == head else { return false }
        guard !base.isEmpty else { return true }
        return (try? await git(["cat-file", "-e", "\(base)^{commit}"], in: origin)) != nil
    }

    static func pruneStale() async {
        let fm = FileManager.default
        guard let pastas = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        for p in pastas {
            let date = (try? p.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast

            guard Date().timeIntervalSince(date) > 3600 else { continue }

            _ = try? await git(["worktree", "remove", "--force", p.path], in: p)
            try? fm.removeItem(at: p)
        }
    }

    static func discard(origin: URL, target: URL) async {
        _ = try? await git(["worktree", "remove", "--force", target.path], in: origin)
    }

    @discardableResult
    static func git(_ args: [String], in folder: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            let p = try Tools.process("git", args)
            p.currentDirectoryURL = folder
            let out = Pipe(), error = Pipe()
            p.standardOutput = out
            p.standardError = error
            try p.run()
            let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let falha = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                throw WorktreeError(message: "git \(args.first ?? ""): \(falha.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            return text
        }.value
    }
}
