import SwiftUI

enum ReviewVerdict: String, Codable, Sendable, CaseIterable {
    case commented, approved, changesRequested

    init(github state: String?) {
        switch state {
        case "APPROVED":          self = .approved
        case "CHANGES_REQUESTED": self = .changesRequested
        default:                  self = .commented
        }
    }

    var word: String {
        switch self {
        case .commented:        "commented"
        case .approved:         "approved"
        case .changesRequested: "changes requested"
        }
    }

    var short: String { self == .changesRequested ? "changes" : word }

    var color: Color {
        switch self {
        case .commented:        Color(red: 0.93, green: 0.94, blue: 0.96)
        case .approved:         Color(red: 0.36, green: 0.84, blue: 0.52)
        case .changesRequested: Color(red: 1.0, green: 0.62, blue: 0.3)
        }
    }
}

struct ReviewTick: Identifiable, Sendable, Equatable {
    let id: String
    let pr: String
    let verdict: ReviewVerdict
    let today: Int
}
