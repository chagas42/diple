import Foundation

enum RankingMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case off, pace, team

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:  "Off"
        case .pace: "My pace"
        case .team: "Team board"
        }
    }

    var detail: String {
        switch self {
        case .off:  "No ranking. Reviews are not a race."
        case .pace: "Only you, against your own usual."
        case .team: "Everyone you follow, ranked by reviews."
        }
    }

    var icon: String {
        switch self {
        case .off:  "eye.slash"
        case .pace: "figure.walk"
        case .team: "trophy"
        }
    }
}

struct Pace: Equatable, Sendable {
    enum Mood: Equatable, Sendable { case ahead, onPace, lighter, early, noHistory }

    let current: Int
    let usual: Double?
    let elapsed: Double

    static let lookback: [RankPeriod: Int] = [.week: 8, .month: 5, .quarter: 1]

    var expected: Double? { usual.map { $0 * elapsed } }

    var mood: Mood {
        guard let usual, usual > 0, let expected else { return .noHistory }
        if elapsed < 0.15 { return .early }
        let ratio = Double(current) / max(expected, 0.5)
        if ratio >= 1.15 { return .ahead }
        if ratio <= 0.85 { return .lighter }
        return .onPace
    }

    static func of(
        _ period: RankPeriod, days: [ActivityDay], now: Date = Date(), calendar: Calendar = .current
    ) -> Pace {
        let start = period.since(now: now, calendar: calendar)
        let end = next(period, after: start, calendar: calendar)
        let current = days.filter { $0.date >= start && $0.date <= now }.reduce(0) { $0 + $1.reviews }
        let total = end.timeIntervalSince(start)
        let elapsed = total > 0 ? min(1, max(0, now.timeIntervalSince(start) / total)) : 1

        let history = days.map(\.date).min() ?? now
        var counts: [Int] = []
        var upper = start
        for _ in 0..<(lookback[period] ?? 1) {
            let lower = previous(period, before: upper, calendar: calendar)
            guard lower >= calendar.startOfDay(for: history) else { break }
            counts.append(days.filter { $0.date >= lower && $0.date < upper }.reduce(0) { $0 + $1.reviews })
            upper = lower
        }
        let usual = counts.isEmpty ? nil : Double(counts.reduce(0, +)) / Double(counts.count)
        return Pace(current: current, usual: usual, elapsed: elapsed)
    }

    private static func step(_ period: RankPeriod) -> (Calendar.Component, Int) {
        switch period {
        case .week: (.day, 7)
        case .month: (.month, 1)
        case .quarter: (.month, 3)
        }
    }

    static func next(_ period: RankPeriod, after start: Date, calendar: Calendar) -> Date {
        let (unit, n) = step(period)
        return calendar.date(byAdding: unit, value: n, to: start) ?? start
    }

    static func previous(_ period: RankPeriod, before start: Date, calendar: Calendar) -> Date {
        let (unit, n) = step(period)
        return calendar.date(byAdding: unit, value: -n, to: start) ?? start
    }

    func sentence(_ period: RankPeriod) -> String {
        let word = switch period { case .week: "week" case .month: "month" case .quarter: "quarter" }
        switch mood {
        case .ahead:     return "Ahead of your usual pace."
        case .onPace:    return "Right on your usual pace."
        case .lighter:   return "Lighter than usual so far."
        case .early:     return "The \(word) has just started."
        case .noHistory: return "Your usual shows up after a full \(word)."
        }
    }
}
