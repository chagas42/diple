import Foundation
import Testing
@testable import Diple

@Suite struct GitDirTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("diple-gitdir-\(UUID().uuidString)").standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func folder(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to path: String) throws {
        try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }

    @Test func aCloneOwnsItsGitFolder() throws {
        let clone = try folder("app")
        _ = try folder("app/.git")
        #expect(GitDir.common(of: clone) == clone.appendingPathComponent(".git"))
    }

    @Test func aLinkedWorktreeWatchesTheMainClone() throws {
        _ = try folder("app/.git/worktrees/feature")
        let worktree = try folder("feature")
        try write("gitdir: \(root.path)/app/.git/worktrees/feature\n", to: "feature/.git")
        try write("../..\n", to: "app/.git/worktrees/feature/commondir")
        #expect(GitDir.common(of: worktree) == root.appendingPathComponent("app/.git"))
    }

    @Test func aRelativeGitFileIsReadFromTheCheckout() throws {
        _ = try folder("modules/lib")
        let checkout = try folder("app/lib")
        try write("gitdir: ../../modules/lib\n", to: "app/lib/.git")
        #expect(GitDir.common(of: checkout) == root.appendingPathComponent("modules/lib"))
    }

    @Test func aFolderWithoutGitIsSkipped() throws {
        #expect(GitDir.common(of: try folder("plain")) == nil)
    }

    @Test func aGitFileWithoutPointerIsSkipped() throws {
        let checkout = try folder("broken")
        try write("not a pointer\n", to: "broken/.git")
        #expect(GitDir.common(of: checkout) == nil)
    }
}

@Suite struct RemoteRefsTests {
    static let root = "/Users/me/dev/app/.git"

    @Test(arguments: [
        ("/Users/me/dev/app/.git/refs/remotes/origin/feature", RemoteRefs.Change.branch(RemoteBranch(remote: "origin", branch: "feature"))),
        ("/Users/me/dev/app/.git/refs/remotes/fork/danilo/fix-notch", .branch(RemoteBranch(remote: "fork", branch: "danilo/fix-notch"))),
        ("/Users/me/dev/app/.git/logs/refs/remotes/origin/main", .branch(RemoteBranch(remote: "origin", branch: "main"))),
        ("/Users/me/dev/app/.git/packed-refs", .packed),
    ])
    func counts(path: String, expected: RemoteRefs.Change) {
        #expect(RemoteRefs.change(at: path, under: Self.root) == expected)
    }

    @Test(arguments: [
        "/Users/me/dev/app/.git/refs/remotes/origin/feature.lock",
        "/Users/me/dev/app/.git/packed-refs.lock",
        "/Users/me/dev/app/.git/refs/remotes/origin/HEAD",
        "/Users/me/dev/app/.git/refs/heads/feature",
        "/Users/me/dev/app/.git/logs/HEAD",
        "/Users/me/dev/app/.git/logs/refs/heads/feature",
        "/Users/me/dev/app/.git/FETCH_HEAD",
        "/Users/me/dev/app/.git/objects/ab/cdef",
        "/Users/me/dev/other/.git/refs/remotes/origin/main",
        "/Users/me/dev/app/.gitx/refs/remotes/origin/main",
    ])
    func ignores(path: String) {
        #expect(RemoteRefs.change(at: path, under: Self.root) == nil)
    }

    @Test func packedRefsReportOnlyRemoteBranchesThatMoved() {
        let before = RemoteRefs.packed("""
        # pack-refs with: peeled fully-peeled sorted
        aaa refs/heads/main
        bbb refs/remotes/origin/main
        ccc refs/remotes/origin/feature
        ddd refs/remotes/origin/gone
        ^eee
        """)
        let after = RemoteRefs.packed("""
        aaa refs/heads/main
        bbb refs/remotes/origin/main
        fff refs/remotes/origin/feature
        ggg refs/remotes/fork/new
        """)
        #expect(RemoteRefs.moved(from: before, to: after) == [
            RemoteBranch(remote: "origin", branch: "feature"),
            RemoteBranch(remote: "fork", branch: "new"),
        ])
    }

    @Test(arguments: [
        ("0000 1111 Me <me@x> 1790000000 -0300\tupdate by push", true),
        ("1111 2222 Me <me@x> 1790000000 -0300\tfetch: fast-forward", false),
        ("1111 2222 Me <me@x> 1790000000 -0300\tfetch origin: storing head", false),
        ("", false),
    ])
    func aPushIsToldFromAFetchByTheReflog(line: String, pushed: Bool) {
        #expect(RemoteRefs.pushed(lastReflogLine: line) == pushed)
    }

    @Test func theRemoteHeadNamesTheDefaultBranch() {
        #expect(RemoteRefs.defaultBranches(remoteHead: "ref: refs/remotes/origin/develop") == ["develop"])
        #expect(RemoteRefs.defaultBranches(remoteHead: nil) == ["main", "master"])
    }
}

