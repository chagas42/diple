import Foundation

enum GitDir {
    static func common(of checkout: URL, files: FileManager = .default) -> URL? {
        let dotGit = checkout.appendingPathComponent(".git")
        var isFolder: ObjCBool = false
        guard files.fileExists(atPath: dotGit.path, isDirectory: &isFolder) else { return nil }
        let gitDir = isFolder.boolValue ? dotGit : pointer(in: dotGit, from: checkout)
        guard let gitDir else { return nil }
        guard let shared = firstLine(of: gitDir.appendingPathComponent("commondir")) else {
            return gitDir.standardizedFileURL
        }
        return resolve(shared, against: gitDir)
    }

    static func firstLine(of file: URL) -> String? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        return line?.isEmpty == false ? line : nil
    }

    private static func pointer(in file: URL, from checkout: URL) -> URL? {
        guard let line = firstLine(of: file), line.hasPrefix("gitdir:") else { return nil }
        let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        return resolve(path, against: checkout)
    }

    private static func resolve(_ path: String, against base: URL) -> URL {
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path)
        return url.standardizedFileURL
    }
}

struct RemoteBranch: Hashable, Sendable, CustomStringConvertible {
    let remote: String
    let branch: String

    var ref: String { "refs/remotes/\(remote)/\(branch)" }
    var description: String { "\(remote)/\(branch)" }

    init(remote: String, branch: String) {
        self.remote = remote
        self.branch = branch
    }

    init?(ref: Substring) {
        guard ref.hasPrefix("refs/remotes/") else { return nil }
        let parts = ref.dropFirst("refs/remotes/".count).split(separator: "/", maxSplits: 1)
        guard parts.count == 2, parts[1] != "HEAD", !parts[1].hasSuffix(".lock") else { return nil }
        self.init(remote: String(parts[0]), branch: String(parts[1]))
    }
}

enum RemoteRefs {
    enum Change: Equatable {
        case branch(RemoteBranch)
        case packed
    }

    static func change(at path: String, under root: String) -> Change? {
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(prefix) else { return nil }
        let inside = path.dropFirst(prefix.count)
        if inside == "packed-refs" { return .packed }
        let ref = inside.hasPrefix("logs/") ? inside.dropFirst("logs/".count) : inside
        return RemoteBranch(ref: ref).map(Change.branch)
    }

    static func packed(_ text: String) -> [RemoteBranch: String] {
        var refs: [RemoteBranch: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") && !line.hasPrefix("^") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let branch = RemoteBranch(ref: parts[1]) else { continue }
            refs[branch] = String(parts[0])
        }
        return refs
    }

    static func moved(from old: [RemoteBranch: String], to new: [RemoteBranch: String]) -> Set<RemoteBranch> {
        Set(new.filter { old[$0.key] != $0.value }.keys)
    }

    static func pushed(lastReflogLine line: String?) -> Bool {
        guard let message = line?.split(separator: "\t", maxSplits: 1).last else { return false }
        return message.hasPrefix("update by push")
    }

    static func defaultBranches(remoteHead: String?) -> Set<String> {
        let prefix = "ref: refs/remotes/"
        guard let head = remoteHead, head.hasPrefix(prefix),
              let name = head.dropFirst(prefix.count).split(separator: "/", maxSplits: 1).last
        else { return ["main", "master"] }
        return [String(name)]
    }
}

enum GitRemote {
    static func url(of remote: String, inConfig text: String) -> String? {
        var inSection = false
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inSection = line == "[remote \"\(remote)\"]"
                continue
            }
            guard inSection else { continue }
            let pair = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2, pair[0] == "url" { return pair[1] }
        }
        return nil
    }

    static func gitHubOwner(of url: String) -> String? {
        let hosts = ["git@github.com:", "ssh://git@github.com/", "https://github.com/", "http://github.com/", "git://github.com/"]
        guard let host = hosts.first(where: url.hasPrefix) else { return nil }
        let owner = url.dropFirst(host.count).split(separator: "/").first.map(String.init)
        return owner?.isEmpty == false ? owner : nil
    }
}

enum PushRule: Equatable, Sendable {
    case ignore
    case syncOnce
    case syncTwice
    case watchForPR(repo: String, head: String)

