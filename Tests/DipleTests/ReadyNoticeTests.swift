import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct ReadyNoticeTests {
    static let repo = "acme/watched"
    static let watchedAt = Date(timeIntervalSince1970: 1_790_000_000)

    static func pr(_ number: Int, draft: Bool, createdAt: Date, updatedAt: Date? = nil) -> PR {
        PR(id: "W\(number)", repo: repo, number: number, title: "Change \(number)",
           url: URL(string: "https://github.com/\(repo)/pull/\(number)")!,
           updatedAt: updatedAt ?? createdAt, createdAt: createdAt, draft: draft,
           author: "bea", authorAvatar: nil, isMine: false,
           headRef: "h", baseRef: "main", checks: .passing, approved: false,
           threads: [], lastComment: nil)
    }

    static func queue(_ watched: [PR]) -> Queue { Queue(viewer: "you", watched: watched) }

    static func store(_ state: StoredState? = nil) -> Store {
        var state = state ?? StoredState()
        if state.watching == nil {
            state.hasRunBefore = true
            state.watching = [repo]
            state.watchedSince = [repo: watchedAt]
        }
        let dir = StoreDiffTests.tempDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(state).write(to: dir.appendingPathComponent("state.json"))
        return Store(directory: dir, metrics: Metrics())
    }

    @Test func aDraftMarkedReadySaysSo() {
        let store = Self.store()
        let created = Self.watchedAt.addingTimeInterval(600)
        #expect(store.diff(Self.queue([Self.pr(1, draft: true, createdAt: created)]), meuLogin: "you").isEmpty)
        let events = store.diff(Self.queue([Self.pr(1, draft: false, createdAt: created, updatedAt: created.addingTimeInterval(60))]), meuLogin: "you")
        #expect(events.map(\.title) == ["bea marked a pull request ready for review"])
        #expect(events.first?.kind == .newPullRequest)
        #expect(store.state.unread.contains("\(Self.repo)#1"))
        #expect(store.diff(Self.queue([Self.pr(1, draft: false, createdAt: created, updatedAt: created.addingTimeInterval(60))]), meuLogin: "you").isEmpty)
    }

    @Test func aDraftOpenedBeforeWatchingStillSaysWhenItIsReady() {
        let store = Self.store()
        let created = Self.watchedAt.addingTimeInterval(-86_400)
        _ = store.diff(Self.queue([Self.pr(2, draft: true, createdAt: created)]), meuLogin: "you")
        let events = store.diff(Self.queue([Self.pr(2, draft: false, createdAt: created)]), meuLogin: "you")
        #expect(events.map(\.title) == ["bea marked a pull request ready for review"])
    }

    @Test func aPullRequestOpenedReadyIsStillOpened() {
        let store = Self.store()
        let events = store.diff(Self.queue([Self.pr(3, draft: false, createdAt: Self.watchedAt.addingTimeInterval(600))]), meuLogin: "you")
        #expect(events.map(\.title) == ["bea opened a pull request"])
    }

    @Test func aSnapshotFromBeforeDraftsWereSavedStaysQuiet() throws {
        let seen = Self.store()
        let created = Self.watchedAt.addingTimeInterval(600)
        _ = seen.diff(Self.queue([Self.pr(4, draft: true, createdAt: created)]), meuLogin: "you")
        var legacy = seen.state
        for k in legacy.prs.keys { legacy.prs[k]?.draft = nil }
        let store = Self.store(legacy)
        #expect(store.diff(Self.queue([Self.pr(4, draft: false, createdAt: created)]), meuLogin: "you").isEmpty)
    }

    @Test func anOlderSnapshotWithoutDraftStillDecodes() throws {
        let legacy = #"{"updatedAt":0,"checks":"passing","approved":false,"reviewRequested":false}"#
        let s = try JSONDecoder().decode(Snapshot.self, from: Data(legacy.utf8))
        #expect(s.draft == nil)
    }
}
