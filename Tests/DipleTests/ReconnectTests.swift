import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct ReconnectTests {
    final class Network: @unchecked Sendable {
        private let lock = NSLock()
        private var down = false
        var isDown: Bool {
            get { lock.withLock { down } }
            set { lock.withLock { down = newValue } }
        }
    }

    @Test func comingBackMidSyncStillSyncs() async throws {
        let github = FakeGitHub(.realistic())
        let network = Network()
        github.transport.respond { q in
            network.isDown
                ? StubTransport.Reply(delay: .milliseconds(300), failure: .notConnectedToInternet)
                : github.reply(q)
        }
        let model = AppModel(
            client: GitHubClient(transport: github.transport, tokens: CachedTokenSource(CountingTokens()), retryDelays: []),
            store: Store(directory: StoreDiffTests.tempDirectory())
        )
        await model.refresh()
        #expect(model.errorMessage == nil)

        network.isDown = true
        let failing = Task { await model.refresh(full: true) }
        try await Task.sleep(for: .milliseconds(50))
        network.isDown = false
        model.setOnline(false)
        model.setOnline(true)

        await failing.value
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.errorMessage == nil)
        #expect(!model.loading)
    }
}
