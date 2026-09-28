import AppKit
import Foundation

@MainActor
enum BenchScenarios {
    static func runHeadless(_ scenario: String) async -> Never {
        switch scenario {
        case "refresh":      await refresh()
        case "launch":       await launch()
        case "review-start": await reviewStart()
        case "sync-parity":  await syncParity()
        default:             Bench.fail("unknown scenario \(scenario). Use refresh, launch, notch-idle or review-start")
        }
    }

    static func refresh() async -> Never {
        Bench.requireIsolatedState()
        let model = AppModel()
        await model.refresh()
        await model.settleState()
        guard model.errorMessage == nil else { Bench.fail(model.errorMessage ?? "") }

        let samples = Bench.Samples()
        let runs = Bench.runs
        for _ in 0..<runs {
            Metrics.shared.reset()
            let start = ContinuousClock.now
            await model.refresh()
            let wall = start.duration(to: .now).millis
            await model.settleState()
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

    static func syncParity() async -> Never {
        let client = GitHubClient()
        let engine = SyncEngine(client: client)
        let pause = Double(Bench.option("--interval").flatMap(Int.init) ?? 20)
        let samples = Bench.Samples()
        let runs = Bench.runs
        func sections(_ q: Queue) -> [[PR]] { [q.mine, q.toReview, q.following] }
        do {
            _ = try await engine.sync(full: true)
            for _ in 0..<runs {
                try? await Task.sleep(for: .seconds(pause))
                var incremental = try await engine.sync().queue
                var truth = try await client.fetchQueue()
                var raced = 0
                if sections(incremental) != sections(truth) {
                    raced = 1
                    incremental = try await engine.sync().queue
                    truth = try await client.fetchQueue()
                }
                let mismatch = sections(incremental) != sections(truth)
                if mismatch {
                    let a = Dictionary(incremental.all.map { ($0.key, $0) }, uniquingKeysWith: { f, _ in f })
                    let b = Dictionary(truth.all.map { ($0.key, $0) }, uniquingKeysWith: { f, _ in f })
                    let differing = Set(a.keys).union(b.keys).filter { a[$0] != b[$0] }
                    FileHandle.standardError.write(Data("bench: mismatch on \(differing.count) PRs\n".utf8))
                }
                samples.add("mismatch", mismatch ? 1 : 0)
                samples.add("raced", raced)
                samples.add("fetched_details", await engine.lastKind == .heartbeatWithDetails ? 1 : 0)
                samples.add("prs", truth.all.count)
            }
        } catch {
            Bench.fail(error.localizedDescription)
        }
        Bench.finish("sync-parity", samples, runs: runs)
    }

    static func launch() async -> Never {
        Bench.requireIsolatedState()
        let primer = AppModel()
        await primer.refresh()
        await primer.settleState()
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
            while model.lastSync == nil {
                if start.duration(to: .now) > .seconds(60) { Bench.fail("the first refresh never finished") }
                try? await Task.sleep(for: .milliseconds(5))
            }
            samples.add("time_to_fresh_queue_ms", start.duration(to: .now).millis)
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

        func removeWorktree() async {
            guard let old = Worktree.existing(repo: repo, pr: number) else { return }
            await Worktree.discard(origin: origin, target: old)
            try? FileManager.default.removeItem(at: old)
        }

        func untilClaude(_ model: AppModel, _ pr: PR) async throws -> (context: Double, total: Double) {
            let start = ContinuousClock.now
            let context = try await model.reviewContext(for: pr)
            let afterContext = ContinuousClock.now
            _ = try await Worktree.prepare(
                origin: origin, repo: repo, pr: number, base: context.base, head: context.head
            )
            return (start.duration(to: afterContext).millis, start.duration(to: .now).millis)
        }

        do {
            guard let pr = try await client.fetchRepoPRs(repo).first(where: { $0.number == number }) else {
                Bench.fail("\(target) is not an open pull request")
            }
            for _ in 0..<runs {
                await removeWorktree()
                let cold = try await untilClaude(AppModel(client: client), pr)
                samples.add("context_ms", cold.context)
                samples.add("worktree_cold_ms", cold.total - cold.context)
                samples.add("until_claude_cold_ms", cold.total)

                await removeWorktree()
                let model = AppModel(client: client)
                let warming = ContinuousClock.now
                await model.prefetcher.warm([.init(pr: pr, origin: origin)])
                samples.add("prefetch_background_ms", warming.duration(to: .now).millis)
                let prefetched = try await untilClaude(model, pr)
                samples.add("until_claude_prefetched_ms", prefetched.total)

                let warm = try await untilClaude(model, pr)
                samples.add("until_claude_warm_ms", warm.total)
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
