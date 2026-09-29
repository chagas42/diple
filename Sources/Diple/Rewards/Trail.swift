import Foundation

enum Trail {
    static let milestones = [10, 30, 60, 100, 180, 300]
    static let rarities: [Rarity] = [.common, .common, .uncommon, .rare, .epic, .legendary]

    static func season(of date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return "\(c.year ?? 0)-Q\(((c.month ?? 1) - 1) / 3 + 1)"
    }

    static func milestone(at count: Int) -> Int? { milestones.firstIndex(of: count) }

    static func leg(for count: Int) -> (from: Int, to: Int)? {
        var from = 0
        for m in milestones {
            if count <= m { return (from, m) }
            from = m
        }
        return nil
    }
}

struct SeasonProgress: Codable, Sendable, Equatable {
    let id: String
    var reviews: Int
}

struct ReviewTick: Identifiable, Sendable, Equatable {
    let id: String
    let pr: String
    let verdict: ReviewVerdict
    let count: Int
    let reward: Reward?

    var leg: (from: Int, to: Int)? { Trail.leg(for: count) }

    static func == (a: ReviewTick, b: ReviewTick) -> Bool { a.id == b.id }
}
