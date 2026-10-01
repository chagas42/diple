import Foundation

enum QueryKey: Hashable, Sendable {
    case queue(watching: Set<String>)
    case team(org: String)
    case ranking(org: String, period: RankPeriod, people: [String])
    case activity(org: String, login: String)
    case repos
    case repoPRs(repo: String)
    case reviewContext(pr: String, at: Date)
    case changedFiles(pr: String, at: Date)
    case aiReview(pr: String, revision: String)
    case map(stack: String, revisions: String)
    case requiredApprovals(repo: String, branch: String)

    var id: String {
        switch self {
        case .queue(let watching):          "queue/\(watching.sorted().joined(separator: ","))"
        case .team(let org):                "team/\(org)"
        case .ranking(let org, let p, let people): "ranking/\(org)/\(p.rawValue)/\(people.joined(separator: ","))"
        case .activity(let org, let login): "activity/\(org)/\(login)"
        case .repos:                        "repos"
        case .repoPRs(let repo):            "repoPRs/\(repo)"
        case .reviewContext(let pr, let at): "reviewContext/\(pr)/\(at.timeIntervalSince1970)"
        case .changedFiles(let pr, let at): "changedFiles/\(pr)/\(at.timeIntervalSince1970)"
        case .aiReview(let pr, let rev):    "aiReview/\(pr)/\(rev)"
        case .map(let stack, let revs):     "map/\(stack)/\(revs)"
        case .requiredApprovals(let repo, let branch): "requiredApprovals/\(repo)/\(branch)"
        }
    }
}

enum QueryTag: Hashable, Sendable { case queue, pr(String), repo(String), team }

struct CacheQuery<T: Sendable>: Sendable {
    let key: QueryKey
    var tags: [QueryTag] = []
    var staleAfter: Duration
    var forgetAfter: Duration = .seconds(300)
    var persists = false
    var persistFor: Duration = .seconds(30 * 24 * 3600)
    var retryDelays: [Duration] = []
    var onSuccess: (@MainActor @Sendable (T) async -> Void)? = nil
    var onError: (@MainActor @Sendable (Error) -> Void)? = nil
    let fetch: @Sendable (GitHubClient, T?) async throws -> T
}

extension CacheQuery {
    init(
        key: QueryKey, tags: [QueryTag] = [], staleAfter: Duration, forgetAfter: Duration = .seconds(300),
        persists: Bool = false,
        persistFor: Duration = .seconds(30 * 24 * 3600),
        onSuccess: (@MainActor @Sendable (T) async -> Void)? = nil,
        onError: (@MainActor @Sendable (Error) -> Void)? = nil,
        fetch: @escaping @Sendable (GitHubClient) async throws -> T
    ) {
        self.init(
            key: key, tags: tags, staleAfter: staleAfter, forgetAfter: forgetAfter, persists: persists,
            persistFor: persistFor, onSuccess: onSuccess, onError: onError
        ) { github, _ in try await fetch(github) }
    }
}

struct StoredQuery: Codable, Sendable, Equatable {
    var data: Data
    var at: Date
    var forgetAt: Date? = nil
}

@MainActor
final class QueryObserver<T: Sendable>: ObservableObject {
    @Published private(set) var fetched: T?
    @Published private(set) var isFetching = false
    @Published private(set) var error: Error?

    let placeholder: T?
    var key: QueryKey { query.key }
    var data: T? { fetched ?? placeholder }
    var isLoading: Bool { isFetching && fetched == nil }

    fileprivate let token = UUID()
    private let client: QueryClient
    private let query: CacheQuery<T>

    fileprivate init(client: QueryClient, query: CacheQuery<T>, placeholder: T?) {
        self.client = client
        self.query = query
        self.placeholder = placeholder
    }

    func refetch() async {
        _ = try? await client.fetch(query, force: true)
    }

    fileprivate func show(_ entry: AnyEntry) {
        let data = entry.data as? T
        if !QueryClient.same(data, fetched) { fetched = data }
        if isFetching != (entry.task != nil) { isFetching = entry.task != nil }
        if error != nil || entry.error != nil { error = entry.error }
    }

