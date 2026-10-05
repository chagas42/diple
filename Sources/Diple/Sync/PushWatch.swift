import CoreServices
import Foundation
import os

@MainActor
final class PushWatch {
    struct Clone: Hashable, Sendable {
        let checkout: URL
        let repos: [String]
    }

    typealias Lookup = @Sendable (_ repo: String, _ head: String, _ etag: String?) async -> PullLookup.Result?

    static let log = Logger(subsystem: "com.chagas42.diple", category: "push")

    var onSync: (() async -> Void)?
    var lookup: Lookup?
    var hasPR: (_ repos: [String], _ branch: String) -> Bool = { _, _ in false }

    private struct Root {
        let path: String
        let repos: [String]
        var packed: [RemoteBranch: String]
    }

    private let now: () -> Date
    private var stream: FSEventStreamRef?
    private var roots: [String: Root] = [:]
    private var schedule = PushSchedule()
    private var prWatches = PRWatches()
    private var checking: Set<String> = []
    private var timer: Task<Void, Never>?

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    func watch(_ clones: [Clone]) {
        var wanted: [String: [String]] = [:]
        for clone in clones {
            guard let common = GitDir.common(of: clone.checkout).flatMap(Self.realPath) else { continue }
            wanted[common, default: []].append(contentsOf: clone.repos)
        }
        let unchanged = wanted.count == roots.count
            && wanted.allSatisfy { roots[$0.key].map { Set($0.repos) } == Set($0.value) }
        guard !unchanged else { return }
        stopStream()
        roots = wanted.reduce(into: [:]) { result, entry in
            result[entry.key] = roots[entry.key].map { Root(path: entry.key, repos: entry.value, packed: $0.packed) }
                ?? Root(path: entry.key, repos: entry.value, packed: Self.readPacked(entry.key))
        }
        guard !roots.isEmpty else { return }
        startStream()
        Self.log.info("watching \(self.roots.count) clone(s)")
    }

    func stop() {
        stopStream()
        roots = [:]
        timer?.cancel()
        timer = nil
        schedule.reset()
        prWatches.reset()
    }

    private func startStream() {
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        guard let s = FSEventStreamCreate(
            nil, Self.callback, &context, Array(roots.keys) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags
        ) else { return }
        FSEventStreamSetDispatchQueue(s, .main)
        FSEventStreamStart(s)
        stream = s
    }

    private func stopStream() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    private static let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
        guard let info, let list = unsafeBitCast(paths, to: NSArray.self) as? [String] else { return }
        let watch = Unmanaged<PushWatch>.fromOpaque(info).takeUnretainedValue()
        MainActor.assumeIsolated { watch.received(Array(list.prefix(count))) }
    }

    private func received(_ paths: [String]) {
        var moved: [String: Set<RemoteBranch>] = [:]
        for path in paths {
            guard let root = roots.keys.first(where: { path.hasPrefix($0 + "/") }),
                  let change = RemoteRefs.change(at: path, under: root) else { continue }
            switch change {
            case .branch(let b):
                moved[root, default: []].insert(b)
            case .packed:
                let fresh = Self.readPacked(root)
                moved[root, default: []].formUnion(RemoteRefs.moved(from: roots[root]?.packed ?? [:], to: fresh))
                roots[root]?.packed = fresh
            }
        }
        for (root, branches) in moved {
            for branch in branches { apply(rule(for: branch, in: root), branch: branch) }
        }
        arm()
    }

    private func rule(for b: RemoteBranch, in rootPath: String) -> PushRule {
        guard let root = roots[rootPath] else { return .ignore }
        let base = URL(fileURLWithPath: rootPath)
        let refExists = FileManager.default.fileExists(atPath: base.appendingPathComponent(b.ref).path)
            || root.packed[b] != nil
        guard refExists else { return .ignore }
        let reflog = try? String(contentsOf: base.appendingPathComponent("logs/" + b.ref), encoding: .utf8)
        let lastLine = reflog?.split(whereSeparator: \.isNewline).last.map(String.init)
        let config = (try? String(contentsOf: base.appendingPathComponent("config"), encoding: .utf8)) ?? ""
        return PushRule.decide(
            branch: b.branch,
            pushed: RemoteRefs.pushed(lastReflogLine: lastLine),
            defaultBranches: RemoteRefs.defaultBranches(
                remoteHead: GitDir.firstLine(of: base.appendingPathComponent("refs/remotes/\(b.remote)/HEAD"))
            ),
            hasPR: hasPR(root.repos, b.branch),
            headOwner: GitRemote.url(of: b.remote, inConfig: config).flatMap(GitRemote.gitHubOwner),
            repos: root.repos
        )
    }

    private func apply(_ rule: PushRule, branch: RemoteBranch) {
        Self.log.info("\(branch, privacy: .private) moved: \(String(describing: rule), privacy: .private)")
        switch rule {
        case .ignore:
            break
        case .syncOnce:
            schedule.signal(at: now(), twice: false)
        case .syncTwice:
            schedule.signal(at: now(), twice: true)
        case .watchForPR(let repo, let head):
            prWatches.start(repo: repo, head: head, at: now())
        }
    }

    private func arm() {
        timer?.cancel()
        let waiting = prWatches.watches.filter { !checking.contains($0.key) }.map(\.due)
        guard let next = ([schedule.next].compactMap { $0 } + waiting).min() else { return }
        timer = Task { [weak self] in
            let wait = max(0, next.timeIntervalSince(self?.now() ?? next))
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            self.fire()
        }
    }

    private func fire() {
        let at = now()
        if schedule.due(at: at), let onSync {
            Self.log.info("syncing after a push")
            Task { await onSync() }
        }
        for w in prWatches.due(at: at) where !checking.contains(w.key) {
            check(w)
        }
        arm()
    }

    private func check(_ w: PRWatches.Watch) {
        guard let lookup else { return }
        checking.insert(w.key)
        Task {
            let result = await lookup(w.repo, w.head, w.etag)
            checking.remove(w.key)
            guard prWatches.watches.contains(where: { $0.key == w.key && $0.started == w.started }) else { return }
            Self.log.info("pull request for \(w.head, privacy: .private): \(String(describing: result), privacy: .private)")
            prWatches.checked(w.key, at: now(), found: result?.found ?? false, etag: result?.etag)
            if result?.found == true { schedule.signal(at: now(), twice: false) }
            arm()
        }
    }

    private static func realPath(_ url: URL) -> String? {
        guard let resolved = realpath(url.path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func readPacked(_ root: String) -> [RemoteBranch: String] {
        let text = try? String(contentsOfFile: root + "/packed-refs", encoding: .utf8)
        return text.map(RemoteRefs.packed) ?? [:]
    }
}
