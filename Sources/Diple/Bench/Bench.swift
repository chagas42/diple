import AppKit
import Foundation

enum Bench {
    static var scenario: String? { option("--bench") }
    static var isOn: Bool { scenario != nil }

    static func option(_ name: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        let value = args[i + 1]
        return value.hasPrefix("--") ? nil : value
    }

    static var runs: Int { option("--runs").flatMap(Int.init) ?? 10 }

    struct Stat: Codable, Sendable {
        let p50: Double
        let p95: Double
        let mean: Double
        let min: Double
        let max: Double

        init(_ samples: [Double]) {
            let sorted = samples.sorted()
            func rank(_ q: Double) -> Double {
                guard !sorted.isEmpty else { return 0 }
                let i = Int((q * Double(sorted.count)).rounded(.up)) - 1
                return sorted[Swift.max(0, Swift.min(sorted.count - 1, i))]
            }
            p50 = rank(0.5)
            p95 = rank(0.95)
            mean = sorted.isEmpty ? 0 : sorted.reduce(0, +) / Double(sorted.count)
            min = sorted.first ?? 0
            max = sorted.last ?? 0
        }
    }

    struct Report: Codable, Sendable {
        let scenario: String
        let commit: String
        let date: String
        let machine: String
        let runs: Int
        let metrics: [String: Stat]
        let samples: [String: [Double]]
    }

    final class Samples {
        private(set) var values: [String: [Double]] = [:]
        func add(_ key: String, _ v: Double) { values[key, default: []].append(v) }
        func add(_ key: String, _ v: Int) { add(key, Double(v)) }
    }

    static func finish(_ scenario: String, _ samples: Samples, runs: Int) -> Never {
        let env = ProcessInfo.processInfo.environment
        let report = Report(
            scenario: scenario,
            commit: env["DIPLE_BENCH_COMMIT"] ?? "unknown",
            date: ISO8601DateFormatter().string(from: Date()),
            machine: machine(),
            runs: runs,
            metrics: samples.values.mapValues(Stat.init),
            samples: samples.values
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? enc.encode(report)) ?? Data()
        if let out = option("--out") {
            let url = URL(fileURLWithPath: out)
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? data.write(to: url)
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(0)
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("bench: \(message)\n".utf8))
        exit(1)
    }

    static func machine() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: Swift.max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let name = String(decoding: model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return "\(name) · \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }

    static func requireIsolatedState() {
        guard let dir = ProcessInfo.processInfo.environment["DIPLE_STATE_DIR"], !dir.isEmpty else {
            fail("set DIPLE_STATE_DIR so the benchmark never touches your real state.json")
        }
    }

    static func cpuMillis() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func ms(_ t: timeval) -> Double { Double(t.tv_sec) * 1000 + Double(t.tv_usec) / 1000 }
        return ms(usage.ru_utime) + ms(usage.ru_stime)
    }
}