    static func decide(
        branch: String, pushed: Bool, defaultBranches: Set<String>,
        hasPR: Bool, headOwner: String?, repos: [String]
    ) -> PushRule {
        guard pushed else { return hasPR ? .syncOnce : .ignore }
        if defaultBranches.contains(branch) { return .syncOnce }
        if hasPR { return .syncTwice }
        guard let headOwner else { return .ignore }
        func owner(_ repo: String) -> String { repo.split(separator: "/").first.map(String.init) ?? repo }
        let base = repos.first { owner($0).caseInsensitiveCompare(headOwner) != .orderedSame } ?? repos.first
        guard let base else { return .ignore }
        return .watchForPR(repo: base, head: "\(headOwner):\(branch)")
    }
}

struct PushSchedule: Sendable, Equatable {
    static let settle: TimeInterval = 3
    static let spacing: TimeInterval = 10
    static let followUp: TimeInterval = 12

    private(set) var first: Date?
    private(set) var second: Date?
    private var twice = false
    private var lastSync: Date?

    var next: Date? { [first, second].compactMap { $0 }.min() }

    mutating func signal(at now: Date, twice: Bool) {
        guard first == nil else {
            self.twice = self.twice || twice
            return
        }
        let earliest = lastSync.map { $0.addingTimeInterval(Self.spacing) } ?? now
        first = max(now.addingTimeInterval(Self.settle), earliest)
        second = nil
        self.twice = twice
    }

    mutating func due(at now: Date) -> Bool {
        if let first, first <= now {
            self.first = nil
            second = twice ? now.addingTimeInterval(Self.followUp) : nil
            lastSync = now
            return true
        }
        if let second, second <= now, first == nil {
            self.second = nil
            lastSync = now
            return true
        }
        return false
    }

    mutating func reset() {
        first = nil
        second = nil
    }
}

struct PRWatches: Sendable, Equatable {
    static let backoff: [TimeInterval] = [10, 20, 30]
    static let steady: TimeInterval = 60
    static let window: TimeInterval = 900
    static let cap = 5

    struct Watch: Sendable, Equatable {
        let repo: String
        let head: String
        let started: Date
        var checks = 0
        var due: Date
        var etag: String?

        var key: String { "\(repo) \(head)" }
    }

    private(set) var watches: [Watch] = []

    var next: Date? { watches.map(\.due).min() }

    static func delay(after checks: Int) -> TimeInterval {
        checks < backoff.count ? backoff[checks] : steady
    }

    mutating func start(repo: String, head: String, at now: Date) {
        watches.removeAll { $0.repo == repo && $0.head == head }
        if watches.count >= Self.cap {
            watches.sort { $0.started < $1.started }
            watches.removeFirst(watches.count - Self.cap + 1)
        }
        watches.append(Watch(repo: repo, head: head, started: now, due: now.addingTimeInterval(Self.delay(after: 0))))
    }

    func due(at now: Date) -> [Watch] {
        watches.filter { $0.due <= now }
    }

    mutating func checked(_ key: String, at now: Date, found: Bool, etag: String?) {
        guard let i = watches.firstIndex(where: { $0.key == key }) else { return }
        var w = watches[i]
        w.checks += 1
        w.etag = etag ?? w.etag
        w.due = now.addingTimeInterval(Self.delay(after: w.checks))
        if found || w.due > w.started.addingTimeInterval(Self.window) {
            watches.remove(at: i)
        } else {
            watches[i] = w
        }
    }

    mutating func reset() {
        watches = []
    }
}

enum PullLookup {
    enum Result: Equatable, Sendable {
        case unchanged
        case none(etag: String?)
        case opened(etag: String?)

        var found: Bool { if case .opened = self { true } else { false } }
        var etag: String? {
            switch self {
            case .unchanged:                       nil
            case .none(let e), .opened(let e):     e
            }
        }
    }

    static func path(repo: String, head: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~/:")
        let encoded = head.addingPercentEncoding(withAllowedCharacters: allowed) ?? head
        return "repos/\(repo)/pulls?head=\(encoded)&state=open&per_page=1"
    }

    static func result(status: Int, body: Data, etag: String?) -> Result? {
        switch status {
        case 304:
            return .unchanged
        case 200..<300:
            guard let list = try? JSONSerialization.jsonObject(with: body) as? [Any] else { return nil }
            return list.isEmpty ? .none(etag: etag) : .opened(etag: etag)
        default:
            return nil
        }
    }
}
