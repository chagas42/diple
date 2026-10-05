import Foundation
import Testing
@testable import Diple

@Suite(.serialized) struct ConflictResolverTests {
    struct Repo {
        let root: URL
        var remote: URL { root.appendingPathComponent("remote.git") }
        var work: URL { root.appendingPathComponent("work") }

        func git(_ args: [String], in folder: URL? = nil) async -> Shell.Result {
            await Shell.live.git(args, in: folder ?? work)
        }

        func write(_ file: String, _ text: String) throws {
            try text.write(to: work.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }

        func commit(_ message: String) async {
            _ = await git(["add", "-A"])
            _ = await git(["commit", "-qm", message])
        }

        static func make() async throws -> Repo {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("diple-resolve-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let repo = Repo(root: root)
            _ = await Shell.live.git(["init", "-q", "--bare", "-b", "main", repo.remote.path], in: root)
            _ = await Shell.live.git(["clone", "-q", repo.remote.path, repo.work.path], in: root)
            _ = await repo.git(["config", "user.email", "t@example.invalid"])
            _ = await repo.git(["config", "user.name", "Test"])
            _ = await repo.git(["checkout", "-qb", "main"])
            return repo
        }

        func job(pushes: Bool = true) -> ConflictResolver.Job {
            .init(folder: work, title: "feat: greet louder", baseRef: "main", headRef: "feature",
                  pushURL: remote.path, pushes: pushes)
        }

        func remoteFile(_ file: String, at ref: String = "feature") async -> String {
            (await git(["show", "\(ref):\(file)"], in: remote)).output
        }

        func parents(at ref: String = "feature") async -> Int {
            (await git(["rev-list", "--parents", "-n", "1", ref], in: remote)).output
                .split(separator: " ").count - 1
        }
    }

    static func conflicting() async throws -> Repo {
        let r = try await Repo.make()
        try r.write("greet.txt", "hello\n")
        await r.commit("base")
        _ = await r.git(["push", "-q", "origin", "main"])
        _ = await r.git(["checkout", "-qb", "feature"])
        try r.write("greet.txt", "HELLO\n")
        await r.commit("louder")
        _ = await r.git(["push", "-q", "origin", "feature"])
        _ = await r.git(["checkout", "-q", "main"])
        try r.write("greet.txt", "hello, world\n")
        await r.commit("wider")
        _ = await r.git(["push", "-q", "origin", "main"])
        _ = await r.git(["checkout", "-q", "feature"])
        return r
    }

    static func writer(_ text: String?, into file: String) -> @Sendable (String, URL) async -> Shell.Result {
        { _, folder in
            if let text { try? text.write(to: folder.appendingPathComponent(file), atomically: true, encoding: .utf8) }
            return Shell.Result(status: 0, output: "\(file): kept HELLO and the world")
        }
    }

    @Test func aConflictIsResolvedCommittedAndPushed() async throws {
        let r = try await Self.conflicting()
        let resolver = ConflictResolver(claude: Self.writer("HELLO, WORLD\n", into: "greet.txt"))
        let outcome = await resolver.resolve(r.job()) { _ in }
        guard case .pushed(_, let report) = outcome else { Issue.record("\(outcome)"); return }
        #expect(report.files == ["greet.txt"])
        #expect(await r.remoteFile("greet.txt") == "HELLO, WORLD\n")
        #expect(await r.parents() == 2)
    }

    @Test func markersLeftBehindStopEverythingAndNothingIsPushed() async throws {
        let r = try await Self.conflicting()
        let before = (await r.git(["rev-parse", "feature"], in: r.remote)).output
        let resolver = ConflictResolver(claude: Self.writer(nil, into: "greet.txt"))
        let outcome = await resolver.resolve(r.job()) { _ in }
        guard case .failed(let step, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(step == "resolve")
        #expect((await r.git(["rev-parse", "feature"], in: r.remote)).output == before)
    }

    @Test func aCleanMergeIsPushedWithoutAskingClaude() async throws {
        let r = try await Repo.make()
        try r.write("a.txt", "a\n")
        await r.commit("base")
        _ = await r.git(["push", "-q", "origin", "main"])
        _ = await r.git(["checkout", "-qb", "feature"])
        try r.write("b.txt", "b\n")
        await r.commit("feature")
        _ = await r.git(["push", "-q", "origin", "feature"])
        _ = await r.git(["checkout", "-q", "main"])
        try r.write("c.txt", "c\n")
        await r.commit("main moves")
        _ = await r.git(["push", "-q", "origin", "main"])
        _ = await r.git(["checkout", "-q", "feature"])

        let asked = Counter()
        let resolver = ConflictResolver(claude: { _, _ in asked.add(); return Shell.Result(status: 0, output: "") })
        let outcome = await resolver.resolve(r.job()) { _ in }
        guard case .pushed = outcome else { Issue.record("\(outcome)"); return }
        #expect(asked.value == 0)
        #expect(await r.parents() == 2)
    }

    @Test func checksThatFailedBeforeTheMergeAreNotUsed() async throws {
        let r = try await Self.conflicting()
        try r.write("Makefile", "test:\n\tfalse\n")
        await r.commit("a test that never passes")
        let resolver = ConflictResolver(claude: Self.writer("HELLO, WORLD\n", into: "greet.txt"))
        let outcome = await resolver.resolve(r.job()) { _ in }
        guard case .pushed(_, let report) = outcome else { Issue.record("\(outcome)"); return }
        #expect(report.checks.contains("already failed before the merge"))
    }

    @Test func checksBrokenByTheMergeAreFixedBeforePushing() async throws {
        let r = try await Repo.make()
        try r.write("status", "ok\n")
        try r.write("Makefile", "test:\n\tgrep -qx ok status\n")
        await r.commit("base")
        _ = await r.git(["push", "-q", "origin", "main"])
        _ = await r.git(["checkout", "-qb", "feature"])
        try r.write("feature.txt", "x\n")
        await r.commit("feature")
        _ = await r.git(["push", "-q", "origin", "feature"])
        _ = await r.git(["checkout", "-q", "main"])
        try r.write("status", "broken\n")
        await r.commit("main breaks the check")
        _ = await r.git(["push", "-q", "origin", "main"])
        _ = await r.git(["checkout", "-q", "feature"])

        let resolver = ConflictResolver(claude: Self.writer("ok\n", into: "status"))
        let outcome = await resolver.resolve(r.job()) { _ in }
        guard case .pushed(_, let report) = outcome else { Issue.record("\(outcome)"); return }
        #expect(report.checks == "make test passed")
        #expect(await r.remoteFile("status") == "ok\n")
    }

    @Test func withoutPushingTheMergeStaysLocal() async throws {
        let r = try await Self.conflicting()
        let before = (await r.git(["rev-parse", "feature"], in: r.remote)).output
        let resolver = ConflictResolver(claude: Self.writer("HELLO, WORLD\n", into: "greet.txt"))
        let outcome = await resolver.resolve(r.job(pushes: false)) { _ in }
        guard case .committed = outcome else { Issue.record("\(outcome)"); return }
        #expect((await r.git(["rev-parse", "feature"], in: r.remote)).output == before)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIPLE_LIVE_CLAUDE"] == "1"))
    func theRealClaudeResolvesARealisticConflict() async throws {
        let r = try await Repo.make()
        try r.write("price.ts", """
        export function total(items: { price: number }[]): number {
          return items.reduce((sum, item) => sum + item.price, 0)
        }

        """)
        try r.write("Makefile", "test:\n\tgrep -q 'discount' price.ts && grep -q 'Math.round' price.ts\n")
        await r.commit("base")
        _ = await r.git(["push", "-q", "origin", "main"])
        _ = await r.git(["checkout", "-qb", "feature"])
        try r.write("price.ts", """
        export function total(items: { price: number }[], discount = 0): number {
          const sum = items.reduce((sum, item) => sum + item.price, 0)
          return sum - sum * discount
        }

        """)
        try r.write("Makefile", "test:\n\tgrep -q 'discount' price.ts\n")
        await r.commit("feat: a discount on the total")
        _ = await r.git(["push", "-q", "origin", "feature"])
        _ = await r.git(["checkout", "-q", "main"])
        try r.write("price.ts", """
        export function total(items: { price: number }[]): number {
          return Math.round(items.reduce((sum, item) => sum + item.price, 0) * 100) / 100
        }

        """)
        await r.commit("fix: round the total to cents")
        _ = await r.git(["push", "-q", "origin", "main"])
        _ = await r.git(["checkout", "-q", "feature"])

        let resolver = ConflictResolver(claude: ConflictResolver.liveClaude(model: "sonnet"))
        let outcome = await resolver.resolve(r.job()) { print("STEP", $0) }
        print("OUTCOME", outcome)
        guard case .pushed = outcome else { Issue.record("\(outcome)"); return }
        let merged = await r.remoteFile("price.ts")
        print("MERGED\n" + merged)
        #expect(merged.contains("discount"))
        #expect(merged.contains("Math.round"))
        #expect(!ConflictResolver.hasMarkers(merged))
    }

    static func clone(_ r: Repo, as name: String) async -> URL {
        let dir = r.root.appendingPathComponent(name)
        _ = await Shell.live.git(["clone", "-q", "-b", "feature", r.remote.path, dir.path], in: r.root)
        _ = await Shell.live.git(["config", "user.email", "o@example.invalid"], in: dir)
        _ = await Shell.live.git(["config", "user.name", "Other"], in: dir)
        return dir
    }

    @Test func whoeverPushesSecondSeesItAlreadyResolved() async throws {
        let r = try await Self.conflicting()
        let other = await Self.clone(r, as: "other")
        let resolver = ConflictResolver(claude: Self.writer("HELLO, WORLD\n", into: "greet.txt"))

        let firstOutcome = await resolver.resolve(r.job()) { _ in }
        guard case .pushed = firstOutcome else { Issue.record("first did not push"); return }
        let first = (await r.git(["rev-parse", "feature"], in: r.remote)).output.trimmingCharacters(in: .whitespacesAndNewlines)

        let job = ConflictResolver.Job(folder: other, title: "feat: greet louder", baseRef: "main", headRef: "feature",
                                       pushURL: r.remote.path, pushes: true)
        let outcome = await resolver.resolve(job) { _ in }
        #expect(outcome == .alreadyResolved(commit: first))
        #expect((await r.git(["rev-parse", "feature"], in: r.remote)).output.trimmingCharacters(in: .whitespacesAndNewlines) == first)
    }

    @Test func aPushFromTheAuthorMidwayIsKeptAndResolvedAgain() async throws {
        let r = try await Self.conflicting()
        let author = await Self.clone(r, as: "author")
        try "notes\n".write(to: author.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        _ = await Shell.live.git(["add", "-A"], in: author)
        _ = await Shell.live.git(["commit", "-qm", "author keeps going"], in: author)
        _ = await Shell.live.git(["push", "-q", "origin", "feature"], in: author)

        let steps = Lines()
        let resolver = ConflictResolver(claude: Self.writer("HELLO, WORLD\n", into: "greet.txt"))
        let outcome = await resolver.resolve(r.job()) { steps.add($0) }
        guard case .pushed = outcome else { Issue.record("\(outcome)"); return }
        #expect(steps.all.contains { $0.contains("starting again") })
        #expect(await r.remoteFile("notes.txt") == "notes\n")
        #expect(await r.remoteFile("greet.txt") == "HELLO, WORLD\n")
    }

    @Test func anotherDipleResolvingThePullRequestHoldsTheLock() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("diple-lock-\(UUID().uuidString)")
        let lock = ResolveLock.at(dir.appendingPathComponent("acme-api-1-resolve"))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "\(getppid())".write(to: lock.file, atomically: true, encoding: .utf8)
        #expect(!lock.acquire())
        try "999999".write(to: lock.file, atomically: true, encoding: .utf8)
        #expect(lock.acquire())
        lock.release()
        #expect(!FileManager.default.fileExists(atPath: lock.file.path))
    }

    @Test func gitsRejectionsAreRecognised() {
        #expect(ConflictResolver.isRejected(" ! [rejected]        HEAD -> feature (fetch first)"))
        #expect(ConflictResolver.isRejected("error: failed to push some refs\nhint: Updates were rejected because the tip of your current branch is behind (non-fast-forward)"))
        #expect(!ConflictResolver.isRejected("fatal: Authentication failed"))
    }

    @Test func markersAreFoundOnlyAtTheStartOfALine() {
        #expect(ConflictResolver.hasMarkers("a\n<<<<<<< HEAD\nb\n=======\nc\n>>>>>>> main\n"))
        #expect(!ConflictResolver.hasMarkers("let x = \"<<<<<<< not a marker\"\n// =======\n"))
    }

    @Test func aForkIsPushedToItsOwnRepository() {
        #expect(ConflictResolver.pushURL(origin: "git@github.com:chagas42/diple.git", repo: "chagas42/diple",
                                         headRepo: "danilofuchs/diple") == "git@github.com:danilofuchs/diple.git")
        #expect(ConflictResolver.pushURL(origin: "https://github.com/chagas42/diple", repo: "chagas42/diple",
                                         headRepo: "chagas42/diple") == "https://github.com/chagas42/diple")
    }

    @Test func theTestCommandComesFromTheProject() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("diple-detect-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(TestCommand.detect(in: dir) == nil)
        try #"{"scripts":{"test":"vitest run"}}"#.write(to: dir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "".write(to: dir.appendingPathComponent("pnpm-lock.yaml"), atomically: true, encoding: .utf8)
        let pnpm = TestCommand.detect(in: dir)
        #expect(pnpm?.label == "pnpm test")
        #expect(pnpm?.steps.first?.arguments == ["install", "--frozen-lockfile"])
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func add() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [String] = []
    func add(_ s: String) { lock.lock(); list.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return list }
}
