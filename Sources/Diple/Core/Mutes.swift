import Foundation

enum Mutes {
    static let keepFor: TimeInterval = 30 * 86_400
    static let refreshAfter: TimeInterval = 86_400

    static func kept(_ muted: [String: Date], queue: Queue, now: Date) -> [String: Date] {
        let present = Set(queue.all.map(\.key))
        var kept: [String: Date] = [:]
        for (key, seen) in muted {
            if present.contains(key) {
                kept[key] = now.timeIntervalSince(seen) < refreshAfter ? seen : now
            } else if now.timeIntervalSince(seen) < keepFor {
                kept[key] = seen
            }
        }
        return kept
    }
}
