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
    case aiReview(pr: String, at: Date)
    case map(stack: String, at: Date)

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
        case .aiReview(let pr, let at):     "aiReview/\(pr)/\(at.timeIntervalSince1970)"
        case .map(let stack, let at):       "map/\(stack)/\(at.timeIntervalSince1970)"
        }
    }
}

enum QueryTag: Hashable, Sendable { case queue, pr(String), repo(String), team }

struct CacheQuery<T: Sendable> {
    let key: QueryKey
    var tags: [QueryTag] = []
    var staleAfter: Duration
    var forgetAfter: Duration = .seconds(300)
    var persists = false
    let fetch: @Sendable (GitHubClient, T?) async throws -> T
}

extension CacheQuery {
    init(
        key: QueryKey, tags: [QueryTag] = [], staleAfter: Duration, forgetAfter: Duration = .seconds(300),
        persists: Bool = false, fetch: @escaping @Sendable (GitHubClient) async throws -> T
    ) {
        self.init(key: key, tags: tags, staleAfter: staleAfter, forgetAfter: forgetAfter, persists: persists) { github, _ in
            try await fetch(github)
        }
    }
}

struct StoredQuery: Codable, Sendable, Equatable {
    var data: Data
    var at: Date
}

@MainActor
final class QueryObserver<T: Sendable>: ObservableObject {
    @Published private(set) var data: T?
    @Published private(set) var isFetching = false
    @Published private(set) var error: Error?

    var onChange: (() -> Void)?
    var key: QueryKey { query.key }

    private let client: QueryClient
    private let query: CacheQuery<T>

    fileprivate init(client: QueryClient, query: CacheQuery<T>) {
        self.client = client
        self.query = query
    }

    func refetch() async {
        _ = try? await client.fetch(query, force: true)
    }

    fileprivate func show(_ entry: AnyEntry) {
        data = entry.data as? T
        isFetching = entry.task != nil
        error = entry.error
        onChange?()
    }

