import Foundation

enum PRState: String, Codable, Sendable {
    case open, merged, closed

    init(github: String?) {
        switch github {
        case "MERGED": self = .merged
        case "CLOSED": self = .closed
        default: self = .open
        }
    }

    var isFinal: Bool { self != .open }
}

struct TrackMark: Codable, Sendable, Equatable {
    var updatedAt: Date
    var state: PRState
    var head: String?
    var checks: CheckState
    var approvals: Int
    var changesRequested: Int
    var lastCommentAt: Date?

    init(updatedAt: Date, state: PRState, head: String?, checks: CheckState,
         approvals: Int, changesRequested: Int, lastCommentAt: Date?) {
        self.updatedAt = updatedAt
        self.state = state
        self.head = head
        self.checks = checks
        self.approvals = approvals
        self.changesRequested = changesRequested
        self.lastCommentAt = lastCommentAt
    }

    init(_ pr: PR) {
        self.init(
            updatedAt: pr.updatedAt, state: pr.state ?? .open, head: pr.head, checks: pr.checks,
            approvals: pr.approvals ?? 0, changesRequested: pr.changesRequested ?? 0,
            lastCommentAt: pr.lastComment?.at
        )
    }

    func moved(_ beat: TrackBeat) -> Bool {
        beat.updatedAt != updatedAt || beat.state != state || beat.head != head || beat.checks != checks
    }
}

struct TrackedPR: Codable, Sendable, Equatable, Identifiable {
    let nodeId: String
    let key: String
    let url: URL
    var title: String
    var since: Date
    var mark: TrackMark

    var id: String { key }

    init(_ pr: PR, since: Date = Date()) {
        nodeId = pr.id
        key = pr.key
        url = pr.url
        title = pr.title
        self.since = since
        mark = TrackMark(pr)
    }
}

struct TrackBeat: Sendable, Equatable {
    let id: String
    let updatedAt: Date
    let state: PRState
    let head: String?
    let checks: CheckState
}

enum Tracking {
    static func events(_ tracked: TrackedPR, now pr: PR, viewer: String) -> [Event] {
        let before = tracked.mark
        let after = TrackMark(pr)
        let stamp = pr.updatedAt.timeIntervalSince1970
        func event(_ suffix: String, _ kind: EventKind = .tracked, title: String, body: String? = nil,
                   threadId: String? = nil) -> Event {
            Event(id: "\(pr.key)/track/\(suffix)/\(stamp)", kind: kind, key: pr.key, url: pr.url,
                  title: title, body: body ?? "\(pr.key) · \(pr.title)", threadId: threadId)
        }

        if after.state != before.state, after.state.isFinal {
            return [event(after.state.rawValue,
                          title: after.state == .merged ? "A PR you track was merged" : "A PR you track was closed")]
        }

        var out: [Event] = []
        if let head = after.head, let old = before.head, head != old {
            out.append(event("push", title: "New commits on a PR you track"))
        }
        if let c = pr.lastComment, c.at != before.lastCommentAt {
            let mentionsYou = c.excerpt.localizedCaseInsensitiveContains("@\(viewer)")
            out.append(event(
                "comment", mentionsYou ? .repliedToYou : .tracked,
                title: mentionsYou ? "\(c.author) replied to you" : "\(c.author) commented on a PR you track",
                body: c.location.map { "\($0) — \(c.excerpt)" } ?? c.excerpt,
                threadId: c.threadId
            ))
        }
        if after.approvals > before.approvals {
            out.append(event("approved", title: "A PR you track was approved"))
        }
        if after.changesRequested > before.changesRequested {
            out.append(event("changes", title: "Changes requested on a PR you track"))
        }
        if after.checks != before.checks {
            switch after.checks {
            case .failing: out.append(event("checks", title: "A check failed on a PR you track"))
            case .passing where before.checks == .failing || before.checks == .running:
                out.append(event("checks", title: "Checks passed on a PR you track"))
            default: break
            }
        }
        return out
    }

    static func handled(_ kind: EventKind) -> Bool {
        [.commented, .repliedToYou, .checkFailed, .approved].contains(kind)
    }

    static func parse(_ text: String) -> (repo: String, number: Int)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let host = url.host, host.hasSuffix("github.com") {
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count >= 4, parts[2] == "pull", let n = Int(parts[3]) else { return nil }
            return ("\(parts[0])/\(parts[1])", n)
        }
        let pieces = trimmed.split(separator: "#")
        guard pieces.count == 2, let n = Int(pieces[1]), pieces[0].split(separator: "/").count == 2 else { return nil }
        return (String(pieces[0]), n)
    }
}
