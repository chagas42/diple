import Foundation
import os

final class Metrics: @unchecked Sendable {
    static let shared = Metrics()

    enum Counter: String, Sendable {
        case requests, bytesIn, bytesOut, tokenSpawns, storeWrites, storeWritesOnMain
    }

    enum Span: String, Sendable {
        case request, refresh, storeWrite
    }

    struct Snapshot: Codable, Sendable, Equatable {
        var counters: [String: Int] = [:]
        var spans: [String: [Double]] = [:]

        func count(_ c: Counter) -> Int { counters[c.rawValue] ?? 0 }
        func bodies(_ view: String) -> Int { counters["body.\(view)"] ?? 0 }
        func millis(_ s: Span) -> [Double] { spans[s.rawValue] ?? [] }
    }

    private let lock = NSLock()
    private var current = Snapshot()
    private let signposter = OSSignposter(subsystem: "com.chagas42.diple", category: .pointsOfInterest)

    func count(_ c: Counter, by n: Int = 1) {
        add(c.rawValue, n)
    }

    func body(_ view: String) {
        add("body.\(view)", 1)
    }

    func record(_ s: Span, millis: Double) {
        lock.withLock { current.spans[s.rawValue, default: []].append(millis) }
    }

    func measure<T>(_ s: Span, _ work: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval("span", id: signposter.makeSignpostID(), "\(s.rawValue)")
        let start = ContinuousClock.now
        defer {
            record(s, millis: start.duration(to: .now).millis)
            signposter.endInterval("span", state)
        }
        return try work()
    }

    func measure<T>(_ s: Span, _ work: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval("span", id: signposter.makeSignpostID(), "\(s.rawValue)")
        let start = ContinuousClock.now
        defer {
            record(s, millis: start.duration(to: .now).millis)
            signposter.endInterval("span", state)
        }
        return try await work()
    }

    func snapshot() -> Snapshot {
        lock.withLock { current }
    }

    func reset() {
        lock.withLock { current = Snapshot() }
    }

    private func add(_ key: String, _ n: Int) {
        lock.withLock { current.counters[key, default: 0] += n }
    }
}

extension Duration {
    var millis: Double {
        let (s, atto) = components
        return Double(s) * 1000 + Double(atto) / 1e15
    }
}
