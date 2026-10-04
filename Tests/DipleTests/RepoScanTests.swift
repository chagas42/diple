import Testing
import Foundation
@testable import Diple

struct RemoteURLTests {
    @Test func sshAndHttpsFormsGiveOwnerAndName() {
        #expect(RepoScan.repo(fromRemote: "git@github.com:chagas42/diple.git") == "chagas42/diple")
        #expect(RepoScan.repo(fromRemote: "git@github.com:chagas42/diple") == "chagas42/diple")
        #expect(RepoScan.repo(fromRemote: "https://github.com/chagas42/diple.git") == "chagas42/diple")
        #expect(RepoScan.repo(fromRemote: "https://github.com/chagas42/diple") == "chagas42/diple")
        #expect(RepoScan.repo(fromRemote: "https://github.com/chagas42/diple/") == "chagas42/diple")
        #expect(RepoScan.repo(fromRemote: "https://token@github.com/chagas42/diple.git") == "chagas42/diple")
        #expect(RepoScan.repo(fromRemote: "ssh://git@github.com/chagas42/diple.git") == "chagas42/diple")
        #expect(RepoScan.repo(fromRemote: "ssh://git@github.com:22/chagas42/diple.git") == "chagas42/diple")
        #expect(RepoScan.repo(fromRemote: "git://github.com/chagas42/diple.git") == "chagas42/diple")
        #expect(RepoScan.repo(fromRemote: "https://www.github.com/chagas42/diple") == "chagas42/diple")
    }

    @Test func otherHostsAndShapesAreNotGitHubRepos() {
        #expect(RepoScan.repo(fromRemote: "git@gitlab.com:chagas42/diple.git") == nil)
        #expect(RepoScan.repo(fromRemote: "https://github.com.evil.io/chagas42/diple") == nil)
        #expect(RepoScan.repo(fromRemote: "https://github.com/chagas42") == nil)
        #expect(RepoScan.repo(fromRemote: "https://github.com/chagas42/diple/pull/3") == nil)
        #expect(RepoScan.repo(fromRemote: "/Users/me/dev/diple") == nil)
        #expect(RepoScan.repo(fromRemote: "") == nil)
    }

    @Test func remotesComeFromTheConfigWithOriginFirst() {
        let config = """
        [core]
        \trepositoryformatversion = 0
        \turl = not-a-remote
        [remote "upstream"]
        \turl = git@github.com:chagas42/diple.git
        \tfetch = +refs/heads/*:refs/remotes/upstream/*
        [remote "origin"]
        \turl = https://github.com/me/diple.git
        [branch "main"]
        \tremote = origin
        """
        #expect(RepoScan.remotes(config: config) == [
            .init(name: "origin", url: "https://github.com/me/diple.git"),
            .init(name: "upstream", url: "git@github.com:chagas42/diple.git"),
        ])
    }
}

struct RepoScanTests {
    let base: URL

    init() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("diple-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    private func clone(_ path: String, remotes: [String: String]) throws {
        let gitDir = base.appendingPathComponent(path).appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        let config = remotes.sorted { $0.key < $1.key }
            .map { "[remote \"\($0.key)\"]\n\turl = \($0.value)\n" }
            .joined()
        try config.write(to: gitDir.appendingPathComponent("config"), atomically: true, encoding: .utf8)
    }

    private func path(_ relative: String) -> String {
        base.appendingPathComponent(relative).resolvingSymlinksInPath().path
    }

    private func resolved(_ path: String?) -> String? {
        path.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
    }

    @Test func findsClonesByTheirRemotes() throws {
        try clone("work/api", remotes: ["origin": "git@github.com:Acme/API.git"])
        try clone("diple", remotes: ["origin": "https://github.com/me/diple", "upstream": "git@github.com:chagas42/diple.git"])
        let found = RepoScan.scan([base])
        #expect(resolved(found["acme/api"]) == path("work/api"))
        #expect(resolved(found["me/diple"]) == path("diple"))
        #expect(resolved(found["chagas42/diple"]) == path("diple"))
    }

    @Test func skipsDependenciesHiddenFoldersAndWhatIsTooDeep() throws {
        try clone("web/node_modules/left-pad", remotes: ["origin": "git@github.com:a/left-pad.git"])
        try clone(".cache/tool", remotes: ["origin": "git@github.com:a/tool.git"])
        try clone("a/b/c/d/e", remotes: ["origin": "git@github.com:a/deep.git"])
        try clone("a/b/c/near", remotes: ["origin": "git@github.com:a/near.git"])
        let found = RepoScan.scan([base])
        #expect(found["a/left-pad"] == nil)
        #expect(found["a/tool"] == nil)
        #expect(found["a/deep"] == nil)
        #expect(resolved(found["a/near"]) == path("a/b/c/near"))
    }

    @Test func doesNotLookInsideAClone() throws {
        try clone("app", remotes: ["origin": "git@github.com:a/app.git"])
        try clone("app/vendored", remotes: ["origin": "git@github.com:a/vendored.git"])
        let found = RepoScan.scan([base])
        #expect(resolved(found["a/app"]) == path("app"))
        #expect(found["a/vendored"] == nil)
    }

