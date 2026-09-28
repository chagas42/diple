import AppKit
import Foundation

@MainActor
enum BenchScenarios {
    static func runHeadless(_ scenario: String) async -> Never {
        switch scenario {
        case "refresh":      await refresh()
        case "launch":       await launch()
        case "review-start": await reviewStart()
        default:             Bench.fail("unknown scenario \(scenario). Use refresh, launch, notch-idle or review-start")
        }
    }

    static func refresh() async -> Never {
        Bench.requireIsolatedState()
        let model = AppModel()
        await model.refresh()
        guard model.errorMessage == nil else { Bench.fail(model.errorMessage ?? "") }

        let samples = Bench.Samples()
        let runs = Bench.runs
        for _ in 0..<runs {
            Metrics.shared.reset()
            let start = ContinuousClock.now
            await model.refresh()
            let wall = start.duration(to: .now).millis
            if let e = model.errorMessage { Bench.fail(e) }
            record(Metrics.shared.snapshot(), wall: wall, into: samples)
        }
        Bench.finish("refresh", samples, runs: runs)
    }

    static func record(_ s: Metrics.Snapshot, wall: Double, into samples: Bench.Samples) {
        samples.add("wall_ms", wall)
        samples.add("requests", s.count(.requests))
        samples.add("bytes_in", s.count(.bytesIn))
        samples.add("token_spawns", s.count(.tokenSpawns))
        samples.add("store_writes", s.count(.storeWrites))
        samples.add("store_writes_on_main", s.count(.storeWritesOnMain))
        samples.add("store_write_ms", s.millis(.storeWrite).reduce(0, +))
    }

    static func launch() async -> Never {
        Bench.requireIsolatedState()
        let primer = AppModel()
        await primer.refresh()
        guard primer.errorMessage == nil else { Bench.fail(primer.errorMessage ?? "") }

        let samples = Bench.Samples()
        let runs = Bench.runs
        for _ in 0..<runs {
            Metrics.shared.reset()
            let start = ContinuousClock.now
            let model = AppModel()
            model.start()
            while model.queue.all.isEmpty {
                if start.duration(to: .now) > .seconds(60) { Bench.fail("the queue never arrived") }
                try? await Task.sleep(for: .milliseconds(2))
            }
            samples.add("time_to_queue_ms", start.duration(to: .now).millis)
            samples.add("requests_before_queue", Metrics.shared.snapshot().count(.requests))
            while model.loading { try? await Task.sleep(for: .milliseconds(20)) }
        }
        Bench.finish("launch", samples, runs: runs)
    }

    static func reviewStart() async -> Never {
        guard let target = Bench.option("--pr"),
              let hash = target.firstIndex(of: "#"),
              let number = Int(target[target.index(after: hash)...]) else {
            Bench.fail("pass --pr owner/repo#number")
        }
        let repo = String(target[..<hash])
        let settings = Store().state.settings
        guard let origin = Worktree.localPath(repo, configured: settings.repoPaths) else {
            Bench.fail("\(repo) is not on this machine")
        }
        let client = GitHubClient()
        let samples = Bench.Samples()
        let runs = Bench.runs
        do {
            for _ in 0..<runs {
                if let old = Worktree.existing(repo: repo, pr: number) {
                    await Worktree.discard(origin: origin, target: old)
                    try? FileManager.default.removeItem(at: old)
                }
                let start = ContinuousClock.now
                let context = try await client.reviewContext(repo: repo, pr: number)
                let afterContext = ContinuousClock.now
                _ = try await Worktree.prepare(origin: origin, repo: repo, pr: number, base: context.base)
                let end = ContinuousClock.now
                samples.add("context_ms", start.duration(to: afterContext).millis)
                samples.add("worktree_cold_ms", afterContext.duration(to: end).millis)
                samples.add("until_claude_cold_ms", start.duration(to: end).millis)

                let warm = ContinuousClock.now
                let warmContext = try await client.reviewContext(repo: repo, pr: number)
                _ = try await Worktree.prepare(origin: origin, repo: repo, pr: number, base: warmContext.base)
                samples.add("until_claude_warm_ms", warm.duration(to: .now).millis)
            }
        } catch {
            Bench.fail(error.localizedDescription)
        }
        Bench.finish("review-start", samples, runs: runs)
    }

    static func notchIdle(notch: NotchController) async -> Never {
        guard Demo.isOn else { Bench.fail("notch-idle runs with --demo") }
        let screen = NSScreen.main?.frame ?? .zero
        let origin = ContinuousClock.now
        notch.pointer = {
            let t = origin.duration(to: .now).millis / 1000
            return CGPoint(
                x: screen.midX + 260 * sin(t * .pi),
                y: screen.maxY - 160 + 60 * cos(t * .pi * 0.7)
            )
        }
        try? await Task.sleep(for: .seconds(2))

        let window = Double(Bench.option("--seconds").flatMap(Int.init) ?? 20)
        let samples = Bench.Samples()
        let runs = Swift.max(1, Swift.min(Bench.runs, 5))
        for _ in 0..<runs {
            Metrics.shared.reset()
            let cpuStart = Bench.cpuMillis()
            let start = ContinuousClock.now
            try? await Task.sleep(for: .seconds(window))
            let elapsed = start.duration(to: .now).millis / 1000
            let cpu = Bench.cpuMillis() - cpuStart
            let s = Metrics.shared.snapshot()
            samples.add("notch_body_per_s", Double(s.bodies("NotchView")) / elapsed)
            samples.add("eye_body_per_s", Double(s.bodies("EyeView")) / elapsed)
            samples.add("cpu_ms_per_s", cpu / elapsed)
            samples.add("cpu_percent", cpu / (elapsed * 10))
        }
        Bench.finish("notch-idle", samples, runs: runs)
    }
}
