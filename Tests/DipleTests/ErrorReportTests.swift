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

@Suite struct ErrorDetailTests {
    static func offline(_ url: String) -> NSError {
        NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: [
            NSURLErrorFailingURLErrorKey: URL(string: url)!,
            NSUnderlyingErrorKey: NSError(domain: "kCFErrorDomainCFNetwork", code: -1009),
        ])
    }

    @Test func aNetworkErrorIsNamedAndAWarning() throws {
        let r = try #require(ErrorReport(Self.offline("https://api.github.com/graphql"), in: .refresh))
        #expect(r.name == "notConnectedToInternet")
        #expect(r.isNetwork)
        #expect(r.level == "warning")
        #expect(r.underlyingDomain == "kCFErrorDomainCFNetwork")
        #expect(r.underlyingCode == -1009)
        #expect(r.host == "api.github.com")
    }

    @Test func aHostThatIsNotOursIsOther() throws {
        let r = try #require(ErrorReport(Self.offline("https://acme.example/secret-repo"), in: .refresh))
        #expect(r.host == "other")
    }

    @Test func anHTTPFailureIsAnErrorNamedByItsStatus() throws {
        let r = try #require(ErrorReport(ClientError.http(502), in: .refresh))
        #expect(r.name == "http_502")
        #expect(!r.isNetwork)
        #expect(r.level == "error")
    }

    @Test func theTimeSinceTheLastSyncIsARange() {
        let now = Date()
        #expect(ErrorReport.SinceLastSync(nil, now: now) == .never)
        #expect(ErrorReport.SinceLastSync(now.addingTimeInterval(-30), now: now) == .under1m)
        #expect(ErrorReport.SinceLastSync(now.addingTimeInterval(-300), now: now) == .under10m)
        #expect(ErrorReport.SinceLastSync(now.addingTimeInterval(-7200), now: now) == .longer)
    }

    @Test func theEventCarriesTheNetworkAndNothingPrivate() async throws {
        let stub = StubTransport { _ in .init(status: 200) }
        let t = TelemetryTests.make(stub)
        var net = NetworkState()
        net.status = "satisfied"
        net.interface = .wifi
        let context = ErrorReport.Context(network: net, failuresInRow: 3, sinceLastSync: .under10m)
        t.capture(.error(try #require(ErrorReport(Self.offline("https://acme.example/secret-repo"), in: .refresh, context: context))))
        await t.flush()
        let body = try #require(stub.bodies.first)
        #expect(!String(decoding: body, as: UTF8.self).contains("acme"))
        let props = try #require(TelemetryTests.events(in: body).first?["properties"] as? [String: Any])
        #expect(props["network_interface"] as? String == "wifi")
        #expect(props["network_status"] as? String == "satisfied")
        #expect(props["failures_in_row"] as? Int == 3)
        #expect(props["since_last_sync"] as? String == "lt_10m")
        #expect(props["$exception_level"] as? String == "warning")
        let list = try #require(props["$exception_list"] as? [[String: Any]])
        #expect(list.first?["value"] as? String == "refresh: notConnectedToInternet")
    }
}
