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

    let operation: Operation
    let type: String
    let domain: String
    let code: Int

    init?(_ error: Error, in operation: Operation) {
        guard !Self.isCancellation(error) else { return nil }
        let ns = error as NSError
        self.operation = operation
        self.type = switch ns.domain {
        case NSURLErrorDomain:   "URLError"
        case NSCocoaErrorDomain: "CocoaError"
        default:                 String(describing: Swift.type(of: error))
        }
        self.domain = ns.domain
        if case ClientError.http(let status) = error {
            self.code = status
        } else {
            self.code = ns.code
        }
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    var fingerprint: String { "\(operation.rawValue)/\(domain)/\(code)" }

    private static let log = Logger(subsystem: "com.chagas42.diple", category: "errors")

    static func log(_ error: Error, in operation: Operation, report: ErrorReport?) {
        if let r = report {
            log.error("\(operation.rawValue, privacy: .public) failed: \(r.type, privacy: .public) \(r.domain, privacy: .public) \(r.code, privacy: .public) — \(error.localizedDescription, privacy: .private)")
        } else {
            log.debug("\(operation.rawValue, privacy: .public) cancelled")
        }
    }
}
