import Foundation

enum Tools {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: String] = [:]
    nonisolated(unsafe) private static var extraPaths: [String]?

    static func find(_ name: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[name] { return hit.isEmpty ? nil : hit }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let known = [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
            "\(home)/.local/bin", "\(home)/bin",
            "\(home)/.bun/bin", "\(home)/.volta/bin", "\(home)/.asdf/shims",
            "/opt/homebrew/sbin", "/usr/sbin", "/sbin",
        ]

        for dir in known + (extraPaths ?? loginShellPath()) {
            let candidate = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) {
                cache[name] = candidate
                return candidate
            }
        }
        cache[name] = ""
        return nil
    }

    private static func loginShellPath() -> [String] {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-lic", "echo $PATH"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()

        var dirs: [String] = []
        if (try? p.run()) != nil {
            let text = String(
                decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
            )
            p.waitUntilExit()
            dirs = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: ":").map(String.init)
        }
        extraPaths = dirs
        return dirs
    }

    static func process(_ name: String, _ arguments: [String]) throws -> Process {
        guard let exe = find(name) else { throw MissingTool(name: name) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = arguments
        return p
    }
}

struct MissingTool: LocalizedError {
    let name: String
    var errorDescription: String? {
        "\(name) was not found. A GUI app does not inherit your shell PATH, "
        + "so Diple looks in the usual places and asks your login shell. "
        + "If \(name) lives somewhere else, add its folder to your shell profile."
    }
}
