import Foundation

enum EventKind: String, Codable, Sendable, CaseIterable {
    case repliedToYou
    case commented
    case reviewRequested
    case checkFailed
    case approved
    case newPullRequest
    case tracked

    var sound: String? {
        switch self {
        case .repliedToYou: "Glass"
        case .commented:      "Pop"
        case .reviewRequested:   "Tink"
        case .checkFailed:     "Basso"
        case .approved:       nil
        case .newPullRequest: "Bottle"
        case .tracked:        "Hero"
        }
    }

    var interrupts: Bool { self != .approved && self != .newPullRequest }

    var urgency: Int {
        switch self {
        case .repliedToYou:    4
        case .checkFailed:     3
        case .commented:       2
        case .reviewRequested: 1
        case .approved:        0
        case .newPullRequest:  0
        case .tracked:         2
        }
    }

    static func moreUrgent(_ a: EventKind?, _ b: EventKind) -> EventKind {
        guard let a else { return b }
        return b.urgency >= a.urgency ? b : a
    }

    var glyph: String {
        switch self {
        case .repliedToYou: "arrowshape.turn.up.left.fill"
        case .commented:      "bubble.left.fill"
        case .reviewRequested:   "arrow.triangle.branch"
        case .checkFailed:     "xmark.octagon.fill"
        case .approved:       "checkmark.seal.fill"
        case .newPullRequest: "tray.and.arrow.down.fill"
        case .tracked:        "scope"
        }
    }

    var label: String {
        switch self {
        case .repliedToYou: "replied to you"
        case .commented:      "commented on your PR"
        case .reviewRequested:   "requested your review"
        case .checkFailed:     "check failing"
        case .approved:       "approved your PR"
        case .newPullRequest: "opened a pull request"
        case .tracked:        "updated a PR you track"
        }
    }
}

struct Event: Identifiable, Sendable {
    let id: String
    let kind: EventKind
    let key: String
    let url: URL
    let title: String
    let body: String

    var threadId: String? = nil
    var isTest = false
}
