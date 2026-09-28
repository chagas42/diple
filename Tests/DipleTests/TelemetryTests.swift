import Foundation
import Testing
@testable import Diple

@Suite struct TelemetryTests {
    static let ok = StubTransport { _ in .init(status: 200, body: Data("{\"status\":1}".utf8)) }

    static func make(
        _ transport: StubTransport = StubTransport { _ in .init(status: 200) },
        key: String? = "phc_test",
        allowed: Bool = true,
        flushEvery: Duration = .seconds(60)
    ) -> Telemetry {
        var c = Telemetry.Config()
        c.key = key
        c.allowed = allowed
        c.flushEvery = flushEvery
        let t = Telemetry(config: c, transport: transport)
        t.configure(installId: "install-1", consent: true, common: ["app_version": .text("9.9.9")])
        return t
    }

    static func events(in body: Data) -> [[String: Any]] {
        let o = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
        return o["batch"] as! [[String: Any]]
    }

    @Test func captureIsCheapAndNeverTouchesTheNetworkOnTheCallingThread() {
        let stub = StubTransport { _ in .init(status: 200) }
        var c = Telemetry.Config()
        c.key = "phc_test"
        c.batchSize = 100_000
        c.capacity = 100_000
        let t = Telemetry(config: c, transport: stub)
        t.configure(installId: "i", consent: true, common: [:])
        let start = ContinuousClock.now
        for _ in 0..<10_000 { t.capture(.findingPosted) }
        let elapsed = start.duration(to: .now)
        #expect(elapsed < .milliseconds(250))
        #expect(stub.queries.isEmpty)
        #expect(t.pendingCount == 10_000)
    }

    @Test func oneEventWaitsForTheTimer() async throws {
        let stub = StubTransport { _ in .init(status: 200) }
        let t = Self.make(stub)
        t.capture(.findingPosted)
        try await Task.sleep(for: .milliseconds(150))
        #expect(stub.bodies.isEmpty)
        #expect(t.pendingCount == 1)
    }

    @Test func aFullBatchIsSentAtOnceAndOffTheMainThread() async throws {
        let stub = StubTransport { _ in .init(status: 200) }
        let t = Self.make(stub)
        for _ in 0..<25 { t.capture(.findingPosted) }
        let deadline = ContinuousClock.now + .seconds(5)
        while stub.bodies.isEmpty, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        await t.flush()
        let sent = stub.bodies.map { Self.events(in: $0).count }.reduce(0, +)
        #expect(sent == 25)
        #expect((1...2).contains(stub.bodies.count))
        #expect(stub.requestsOnMainThread == 0)
    }

    @Test func theTimerFlushesOnItsOwn() async throws {
        let stub = StubTransport { _ in .init(status: 200) }
        let t = Self.make(stub, flushEvery: .milliseconds(100))
        t.capture(.findingPosted)
        let deadline = ContinuousClock.now + .seconds(10)
        while stub.bodies.isEmpty, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(stub.bodies.count == 1)
    }

    @Test func optingOutDropsTheQueueAndSendsNothing() async {
        let stub = StubTransport { _ in .init(status: 200) }
        let t = Self.make(stub)
        t.capture(.findingPosted)
        t.setConsent(false)
        #expect(t.pendingCount == 0)
        t.capture(.findingPosted)
        await t.flush()
        #expect(stub.bodies.isEmpty)
        #expect(!t.isActive)
    }

    @Test(arguments: [(String?.none, true), ("phc_test", false), ("", true)])
    func withoutAKeyOrPermissionNothingIsSent(key: String?, allowed: Bool) async {
        let stub = StubTransport { _ in .init(status: 200) }
        let t = Self.make(stub, key: key, allowed: allowed)
        t.capture(.findingPosted)
        await t.flush()
        #expect(stub.bodies.isEmpty)
        #expect(!t.isActive)
    }

    @Test func doNotTrackAndSpecialModesDisableIt() {
        let info: [String: Any] = ["DiplePostHogKey": "phc_live"]
        #expect(!Telemetry.Config.make(info: info, env: ["DO_NOT_TRACK": "1"], arguments: ["Diple"]).allowed)
        #expect(!Telemetry.Config.make(info: info, env: [:], arguments: ["Diple", "--demo"]).allowed)
        #expect(!Telemetry.Config.make(info: info, env: [:], arguments: ["Diple", "--bench", "refresh"]).allowed)
        let live = Telemetry.Config.make(info: info, env: [:], arguments: ["Diple"])
        #expect(live.allowed)
        #expect(live.key == "phc_live")
        #expect(Telemetry.Config.make(info: [:], env: [:], arguments: ["Diple"]).key == nil)
    }

    @Test func aFailedSendIsRetriedWithTheSameIds() async {
        let failing = StubTransport { _ in .init(status: 503) }
        let t = Self.make(failing)
        t.capture(.findingPosted)
        t.capture(.prOpened(source: .notch))
        await t.flush()
        #expect(t.pendingCount == 2)
        failing.respond { _ in .init(status: 200) }
        await t.flush()
        #expect(t.pendingCount == 0)
        let first = Self.events(in: failing.bodies[0]).map { $0["uuid"] as! String }
        let second = Self.events(in: failing.bodies[1]).map { $0["uuid"] as! String }
        #expect(first == second)
    }

