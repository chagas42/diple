import Foundation

enum EventKind: String, Codable, Sendable, CaseIterable {
    case repliedToYou
    case commented
    case reviewRequested
    case checkFailed
    case approved

    var sound: String? {
        switch self {
        case .repliedToYou: "Glass"
        case .commented:      "Pop"
        case .reviewRequested:   "Tink"
        case .checkFailed:     "Basso"
        case .approved:       nil
        }
    }

    var interrupts: Bool { self != .approved }

    var glyph: String {
        switch self {
        case .repliedToYou: "arrowshape.turn.up.left.fill"
        case .commented:      "bubble.left.fill"
        case .reviewRequested:   "arrow.triangle.branch"
        case .checkFailed:     "xmark.octagon.fill"
        case .approved:       "checkmark.seal.fill"
        }
    }

    var label: String {
        switch self {
        case .repliedToYou: "replied to you"
        case .commented:      "commented on your PR"
        case .reviewRequested:   "requested your review"
        case .checkFailed:     "check failing"
        case .approved:       "aprovou"
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
}