    deinit {
        let (client, key, token) = (client, query.key, token)
        Task { @MainActor in client.stopObserving(key, token) }
    }
}

@MainActor
final class QueryHold {
    fileprivate let token = UUID()
    private let client: QueryClient
    private let key: QueryKey

    fileprivate init(client: QueryClient, key: QueryKey) {
        self.client = client
        self.key = key
    }

    deinit {
        let (client, key, token) = (client, key, token)
        Task { @MainActor in client.stopObserving(key, token) }
    }
}

@MainActor
private final class AnyEntry {
    var data: (any Sendable)?
    var fetchedAt: Date?
    var error: Error?
    var task: Task<any Sendable, Error>?
    var version = 0
    var invalidated = false
    var tags: [QueryTag] = []
    var persists = false
    var persistFor: Duration = .zero
    var staleAfter: Duration = .zero
    var forgetAfter: Duration = .zero
    var observers: [UUID: (AnyEntry) -> Void] = [:]
    var refetch: ((_ force: Bool) -> Void)?
    var forget: Task<Void, Never>?

    func notify() {
        for show in observers.values { show(self) }
    }
}

private struct Superseded: Error {}

@MainActor
final class QueryClient {
    private let github: GitHubClient
    private let store: Store?
    private let now: () -> Date
    private var entries: [QueryKey: AnyEntry] = [:]
    private var background: [UUID: Task<Void, Never>] = [:]
    private var decoded: [String: any Sendable] = [:]
    private var decoding: Task<Void, Never>?

    typealias Decode = @Sendable (Data) throws -> any Sendable

    var onChange: (() -> Void)?

    init(
        github: GitHubClient, store: Store? = nil, now: @escaping () -> Date = Date.init,
        decoders: [String: Decode] = [:]
    ) {
        self.github = github
        self.store = store
        self.now = now
        pruneExpired()
        decodeSaved(with: decoders)
    }

    func savedDecoded() async { await decoding?.value }

    func observe<T: Sendable>(_ q: CacheQuery<T>, placeholder: T? = nil, fetching: Bool = true) -> QueryObserver<T> {
        let entry = entry(for: q)
        let observer = QueryObserver(client: self, query: q, placeholder: placeholder)
        entry.forget?.cancel()
        entry.forget = nil
        entry.observers[observer.token] = { [weak observer] in observer?.show($0) }
        if fetching { prefetch(q) }
        observer.show(entry)
        return observer
    }

    func hold(_ key: QueryKey) -> QueryHold {
        let hold = QueryHold(client: self, key: key)
        let entry = entries[key] ?? AnyEntry()
        entries[key] = entry
        entry.forget?.cancel()
        entry.forget = nil
        entry.observers[hold.token] = { _ in }
        return hold
    }

    func fetch<T: Sendable>(_ q: CacheQuery<T>, force: Bool = false) async throws -> T {
        let entry = entry(for: q)
        if force { expire(entry) }
        while true {
            if !needsFetch(entry), let data = entry.data as? T { return data }
            let version = entry.version
            let task = entry.task ?? start(q, entry)
            do {
                let value = try await task.value
                if entry.version == version, let value = value as? T { return value }
            } catch {
                if entry.version == version, !(error is Superseded) { throw error }
            }
        }
    }

    func prefetch<T: Sendable>(_ q: CacheQuery<T>) {
        let entry = entry(for: q)
        guard entry.task == nil, needsFetch(entry) else { return }
        _ = start(q, entry)
    }

    func prefetch<A: Sendable, B: Sendable>(_ first: CacheQuery<A>, then next: @escaping (A) -> CacheQuery<B>?) {
        let id = UUID()
        background[id] = Task { [weak self] in
            if let self, let a = try? await self.fetch(first), let q = next(a) { self.prefetch(q) }
            self?.background[id] = nil
        }
    }

    func peek<T: Sendable>(_ q: CacheQuery<T>) -> T? {
        entry(for: q).data as? T
    }

    func cached<T: Sendable>(_ key: QueryKey, as _: T.Type = T.self) -> T? {
        entries[key]?.data as? T
    }

    func isFetching(_ key: QueryKey) -> Bool { entries[key]?.task != nil }

