import Foundation

enum Dismissals {
    static let keepFor: TimeInterval = 30 * 86_400

    static func hides(_ pr: PR, _ dismissed: [String: Date]) -> Bool {
        guard let at = dismissed[pr.key] else { return false }
        return pr.updatedAt <= at
    }

    static func kept(_ dismissed: [String: Date], queue: Queue, now: Date) -> [String: Date] {
        let current = Dictionary(queue.all.map { ($0.key, $0.updatedAt) }, uniquingKeysWith: max)
        return dismissed.filter { key, at in
            if let updated = current[key] { return updated <= at }
            return now.timeIntervalSince(at) < keepFor
        }
    }
}
