import Foundation

struct SyncPolicy: Sendable, Equatable {
    var base: TimeInterval
    var failures = 0
    var partialFailures = 0
    var online = true
    var visible = false
    var lowPower = false
    var rateLimitLeft: Int?
    var rateLimitResetAt: Date?

    static let maxBackoff: TimeInterval = 600
    static let partialRetry: TimeInterval = 30
    static let rateLimitFloor = 100

    func nextDelay(now: Date = Date()) -> TimeInterval? {
        guard online else { return nil }

        if let left = rateLimitLeft, left < Self.rateLimitFloor,
           let reset = rateLimitResetAt, reset > now {
            return max(reset.timeIntervalSince(now) + 5, base)
        }

        if failures > 0 {
            let exponent = Double(min(failures, 10))
            return min(base * pow(2, exponent), Self.maxBackoff)
        }

        var delay = visible ? base : base * 2
        if lowPower { delay *= 2 }
        if partialFailures > 0 {
            let exponent = Double(min(partialFailures - 1, 10))
            return min(Self.partialRetry * pow(2, exponent), delay)
        }
        return delay
    }

    var tolerance: TimeInterval { (nextDelay() ?? base) * 0.1 }
}