@Suite struct GitRemoteTests {
    static let config = """
    [core]
    \tbare = false
    [remote "origin"]
    \turl = https://github.com/chagas42/diple.git
    \tfetch = +refs/heads/*:refs/remotes/origin/*
    [remote "fork"]
    \turl = git@github.com:danilofuchs/diple.git
    [branch "main"]
    \tremote = origin
    """

    @Test func eachRemoteHasItsOwnURL() {
        #expect(GitRemote.url(of: "origin", inConfig: Self.config) == "https://github.com/chagas42/diple.git")
        #expect(GitRemote.url(of: "fork", inConfig: Self.config) == "git@github.com:danilofuchs/diple.git")
        #expect(GitRemote.url(of: "upstream", inConfig: Self.config) == nil)
    }

    @Test(arguments: [
        ("https://github.com/chagas42/diple.git", "chagas42"),
        ("git@github.com:danilofuchs/diple.git", "danilofuchs"),
        ("ssh://git@github.com/acme/api", "acme"),
        ("https://gitlab.com/acme/api.git", nil),
        ("/Users/me/remote.git", nil),
    ] as [(String, String?)])
    func ownerComesFromAGitHubURL(url: String, owner: String?) {
        #expect(GitRemote.gitHubOwner(of: url) == owner)
    }
}

@Suite struct PushRuleTests {
    static let repos = ["chagas42/diple", "danilofuchs/diple"]

    private func decide(
        _ branch: String = "feature", pushed: Bool = true, hasPR: Bool = false,
        owner: String? = "danilofuchs", repos: [String] = repos
    ) -> PushRule {
        PushRule.decide(
            branch: branch, pushed: pushed, defaultBranches: ["main"],
            hasPR: hasPR, headOwner: owner, repos: repos
        )
    }

    @Test func aPushToABranchWithAPRSyncsTwice() {
        #expect(decide(hasPR: true) == .syncTwice)
    }

    @Test func aPushToTheDefaultBranchSyncsOnce() {
        #expect(decide("main") == .syncOnce)
        #expect(decide("main", hasPR: true) == .syncOnce)
    }

    @Test func aPushToANewBranchWatchesForThePRUpstream() {
        #expect(decide() == .watchForPR(repo: "chagas42/diple", head: "danilofuchs:feature"))
    }

    @Test func aPushInsideOneRepoWatchesThatRepo() {
        #expect(decide(owner: "acme", repos: ["acme/api"]) == .watchForPR(repo: "acme/api", head: "acme:feature"))
    }

    @Test func aRemoteOutsideGitHubIsLeftAlone() {
        #expect(decide(owner: nil) == .ignore)
    }

    @Test func aFetchSyncsOnlyWhenItMovedAKnownPR() {
        #expect(decide(pushed: false, hasPR: true) == .syncOnce)
        #expect(decide(pushed: false) == .ignore)
        #expect(decide("main", pushed: false) == .ignore)
    }
}

@Suite struct PushScheduleTests {
    static let t0 = FakeWorld.epoch

    private func at(_ seconds: TimeInterval) -> Date { Self.t0.addingTimeInterval(seconds) }

    private func fire(_ s: inout PushSchedule, _ now: Date) -> Bool { s.due(at: now) }

    @Test func aPushToAPRSyncsAfterSettlingThenAgainForGitHub() {
        var s = PushSchedule()
        s.signal(at: at(0), twice: true)
        #expect(s.next == at(3))
        #expect(!fire(&s, at(2)))
        #expect(fire(&s, at(3)))
        #expect(s.next == at(15))
        #expect(!fire(&s, at(10)))
        #expect(fire(&s, at(15)))
        #expect(s.next == nil)
    }

