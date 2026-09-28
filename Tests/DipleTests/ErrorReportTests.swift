import Foundation
import Testing
@testable import Diple

@Suite struct ErrorReportTests {
    struct Leaky: LocalizedError {
        var errorDescription: String? { "could not reach https://github.com/acme/secret-repo/pull/7" }
    }

    @Test func cancellationIsNotAnError() {
        #expect(ErrorReport(URLError(.cancelled), in: .refresh) == nil)
        #expect(ErrorReport(CancellationError(), in: .loadTab) == nil)
        #expect(ErrorReport(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled), in: .reply) == nil)
    }

    @Test func aReportCarriesTheOperationTypeDomainAndCode() throws {
        let r = try #require(ErrorReport(URLError(.timedOut), in: .refresh))
        #expect(r.type == "URLError")
        #expect(r.domain == NSURLErrorDomain)
        #expect(r.code == NSURLErrorTimedOut)
        #expect(r.fingerprint == "refresh/\(NSURLErrorDomain)/\(NSURLErrorTimedOut)")
    }

    @Test func anHTTPFailureIsCodedByItsStatus() throws {
        let r = try #require(ErrorReport(ClientError.http(502), in: .reply))
        #expect(r.code == 502)
        #expect(r.type == "ClientError")
    }

    @Test func theMessageNeverLeavesTheMachine() async throws {
        let stub = StubTransport { _ in .init(status: 200) }
        let t = TelemetryTests.make(stub)
        t.capture(.error(try #require(ErrorReport(Leaky(), in: .mapEnrich))))
        await t.flush()
        let body = try #require(stub.bodies.first)
        let payload = String(decoding: body, as: UTF8.self)
        #expect(!payload.contains("acme"))
        #expect(!payload.contains("github.com"))

        let event = try #require(TelemetryTests.events(in: body).first)
        #expect(event["event"] as? String == "$exception")
        let props = try #require(event["properties"] as? [String: Any])
        let list = try #require(props["$exception_list"] as? [[String: Any]])
        #expect(list.first?["type"] as? String == "Leaky")
        #expect((list.first?["mechanism"] as? [String: Any])?["handled"] as? Bool == true)
    }
}

@MainActor
@Suite struct RefreshErrorTests {
    static func model(failing code: URLError.Code) -> (AppModel, Telemetry) {
        var c = Telemetry.Config()
        c.key = "phc_test"
        c.batchSize = 1_000
        let telemetry = Telemetry(config: c, transport: StubTransport { _ in .init(status: 200) })
        telemetry.configure(installId: "i", consent: true, common: [:])
        let model = AppModel(
            client: GitHubClient(
                transport: StubTransport { _ in .init(failure: code) },
                tokens: CountingTokens(),
                metrics: Metrics()
            ),
            store: Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics()),
            telemetry: telemetry
        )
        return (model, telemetry)
    }

    @Test func aCancelledSyncShowsNothingAndDoesNotBackOff() async {
        let (model, telemetry) = Self.model(failing: .cancelled)
        await model.refresh()
        #expect(model.errorMessage == nil)
        #expect(model.failures == 0)
        #expect(telemetry.pendingCount == 0)
    }

    @Test func aFailedSyncIsShownCountedAndReported() async {
        let (model, telemetry) = Self.model(failing: .timedOut)
        await model.refresh()
        #expect(model.errorMessage != nil)
        #expect(model.failures == 1)
        #expect(telemetry.pendingCount == 1)
    }
}