    func put<T: Sendable>(_ key: QueryKey, _ value: T, tags: [QueryTag] = [], forgetAfter: Duration) {
        let entry = entries[key] ?? AnyEntry()
        entry.tags = tags
        entry.forgetAfter = forgetAfter
        entry.data = value
        entry.fetchedAt = now()
        entries[key] = entry
        changed(entry)
        forgetIfUnobserved(key, entry)
    }

    func invalidate(_ tag: QueryTag) {
        for (key, entry) in entries where entry.tags.contains(tag) { expireAndRefetch(key, entry) }
    }

    func refetchObserved(force: Bool = false, except spared: QueryTag? = nil) {
        for entry in entries.values where !entry.observers.isEmpty {
            if let spared, entry.tags.contains(spared) { continue }
            entry.refetch?(force)
        }
    }

    func setData<T: Sendable>(_ key: QueryKey, _ update: (inout T) -> Void) {
        guard let entry = entries[key], var data = entry.data as? T else { return }
        update(&data)
        guard !Self.same(data, entry.data as? T) else { return }
        entry.data = data
        changed(entry)
        persist(key, entry, data)
    }

    func settle() async {
        while true {
            if let task = entries.values.first(where: { $0.task != nil })?.task {
                _ = try? await task.value
            } else if let task = background.values.first {
                await task.value
            } else {
                return
            }
        }
    }

    fileprivate func stopObserving(_ key: QueryKey, _ observer: UUID) {
        guard let entry = entries[key] else { return }
        entry.observers[observer] = nil
        forgetIfUnobserved(key, entry)
    }

