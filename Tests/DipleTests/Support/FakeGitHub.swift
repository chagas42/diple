import Foundation

extension FakeWorld {
    static func beat(_ p: FakePR) -> [String: Any] {
        [
            "id": p.id,
            "updatedAt": iso(p.updatedAt),
            "isDraft": p.draft,
            "reviewDecision": p.decision.map { $0 as Any } ?? NSNull(),
            "commits": ["nodes": [["commit": ["statusCheckRollup": p.checks.map { ["state": $0] as Any } ?? NSNull()]]]],
        ]
    }

    func heartbeatResponse(for query: String) -> Data {
        let section: [FakePR] =
            query.contains("review-requested:@me") ? toReview
            : query.contains("involves:@me") ? following
            : mine
        let data: [String: Any] = [
            "viewer": ["login": viewer],
            "section": ["nodes": section.map(Self.beat)],
            "rateLimit": ["remaining": rateLimit, "resetAt": Self.iso(Self.epoch.addingTimeInterval(3600))],
        ]
        return try! JSONSerialization.data(withJSONObject: ["data": data])
    }

    func detailResponse(_ ids: [String], hiding hidden: Set<String> = []) -> Data {
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let nodes: [Any] = ids.map { id in
            guard !hidden.contains(id), let p = byId[id] else { return NSNull() }
            return Self.json(p)
        }
        return try! JSONSerialization.data(withJSONObject: ["data": ["viewer": ["login": viewer], "nodes": nodes]])
    }
}

final class FakeGitHub: @unchecked Sendable {
    private let lock = NSLock()
    private var current: FakeWorld
    private var hidden: Set<String> = []
    private var failing: Set<String> = []
    private(set) var transport: StubTransport!

    init(_ world: FakeWorld) {
        current = world
        transport = StubTransport { [self] query in self.reply(query) }
    }

    var world: FakeWorld {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }

    func edit(_ change: (inout FakeWorld) -> Void) {
        lock.withLock { change(&current) }
    }

    func hideFromDetails(_ ids: Set<String>) { lock.withLock { hidden = ids } }

    func timeOut(_ sectionsOrIds: Set<String>) { lock.withLock { failing = sectionsOrIds } }

    func reply(_ query: String) -> StubTransport.Reply {
        let (w, h, f) = lock.withLock { (current, hidden, failing) }
        if query.contains("query Beat") { return .init(body: w.heartbeatResponse(for: query)) }
        if query.contains("query Detail") {
            let ids = Self.ids(in: query)
            if ids.contains(where: f.contains) { return .init(status: 504) }
            return .init(body: w.detailResponse(ids, hiding: h))
        }
        if f.contains(where: { query.contains("\($0): search") }) { return .init(status: 504) }
        return .init(body: w.queueResponse())
    }

    static func ids(in query: String) -> [String] {
        guard let open = query.range(of: "nodes(ids: ["),
              let close = query.range(of: "])", range: open.upperBound..<query.endIndex) else { return [] }
        return query[open.upperBound..<close.lowerBound]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"")) }
    }

    static func kind(_ query: String) -> String {
        if query.contains("query Beat") { return "beat" }
        if query.contains("query Detail") { return "detail" }
        if query.contains("query Queue") { return "full" }
        return "other"
    }

    static func syncKinds<S: Sequence>(_ queries: S) -> [String] where S.Element == String {
        queries.map(kind).filter { $0 != "other" }
    }
}