    @Test func anOriginBeatsAnotherClonesUpstream() throws {
        try clone("a-fork", remotes: ["origin": "git@github.com:me/lib.git", "upstream": "git@github.com:team/lib.git"])
        try clone("z-lib", remotes: ["origin": "git@github.com:team/lib.git"])
        #expect(resolved(RepoScan.scan([base])["team/lib"]) == path("z-lib"))
    }

    @Test func aLinkedWorktreeReadsItsMainConfig() throws {
        try clone("main", remotes: ["origin": "git@github.com:a/main.git"])
        let worktreeGit = base.appendingPathComponent("main/.git/worktrees/feature")
        try FileManager.default.createDirectory(at: worktreeGit, withIntermediateDirectories: true)
        try "../..\n".write(to: worktreeGit.appendingPathComponent("commondir"), atomically: true, encoding: .utf8)
        let checkout = base.appendingPathComponent("other/feature")
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        try "gitdir: \(worktreeGit.path)\n".write(to: checkout.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        let config = RepoScan.configFile(checkout.appendingPathComponent(".git"))
        #expect(resolved(config?.path) == path("main/.git/config"))
    }

    @Test func foldersMergeAndTheShallowerCloneWinsAcrossThem() throws {
        try clone("dev/diple", remotes: ["origin": "git@github.com:chagas42/diple.git"])
        try clone("work/api", remotes: ["origin": "git@github.com:acme/api.git"])
        try clone("work/old/diple", remotes: ["origin": "git@github.com:chagas42/diple.git"])
        let dev = base.appendingPathComponent("dev")
        let work = base.appendingPathComponent("work")
        let found = RepoScan.scan([work, dev])
        #expect(resolved(found["acme/api"]) == path("work/api"))
        #expect(resolved(found["chagas42/diple"]) == path("dev/diple"))
        #expect(RepoScan.found(in: dev.path, scanned: found) == 1)
        #expect(RepoScan.found(in: work.path, scanned: found) == 1)
    }

    @Test func aTieBetweenFoldersGoesToTheOneListedFirst() throws {
        try clone("dev/diple", remotes: ["origin": "git@github.com:chagas42/diple.git"])
        try clone("work/diple", remotes: ["origin": "git@github.com:chagas42/diple.git"])
        let dev = base.appendingPathComponent("dev")
        let work = base.appendingPathComponent("work")
        #expect(resolved(RepoScan.scan([dev, work])["chagas42/diple"]) == path("dev/diple"))
        #expect(resolved(RepoScan.scan([work, dev])["chagas42/diple"]) == path("work/diple"))
    }

    @Test func removingAFolderDropsWhatOnlyItHeld() throws {
        try clone("dev/diple", remotes: ["origin": "git@github.com:chagas42/diple.git"])
        try clone("work/api", remotes: ["origin": "git@github.com:acme/api.git"])
        try clone("work/diple", remotes: ["origin": "git@github.com:chagas42/diple.git"])
        let dev = base.appendingPathComponent("dev")
        let work = base.appendingPathComponent("work")
        #expect(resolved(RepoScan.scan([work, dev])["chagas42/diple"]) == path("work/diple"))
        let left = RepoScan.scan([dev])
        #expect(left["acme/api"] == nil)
        #expect(resolved(left["chagas42/diple"]) == path("dev/diple"))
        #expect(RepoScan.scan([]).isEmpty)
    }

    @Test func aSingleSavedFolderBecomesTheFirstOfTheList() throws {
        let legacy = #"{"reposFolder": "/Users/me/dev", "scannedRepoPaths": {"a/b": "/Users/me/dev/b"}}"#
        let migrated = try JSONDecoder().decode(Settings.self, from: Data(legacy.utf8))
        #expect(migrated.reposFolders == ["/Users/me/dev"])
        #expect(migrated.scannedRepoPaths == ["a/b": "/Users/me/dev/b"])

        let current = #"{"reposFolders": ["/Users/me/dev", "/Users/me/work"], "reposFolder": "/old"}"#
        #expect(try JSONDecoder().decode(Settings.self, from: Data(current.utf8)).reposFolders
            == ["/Users/me/dev", "/Users/me/work"])
        #expect(try JSONDecoder().decode(Settings.self, from: Data("{}".utf8)).reposFolders.isEmpty)

        var settings = Settings()
        settings.reposFolders = ["/Users/me/dev", "/Users/me/work"]
        let roundTrip = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        #expect(roundTrip.reposFolders == settings.reposFolders)
    }

    @Test func aPathChosenByHandWinsAndCountsAsNotMatched() {
        let manual = ["acme/api": "/hand/picked"]
        let scanned = ["acme/api": "/scanned/api", "acme/web": "/scanned/web"]
        #expect(Worktree.localPath("acme/api", configured: manual, scanned: scanned)?.path == "/hand/picked")
        #expect(Worktree.localPath("Acme/Web", configured: manual, scanned: scanned)?.path == "/scanned/web")
        #expect(RepoScan.matched(["acme/api", "Acme/Web", "acme/other"], manual: manual, scanned: scanned) == 1)
    }
}