    nonisolated static func same<T>(_ a: T?, _ b: T?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (let a?, let b?):
            guard let a = a as? any Equatable else { return false }
            return a.isEqual(to: b)
        default: return false
        }
    }

    private func entry<T: Sendable>(for q: CacheQuery<T>) -> AnyEntry {
        if let entry = entries[q.key] { return entry }
        let entry = AnyEntry()
        entry.tags = q.tags
        entry.persists = q.persists
        entry.persistFor = q.persistFor
        entry.staleAfter = q.staleAfter
        entry.forgetAfter = q.forgetAfter
        if q.persists, let stored = store?.state.cache.queries?[q.key.id],
           let value = (decoded.removeValue(forKey: q.key.id) as? T) ?? Self.decode(T.self, stored.data) {
            entry.data = value
            entry.fetchedAt = stored.at
        }
        entry.refetch = { [weak self] force in
            guard let self else { return }
            if force { Task { _ = try? await self.fetch(q, force: true) } } else { self.prefetch(q) }
        }
        entries[q.key] = entry
        forgetIfUnobserved(q.key, entry)
        return entry
    }

    private func needsFetch(_ entry: AnyEntry) -> Bool {
        guard entry.data != nil, let at = entry.fetchedAt, !entry.invalidated else { return true }
        return now().timeIntervalSince(at) >= entry.staleAfter.seconds
    }

    private func start<T: Sendable>(_ q: CacheQuery<T>, _ entry: AnyEntry) -> Task<any Sendable, Error> {
        let version = entry.version
        let github = github
        let previous = entry.data as? T
        let task = Task<any Sendable, Error> { @MainActor [weak self] in
            do {
                let value = try await Self.fetching(q, github, previous) { entry.version == version }
                guard entry.version == version else { throw Superseded() }
                let old = entry.data as? T
                let unchanged = Self.same(value, old)
                let kept = unchanged ? old ?? value : value
                entry.data = kept
                entry.fetchedAt = self?.now() ?? Date()
                entry.error = nil
                entry.invalidated = false
                self?.persist(q.key, entry, kept, unchanged: unchanged)
                await q.onSuccess?(kept)
                if entry.version == version { entry.task = nil }
                self?.changed(entry)
                self?.forgetIfUnobserved(q.key, entry)
                return kept
            } catch {
                if entry.version == version && !(error is Superseded) {
                    entry.task = nil
                    entry.error = error
                    q.onError?(error)
                    self?.changed(entry)
                }
                self?.forgetIfUnobserved(q.key, entry)
                throw entry.version == version ? error : Superseded()
            }
        }
        entry.forget?.cancel()
        entry.forget = nil
        entry.task = task
        changed(entry)
        return task
    }

    private static func fetching<T>(
        _ q: CacheQuery<T>, _ github: GitHubClient, _ previous: T?, stillWanted: () -> Bool
    ) async throws -> T {
        var delays = q.retryDelays[...]
        while true {
            do {
                return try await q.fetch(github, previous)
            } catch let error as URLError where error.code != .cancelled {
                guard let delay = delays.popFirst(), stillWanted() else { throw error }
                try await Task.sleep(for: delay)
            }
        }
    }

    private func changed(_ entry: AnyEntry) {
        entry.notify()
        onChange?()
    }

    private func expire(_ entry: AnyEntry) {
        entry.version += 1
        entry.invalidated = true
        entry.task?.cancel()
        entry.task = nil
    }

    private func expireAndRefetch(_ key: QueryKey, _ entry: AnyEntry) {
        expire(entry)
        changed(entry)
        if entry.observers.isEmpty { forgetIfUnobserved(key, entry) } else { entry.refetch?(false) }
    }

    private func forgetIfUnobserved(_ key: QueryKey, _ entry: AnyEntry) {
        guard entry.observers.isEmpty, entry.task == nil else { return }
        entry.forget?.cancel()
        entry.forget = Task { [weak self, after = entry.forgetAfter] in
            try? await Task.sleep(for: after)
            guard !Task.isCancelled, let self, self.entries[key] === entry,
                  entry.observers.isEmpty, entry.task == nil else { return }
            self.entries[key] = nil
            self.onChange?()
        }
    }

    private func persist<T: Sendable>(_ key: QueryKey, _ entry: AnyEntry, _ value: T, unchanged: Bool = false) {
        guard entry.persists, let store, let value = value as? any Encodable else { return }
        let at = entry.fetchedAt ?? now()
        let stored = store.state.cache.queries?[key.id]
        let recent = stored.map { at.timeIntervalSince($0.at) < entry.staleAfter.seconds } ?? false
        if unchanged, recent { return }
        guard let data = try? Self.encoder.encode(value) else { return }
        if stored?.data == data, recent { return }
        decoded[key.id] = nil
        let row = StoredQuery(data: data, at: at, forgetAt: at.addingTimeInterval(entry.persistFor.seconds))
        store.updateCache { $0.queries = ($0.queries ?? [:]).merging([key.id: row]) { $1 } }
    }

    private func decodeSaved(with decoders: [String: Decode]) {
        guard !decoders.isEmpty, let rows = store?.state.cache.queries else { return }
        let work = rows.compactMap { id, row in
            decoders[String(id.prefix { $0 != "/" })].map { (id, row.data, $0) }
        }
        guard !work.isEmpty else { return }
        decoding = Task { [weak self] in
            let values = await Task.detached(priority: .userInitiated) {
                var out: [String: any Sendable] = [:]
                for (id, data, decode) in work { out[id] = try? decode(data) }
                return out
            }.value
            guard let self else { return }
            for (id, value) in values where self.entries.keys.allSatisfy({ $0.id != id }) {
                self.decoded[id] = value
            }
        }
    }

    private func pruneExpired() {
        guard let store, let rows = store.state.cache.queries else { return }
        let now = now()
        let expired = rows.filter { $0.value.forgetAt.map { $0 < now } ?? false }.map(\.key)
        guard !expired.isEmpty else { return }
        store.updateCache { cache in for id in expired { cache.queries?[id] = nil } }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return e
    }()

    private static func decode<T>(_: T.Type, _ data: Data) -> T? {
        guard let type = T.self as? any Decodable.Type else { return nil }
        return (try? JSONDecoder().decode(type, from: data)) as? T
    }
}

private extension Equatable {
    func isEqual(to other: Any) -> Bool {
        guard let other = other as? Self else { return false }
        return self == other
    }
}

extension Duration {
    var seconds: TimeInterval {
        let (s, atto) = components
        return TimeInterval(s) + TimeInterval(atto) / 1e18
    }
}