    @Test func aSyncOnceHasNoFollowUp() {
        var s = PushSchedule()
        s.signal(at: at(0), twice: false)
        #expect(fire(&s, at(3)))
        #expect(s.next == nil)
    }

    @Test func aBurstOfRefUpdatesIsOneSync() {
        var s = PushSchedule()
        s.signal(at: at(0), twice: false)
        s.signal(at: at(0.5), twice: true)
        s.signal(at: at(1.5), twice: false)
        #expect(s.next == at(3))
        #expect(fire(&s, at(3)))
        #expect(s.next == at(15))
    }

    @Test func syncsAfterAPushAreAtLeastTenSecondsApart() {
        var s = PushSchedule()
        s.signal(at: at(0), twice: true)
        #expect(fire(&s, at(3)))
        s.signal(at: at(4), twice: true)
        #expect(s.next == at(13))
        #expect(!fire(&s, at(7)))
        #expect(fire(&s, at(13)))
        #expect(s.next == at(25))
    }

    @Test func resetForgetsWhatWasPending() {
        var s = PushSchedule()
        s.signal(at: at(0), twice: true)
        s.reset()
        #expect(s.next == nil)
        #expect(!fire(&s, at(100)))
    }
}

@Suite struct PRWatchesTests {
    static let t0 = FakeWorld.epoch

    private func at(_ seconds: TimeInterval) -> Date { Self.t0.addingTimeInterval(seconds) }

    @Test func checksBackOffThenSettleOnAMinute() {
        var w = PRWatches()
        w.start(repo: "acme/api", head: "acme:feature", at: at(0))
        var times: [TimeInterval] = []
        while let next = w.next {
            times.append(next.timeIntervalSince(Self.t0))
            w.checked("acme/api acme:feature", at: next, found: false, etag: "\"x\"")
        }
        #expect(Array(times.prefix(5)) == [10, 30, 60, 120, 180])
        #expect(times.last! <= PRWatches.window)
        #expect(times.count == 17)
    }

    @Test func findingThePRStopsWatching() {
        var w = PRWatches()
        w.start(repo: "acme/api", head: "acme:feature", at: at(0))
        w.checked("acme/api acme:feature", at: at(10), found: true, etag: nil)
        #expect(w.next == nil)
    }

    @Test func theETagIsKeptAcrossUnchangedAnswers() {
        var w = PRWatches()
        w.start(repo: "acme/api", head: "acme:feature", at: at(0))
        w.checked("acme/api acme:feature", at: at(10), found: false, etag: "\"a\"")
        w.checked("acme/api acme:feature", at: at(30), found: false, etag: nil)
        #expect(w.watches.first?.etag == "\"a\"")
    }

    @Test func anotherPushToTheBranchStartsTheWindowOver() {
        var w = PRWatches()
        w.start(repo: "acme/api", head: "acme:feature", at: at(0))
        w.checked("acme/api acme:feature", at: at(10), found: false, etag: nil)
        w.start(repo: "acme/api", head: "acme:feature", at: at(400))
        #expect(w.watches.count == 1)
        #expect(w.next == at(410))
    }

    @Test func atMostFiveBranchesAreWatchedAndTheOldestGoes() {
        var w = PRWatches()
        for i in 0..<6 { w.start(repo: "acme/api", head: "acme:b\(i)", at: at(Double(i))) }
        #expect(w.watches.map(\.head) == ["acme:b1", "acme:b2", "acme:b3", "acme:b4", "acme:b5"])
    }
}

@Suite struct PullLookupTests {
    @Test func theHeadIsEncodedForTheQuery() {
        #expect(PullLookup.path(repo: "acme/api", head: "acme:fix/a+b")
            == "repos/acme/api/pulls?head=acme:fix/a%2Bb&state=open&per_page=1")
    }

    @Test func answersMapToWhatTheWatchNeeds() {
        #expect(PullLookup.result(status: 304, body: Data(), etag: nil) == .unchanged)
        #expect(PullLookup.result(status: 200, body: Data("[]".utf8), etag: "\"a\"") == .none(etag: "\"a\""))
        #expect(PullLookup.result(status: 200, body: Data("[{\"number\":1}]".utf8), etag: "\"b\"") == .opened(etag: "\"b\""))
        #expect(PullLookup.result(status: 404, body: Data(), etag: nil) == nil)
    }
}
