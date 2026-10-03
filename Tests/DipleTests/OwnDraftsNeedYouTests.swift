import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct OwnDraftsNeedYouTests {
    static func model(drafts: [String]) async -> AppModel {
        var world = FakeWorld.realistic()
        for id in drafts { world.update(id) { $0.draft = true } }
        let github = FakeGitHub(world)
        let model = AppModel(
            client: GitHubClient(transport: github.transport, tokens: CountingTokens(), metrics: Metrics()),
            store: Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        )
        model.preloadsTabs = false
        await model.refresh()
        return model
    }

    @Test func yourDraftsWaitOnYouUnderTheirOwnReason() async throws {
        let model = await Self.model(drafts: ["PR_0", "PR_20"])
        let keys = model.needsYou.map(\.key)
        #expect(keys.contains("acme/repo0#100"))
        #expect(!keys.contains("acme/repo0#120"))
        #expect(!keys.contains("acme/repo1#101"))
        let draft = try #require(model.queue.mine.first { $0.key == "acme/repo0#100" })
        #expect(model.needsReason(draft) == .yourDraft)
        #expect(model.needsReason(draft)?.label == "your draft")
        #expect(model.needsReason(draft)?.kind == nil)
        #expect(model.count == model.reviewing.count + 1)
        #expect(model.count(.needsYou) == model.count)
    }

    @Test func turningItOffLeavesThemInYourPRsOnly() async throws {
        let model = await Self.model(drafts: ["PR_0"])
        var changes = 0
        model.onCountChange = { changes += 1 }
        let before = model.count
        model.settings.draftsNeedYou = false
        #expect(changes == 1)
        #expect(model.count == before - 1)
        #expect(!model.needsYou.contains { $0.key == "acme/repo0#100" })
        #expect(model.prs(.mine).contains { $0.key == "acme/repo0#100" })
        let draft = try #require(model.queue.mine.first { $0.key == "acme/repo0#100" })
        #expect(model.needsReason(draft) == nil)
    }

    @Test func somethingNewOnYourDraftOutranksItBeingADraft() {
        let r = AppModel.NeedsReason.of("k", unread: ["k"], reasons: ["k": .repliedToYou], reviewRequested: false, yourDraft: true)
        #expect(r == .replied)
        #expect(AppModel.NeedsReason.of("k", unread: [], reasons: [:], reviewRequested: false, yourDraft: true) == .yourDraft)
    }

    @Test func anOlderSettingsFileTurnsItOn() throws {
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Settings())) as! [String: Any]
        legacy.removeValue(forKey: "draftsNeedYou")
        let decoded = try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.draftsNeedYou)
    }
}
