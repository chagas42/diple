import Foundation

enum RepoScan {
    static let maxDepth = 4
    static let skipped: Set<String> = ["node_modules", ".build", "DerivedData", "Pods"]

    struct Remote: Equatable {
        let name: String
        let url: String
    }

    static func scan(_ base: URL, maxDepth: Int = maxDepth) -> [String: String] {
        var best: [String: (rank: Int, path: String)] = [:]
        visit(base.standardizedFileURL, depth: 0, maxDepth: maxDepth) { folder, depth, remotes in
            for remote in remotes {
                guard let repo = repo(fromRemote: remote.url)?.lowercased() else { continue }
                let rank = (remote.name == "origin" ? 0 : 1000) + depth
                if let current = best[repo], current.rank <= rank { continue }
                best[repo] = (rank, folder.path)
            }
        }
        return best.mapValues(\.path)
    }

    static func matched(_ repos: [String], manual: [String: String], scanned: [String: String]) -> Int {
        repos.filter { manual[$0] == nil && scanned[$0.lowercased()] != nil }.count
    }

    private static func visit(
        _ folder: URL, depth: Int, maxDepth: Int,
        found: (URL, Int, [Remote]) -> Void
    ) {
        let fm = FileManager.default
        let dotGit = folder.appendingPathComponent(".git")
        if fm.fileExists(atPath: dotGit.path) {
            if let config = configFile(dotGit), let text = try? String(contentsOf: config, encoding: .utf8) {
                found(folder, depth, remotes(config: text))
            }
            return
        }
        guard depth < maxDepth,
              let children = try? fm.contentsOfDirectory(
                  at: folder,
                  includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                  options: [.skipsHiddenFiles, .skipsPackageDescendants]
              )
        else { return }
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard !skipped.contains(child.lastPathComponent) else { continue }
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            visit(child, depth: depth + 1, maxDepth: maxDepth, found: found)
        }
    }

    static func configFile(_ dotGit: URL) -> URL? {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isFolder) else { return nil }
        if isFolder.boolValue { return dotGit.appendingPathComponent("config") }

        guard let text = try? String(contentsOf: dotGit, encoding: .utf8),
              let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") })
        else { return nil }
        let raw = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        let gitDir = URL(fileURLWithPath: raw, relativeTo: dotGit.deletingLastPathComponent()).standardizedFileURL
        let common = gitDir.appendingPathComponent("commondir")
        if let shared = try? String(contentsOf: common, encoding: .utf8) {
            let path = shared.trimmingCharacters(in: .whitespacesAndNewlines)
            return URL(fileURLWithPath: path, relativeTo: gitDir).standardizedFileURL.appendingPathComponent("config")
        }
        return gitDir.appendingPathComponent("config")
    }

    static func remotes(config: String) -> [Remote] {
        var found: [Remote] = []
        var section: String?
        for raw in config.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                section = remoteName(header: line)
                continue
            }
            guard let section, let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            guard key == "url" else { continue }
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            found.append(Remote(name: section, url: value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))))
        }
        return found.filter { $0.name == "origin" } + found.filter { $0.name != "origin" }
    }

    private static func remoteName(header: String) -> String? {
        let inner = header.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        guard inner.lowercased().hasPrefix("remote"),
              let open = inner.firstIndex(of: "\""),
              let close = inner.lastIndex(of: "\""), open < close
        else { return nil }
        return String(inner[inner.index(after: open)..<close])
    }

    static func repo(fromRemote raw: String) -> String? {
        let url = raw.trimmingCharacters(in: .whitespaces)
        let hostAndPath: (host: Substring, path: Substring)
        if let scheme = url.range(of: "://") {
            let rest = url[scheme.upperBound...]
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            hostAndPath = (rest[..<slash], rest[rest.index(after: slash)...])
        } else {
            guard let colon = url.firstIndex(of: ":") else { return nil }
            hostAndPath = (url[..<colon], url[url.index(after: colon)...])
        }

        var host = hostAndPath.host
        if let at = host.lastIndex(of: "@") { host = host[host.index(after: at)...] }
        if let port = host.firstIndex(of: ":") { host = host[..<port] }
        guard ["github.com", "www.github.com"].contains(host.lowercased()) else { return nil }

        let parts = hostAndPath.path.split(separator: "/")
        guard parts.count == 2 else { return nil }
        var name = parts[1]
        if name.hasSuffix(".git") { name = name.dropLast(4) }
        guard !parts[0].isEmpty, !name.isEmpty else { return nil }
        return "\(parts[0])/\(name)"
    }
}
