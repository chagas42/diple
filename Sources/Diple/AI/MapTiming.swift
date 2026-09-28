import Foundation

struct MapEstimate: Sendable, Equatable {
    struct Part: Sendable, Equatable, Identifiable {
        var id: String { label }
        let label: String
        let seconds: Double
    }

    let parts: [Part]
    let raw: Double
    let factor: Double
    let samples: Int

    var seconds: Double { raw * factor }

    var calibration: String {
        guard samples >= MapTiming.minSamples else {
            return "no history yet, using defaults"
        }
        let f = factor.formatted(.number.precision(.fractionLength(2)))
        return "×\(f) from your last \(samples) map\(samples == 1 ? "" : "s")"
    }
}

struct MapRun: Sendable, Equatable {
    var phase: String
    let startedAt: Date
    var estimate: MapEstimate
    var expectedTools: Int
    var toolCalls = 0
    var lastTool: String?

    func elapsed(_ now: Date) -> Double { now.timeIntervalSince(startedAt) }

    func progress(_ now: Date) -> Double {
        let byTools = min(Double(toolCalls) / Double(max(expectedTools, 1)), 0.95)
        let byClock = min(elapsed(now) / max(estimate.seconds, 1), 0.95)
        return max(byTools, byClock * 0.9)
    }

    func total(_ now: Date) -> Double {
        let e = elapsed(now)
        let p = min(Double(toolCalls) / Double(max(expectedTools, 1)), 0.95)
        let projected = p > 0.15 ? e / p : estimate.seconds
        let blended = (1 - p) * estimate.seconds + p * projected
        return max(blended, e)
    }

    func remaining(_ now: Date) -> Double { max(total(now) - elapsed(now), 0) }

    var overdueAfter: Double { estimate.seconds * 2.5 }

    func overdue(_ now: Date) -> Bool { elapsed(now) > overdueAfter }
}

enum MapTiming {
    static let minSamples = 2

    static let startup = 20.0
    static let perFile = 0.8
    static let perThousandLines = 5.0
    static let perDomain = 6.0
    static let freshWorktree = 8.0

    static func expectedTools(_ size: MapSize) -> Int {
        min(max(4 + size.domains * 2, 6), 16)
    }

    static func estimate(size: MapSize, worktreeReady: Bool) -> MapEstimate {
        let files = Double(min(size.files, 400))
        let klines = Double(min(size.lines, 40_000)) / 1000
        let domains = Double(min(size.domains, MapScan.maxDomains))

        var parts = [MapEstimate.Part(label: "session start", seconds: startup)]
        if !worktreeReady {
            parts.append(.init(label: "worktree fetch", seconds: freshWorktree))
        }
        parts.append(.init(label: "\(size.files) files × \(fmt(perFile))s", seconds: files * perFile))
        parts.append(.init(
            label: "\(fmt(Double(size.lines) / 1000))k lines × \(fmt(perThousandLines))s",
            seconds: klines * perThousandLines
        ))
        parts.append(.init(label: "\(Int(domains)) domains × \(fmt(perDomain))s", seconds: domains * perDomain))

        let raw = parts.reduce(0) { $0 + $1.seconds }
        let history = load().suffix(10)
        let ratios = history.map { $0.actual / max($0.raw, 1) }.sorted()
        let factor: Double = ratios.count >= minSamples
            ? min(max(ratios[ratios.count / 2], 0.4), 3)
            : 1
        return MapEstimate(parts: parts, raw: raw, factor: factor, samples: ratios.count)
    }

    static func record(raw: Double, actual: Double, size: MapSize) {
        guard actual > 3 else { return }
        var all = load()
        all.append(Sample(raw: raw, actual: actual, files: size.files, lines: size.lines, at: Date()))
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(Array(all.suffix(30))).write(to: path, options: .atomic)
    }

    static func fmt(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...1)))
    }

    private struct Sample: Codable {
        let raw: Double
        let actual: Double
        let files: Int
        let lines: Int
        let at: Date
    }

    private static var path: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Diple", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("map-timings.json")
    }

    private static func load() -> [Sample] {
        guard let bytes = try? Data(contentsOf: path) else { return [] }
        return (try? JSONDecoder().decode([Sample].self, from: bytes)) ?? []
    }
}