    isolated deinit {
        client.stopObserving(query.key, self)
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
    var forgetAfter: Duration = .zero
    var observers: [ObjectIdentifier: (AnyEntry) -> Void] = [:]
    var refetch: (() -> Void)?
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

    init(github: GitHubClient, store: Store? = nil, now: @escaping () -> Date = Date.init) {
        self.github = github
        self.store = store
        self.now = now
    }

    func observe<T: Sendable>(_ q: CacheQuery<T>, fetching: Bool = true) -> QueryObserver<T> {
        let entry = entry(for: q)
        let observer = QueryObserver(client: self, query: q)
        entry.forget?.cancel()
        entry.forget = nil
        entry.observers[ObjectIdentifier(observer)] = { [weak observer] in observer?.show($0) }
        if fetching { prefetch(q) }
        observer.show(entry)
        return observer
    }

    func fetch<T: Sendable>(_ q: CacheQuery<T>, force: Bool = false) async throws -> T {
        let entry = entry(for: q)
        if force { expire(entry) }
        while true {
            if !needsFetch(entry, q), let data = entry.data as? T { return data }
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
        guard entry.task == nil, needsFetch(entry, q) else { return }
        _ = start(q, entry)
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
        entry.notify()
        forgetIfUnobserved(key, entry)
    }

    func move(_ from: QueryKey, to: QueryKey) {
        guard from != to, entries[to] == nil, let entry = entries.removeValue(forKey: from),
              entry.observers.isEmpty, entry.task == nil else { return }
        entries[to] = entry
        forgetIfUnobserved(to, entry)
    }

    func invalidate(_ tag: QueryTag) {
        for entry in entries.values where entry.tags.contains(tag) { expireAndRefetch(entry) }
    }

    func invalidateAll() {
        for entry in entries.values { expireAndRefetch(entry) }
    }

    func setData<T: Sendable>(_ key: QueryKey, _ update: (inout T) -> Void) {
        guard let entry = entries[key], var data = entry.data as? T else { return }
        update(&data)
        entry.data = data
        entry.notify()
        persist(key, entry, data)
    }

    func settle() async {
        while let task = entries.values.first(where: { $0.task != nil })?.task {
            _ = try? await task.value
        }
    }

    fileprivate func stopObserving(_ key: QueryKey, _ observer: AnyObject) {
        guard let entry = entries[key] else { return }
        entry.observers[ObjectIdentifier(observer)] = nil
        forgetIfUnobserved(key, entry)
    }

    private func entry<T: Sendable>(for q: CacheQuery<T>) -> AnyEntry {
        if let entry = entries[q.key] { return entry }
        let entry = AnyEntry()
        entry.tags = q.tags
        entry.persists = q.persists
        entry.forgetAfter = q.forgetAfter
        if q.persists, let stored = store?.state.cache.queries?[q.key.id],
           let decoded = Self.decode(T.self, stored.data) {
            entry.data = decoded
            entry.fetchedAt = stored.at
        }
        entry.refetch = { [weak self] in self?.prefetch(q) }
        entries[q.key] = entry
        return entry
    }

    private func needsFetch<T>(_ entry: AnyEntry, _ q: CacheQuery<T>) -> Bool {
        guard entry.data != nil, let at = entry.fetchedAt, !entry.invalidated else { return true }
        return now().timeIntervalSince(at) > q.staleAfter.seconds
    }

    private func start<T: Sendable>(_ q: CacheQuery<T>, _ entry: AnyEntry) -> Task<any Sendable, Error> {
        let version = entry.version
        let github = github
        let previous = entry.data as? T
        let task = Task<any Sendable, Error> { @MainActor [weak self] in
            do {
                let value = try await q.fetch(github, previous)
                guard entry.version == version else { throw Superseded() }
                entry.task = nil
                entry.data = value
                entry.fetchedAt = self?.now() ?? Date()
                entry.error = nil
                entry.invalidated = false
                entry.notify()
                self?.persist(q.key, entry, value)
                self?.forgetIfUnobserved(q.key, entry)
                return value
            } catch {
                guard entry.version == version else { throw Superseded() }
                entry.task = nil
                entry.error = error
                entry.notify()
                self?.forgetIfUnobserved(q.key, entry)
                throw error
            }
        }
        entry.forget?.cancel()
        entry.forget = nil
        entry.task = task
        entry.notify()
        return task
    }

    private func expire(_ entry: AnyEntry) {
        entry.version += 1
        entry.invalidated = true
        entry.task = nil
    }

    private func expireAndRefetch(_ entry: AnyEntry) {
        expire(entry)
        entry.notify()
        if !entry.observers.isEmpty { entry.refetch?() }
    }

    private func forgetIfUnobserved(_ key: QueryKey, _ entry: AnyEntry) {
        guard entry.observers.isEmpty else { return }
        entry.forget?.cancel()
        entry.forget = Task { [weak self, after = entry.forgetAfter] in
            try? await Task.sleep(for: after)
            guard !Task.isCancelled, let self, self.entries[key] === entry,
                  entry.observers.isEmpty, entry.task == nil else { return }
            self.entries[key] = nil
            if self.store?.state.cache.queries?[key.id] != nil {
                self.store?.updateCache { $0.queries?[key.id] = nil }
            }
        }
    }

    private func persist<T: Sendable>(_ key: QueryKey, _ entry: AnyEntry, _ value: T) {
        guard entry.persists, let store, let value = value as? any Encodable,
              let data = try? Self.encoder.encode(value),
              store.state.cache.queries?[key.id]?.data != data else { return }
        let stored = StoredQuery(data: data, at: entry.fetchedAt ?? now())
        store.updateCache { $0.queries = ($0.queries ?? [:]).merging([key.id: stored]) { $1 } }
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

private extension Duration {
    var seconds: TimeInterval {
        let (s, atto) = components
        return TimeInterval(s) + TimeInterval(atto) / 1e18
    }
}