    @Test func aRejectedBatchIsDroppedNotRetriedForever() async {
        let rejecting = StubTransport { _ in .init(status: 401) }
        let t = Self.make(rejecting)
        t.capture(.findingPosted)
        await t.flush()
        #expect(t.pendingCount == 0)
    }

    @Test func theQueueNeverGrowsPastItsCapacity() {
        var c = Telemetry.Config()
        c.key = "phc_test"
        c.batchSize = 10_000
        c.capacity = 50
        let t = Telemetry(config: c, transport: StubTransport { _ in .init(status: 200) })
        t.configure(installId: "i", consent: true, common: [:])
        for _ in 0..<500 { t.capture(.findingPosted) }
        #expect(t.pendingCount == 50)
    }

    @Test func onlyAllowlistedPropertiesLeaveTheMachine() async throws {
        let stub = StubTransport { _ in .init(status: 200) }
        let t = Self.make(stub)
        let every: [TelemetryEvent] = [
            .appActive(needsYou: 3, mine: 4, toReview: 1),
            .aiReviewStarted(deep: true),
            .aiReviewFinished(outcome: .done, findings: 2, threadsJudged: 1, deep: true, duration: .init(seconds: 95)),
            .mapBuilt(outcome: .failed, prsInStack: 3, duration: .init(seconds: 10)),
            .replySent(source: .notification),
            .threadResolved(source: .window),
            .findingPosted,
            .prOpened(source: .notch),
            .notificationShown(kind: .checkFailed),
        ]
        every.forEach { t.capture($0) }
        await t.flush()
        let events = Self.events(in: try #require(stub.bodies.first))
        let allowed: Set<String> = [
            "app_version", "$lib", "$process_person_profile",
            "needs_you", "mine", "to_review", "deep", "outcome", "findings", "threads_judged",
            "duration", "prs_in_stack", "source", "kind",
        ]
        for e in events {
            let props = e["properties"] as! [String: Any]
            #expect(Set(props.keys).isSubset(of: allowed))
            #expect(e["distinct_id"] as? String == "install-1")
            #expect(props["$process_person_profile"] as? Bool == false)
        }
        #expect(events.map { $0["event"] as! String } == every.map(\.name))
        let payload = String(decoding: try #require(stub.bodies.first), as: UTF8.self)
        #expect(payload.contains("\"api_key\":\"phc_test\""))
        #expect(!payload.contains("acme/"))
    }

    @Test func durationsAreBucketed() {
        #expect(TelemetryEvent.DurationBucket(seconds: 5) == .under30s)
        #expect(TelemetryEvent.DurationBucket(seconds: 90) == .under2m)
        #expect(TelemetryEvent.DurationBucket(seconds: 200) == .under5m)
        #expect(TelemetryEvent.DurationBucket(seconds: 900) == .longer)
    }

    @Test func resettingTheIdForgetsWhatWasQueued() {
        let t = Self.make()
        t.capture(.findingPosted)
        t.setInstallId("install-2")
        #expect(t.pendingCount == 0)
    }
}

@MainActor
@Suite struct UsageConsentTests {
    @Test func theInstallIdIsCreatedOnceAndSurvivesAReload() {
        let dir = StoreDiffTests.tempDirectory()
        let store = Store(directory: dir, metrics: Metrics())
        let id = store.ensureInstallId()
        #expect(!id.isEmpty)
        #expect(store.ensureInstallId() == id)
        store.flushNow()
        #expect(Store(directory: dir, metrics: Metrics()).state.installId == id)
    }

    @Test func resettingGivesANewId() {
        let store = Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        let id = store.ensureInstallId()
        #expect(store.resetInstallId() != id)
    }

    @Test func anOlderStateDecodesWithSharingOnAndNoId() throws {
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(StoredState())) as! [String: Any]
        legacy.removeValue(forKey: "installId")
        legacy.removeValue(forKey: "usageNoticeSeen")
        var settings = legacy["settings"] as! [String: Any]
        settings.removeValue(forKey: "shareUsage")
        legacy["settings"] = settings
        let d = try JSONDecoder().decode(StoredState.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(d.settings.shareUsage)
        #expect(d.installId == nil)
        #expect(!d.usageNoticeSeen)
    }

    @Test func theActiveDayIsCountedOncePerDay() {
        let store = Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        #expect(store.markActive(on: "2026-09-28"))
        #expect(!store.markActive(on: "2026-09-28"))
        #expect(store.markActive(on: "2026-09-29"))
    }

    @Test func turningSharingOffInSettingsStopsTheClient() {
        var c = Telemetry.Config()
        c.key = "phc_test"
        let telemetry = Telemetry(config: c, transport: StubTransport { _ in .init(status: 200) })
        let model = AppModel(
            client: GitHubClient(transport: StubTransport(body: Data()), tokens: CountingTokens(), metrics: Metrics()),
            store: Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics()),
            telemetry: telemetry
        )
        model.startTelemetry()
        #expect(telemetry.isActive)
        #expect(model.usageNoticeVisible)
        model.settings.shareUsage = false
        #expect(!telemetry.isActive)
        model.dismissUsageNotice()
        #expect(!model.usageNoticeVisible)
    }
}
