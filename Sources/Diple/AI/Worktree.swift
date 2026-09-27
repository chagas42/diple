import Foundation

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

    @discardableResult
    static func prepare(origin: URL, repo: String, pr: Int, base: String = "") async throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let name = "\(repo.replacingOccurrences(of: "/", with: "-"))-\(pr)"
        let target = root.appendingPathComponent(name)

        if FileManager.default.fileExists(atPath: target.path) {
            let current = try? await git(["rev-parse", "HEAD"], in: target)
            let alvo = try? await git(["rev-parse", "refs/diple/pr-\(pr)"], in: origin)
            let mesmo = current?.trimmingCharacters(in: .whitespacesAndNewlines)
                == alvo?.trimmingCharacters(in: .whitespacesAndNewlines)
            if mesmo, current?.isEmpty == false { return target }
            try? await git(["worktree", "remove", "--force", target.path], in: origin)
        }
        var refs = ["+refs/pull/\(pr)/head:refs/diple/pr-\(pr)"]

        if !base.isEmpty { refs.append(base) }
        _ = try await git(["fetch", "origin"] + refs + ["--force"], in: origin)
        _ = try await git(["worktree", "add", "--detach", target.path, "refs/diple/pr-\(pr)"], in: origin)
        return target
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
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["git"] + args
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
