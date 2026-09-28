import Foundation
import os

struct ErrorReport: Sendable, Equatable {
    enum Operation: String, Sendable, CaseIterable {
        case refresh
        case loadRepos = "load_repos"
        case repoPRs = "repo_prs"
        case loadTab = "load_tab"
        case postFinding = "post_finding"
        case reply
        case resolve
        case aiReview = "ai_review"
        case mapDiff = "map_diff"
        case mapEnrich = "map_enrich"
    }

    enum SinceLastSync: String, Sendable {
        case never
        case under1m = "lt_1m"
        case under10m = "lt_10m"
        case under1h = "lt_1h"
        case longer = "gte_1h"

        init(_ last: Date?, now: Date = Date()) {
            guard let last else { self = .never; return }
            switch now.timeIntervalSince(last) {
            case ..<60:   self = .under1m
            case ..<600:  self = .under10m
            case ..<3600: self = .under1h
            default:      self = .longer
            }
        }
    }

    struct Context: Sendable, Equatable {
        var network = NetworkState()
        var failuresInRow = 0
        var sinceLastSync = SinceLastSync.never
    }

    static let knownHosts: Set<String> = ["api.github.com", "github.com", "us.i.posthog.com"]

    let operation: Operation
    let type: String
    let name: String
    let domain: String
    let code: Int
    let underlyingDomain: String?
    let underlyingCode: Int?
    let host: String?
    let isNetwork: Bool
    let context: Context

    init?(_ error: Error, in operation: Operation, context: Context = Context()) {
        guard !Self.isCancellation(error) else { return nil }
        let ns = error as NSError
        self.operation = operation
        self.context = context
        self.type = switch ns.domain {
        case NSURLErrorDomain:   "URLError"
        case NSCocoaErrorDomain: "CocoaError"
        default:                 String(describing: Swift.type(of: error))
        }
        self.domain = ns.domain
        if case ClientError.http(let status) = error {
            self.code = status
            self.name = "http_\(status)"
        } else {
            self.code = ns.code
            self.name = ns.domain == NSURLErrorDomain ? Self.urlName(ns.code) : "\(self.type).\(ns.code)"
        }
        let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError
        self.underlyingDomain = underlying?.domain
        self.underlyingCode = underlying?.code
        self.host = (ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.host.map {
            Self.knownHosts.contains($0) ? $0 : "other"
        }
        self.isNetwork = ns.domain == NSURLErrorDomain && Self.networkCodes.contains(ns.code)
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    var fingerprint: String { "\(operation.rawValue)/\(domain)/\(code)" }
    var level: String { isNetwork ? "warning" : "error" }

    private static let networkCodes: Set<Int> = [
        NSURLErrorTimedOut, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost,
        NSURLErrorNetworkConnectionLost, NSURLErrorDNSLookupFailed, NSURLErrorNotConnectedToInternet,
        NSURLErrorInternationalRoamingOff, NSURLErrorDataNotAllowed, NSURLErrorSecureConnectionFailed,
    ]

    static func urlName(_ code: Int) -> String {
        switch code {
        case NSURLErrorTimedOut:                 "timedOut"
        case NSURLErrorCannotFindHost:           "cannotFindHost"
        case NSURLErrorCannotConnectToHost:      "cannotConnectToHost"
        case NSURLErrorNetworkConnectionLost:    "networkConnectionLost"
        case NSURLErrorDNSLookupFailed:          "dnsLookupFailed"
        case NSURLErrorNotConnectedToInternet:   "notConnectedToInternet"
        case NSURLErrorInternationalRoamingOff:  "internationalRoamingOff"
        case NSURLErrorDataNotAllowed:           "dataNotAllowed"
        case NSURLErrorSecureConnectionFailed:   "secureConnectionFailed"
        case NSURLErrorBadServerResponse:        "badServerResponse"
        case NSURLErrorCannotParseResponse:      "cannotParseResponse"
        case NSURLErrorResourceUnavailable:      "resourceUnavailable"
        case NSURLErrorBadURL:                   "badURL"
        default:                                 "URLError.\(code)"
        }
    }

    private static let log = Logger(subsystem: "com.chagas42.diple", category: "errors")

    static func log(_ error: Error, in operation: Operation, report: ErrorReport?) {
        if let r = report {
            let net = r.context.network
            log.error("\(operation.rawValue, privacy: .public) failed: \(r.name, privacy: .public) (\(r.domain, privacy: .public) \(r.code, privacy: .public)) underlying \(r.underlyingDomain ?? "-", privacy: .public) \(r.underlyingCode ?? 0, privacy: .public) · network \(net.status, privacy: .public)/\(net.interface.rawValue, privacy: .public) · \(r.context.failuresInRow, privacy: .public) in a row — \(error.localizedDescription, privacy: .private)")
        } else {
            log.debug("\(operation.rawValue, privacy: .public) cancelled")
        }
    }
}
