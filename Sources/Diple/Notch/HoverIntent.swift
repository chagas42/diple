import CoreGraphics
import Foundation

enum HoverOpening: String, Codable, Sendable, CaseIterable, Identifiable {
    case instantly, afterPause

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instantly:  "Instantly"
        case .afterPause: "After a short pause"
        }
    }
}

struct HoverIntent {
    enum Decision: Equatable { case open, hold }

    static let dwell: TimeInterval = 0.15
    static let fastest: CGFloat = 700
    static let speedWindow: TimeInterval = 0.1

    var opening = HoverOpening.afterPause
    private var samples: [(time: Date, point: CGPoint)] = []
    private var slowInsideSince: Date?
    private var wasPressed = false

    static func zone(notch: CGRect, shape: CGRect) -> CGRect {
        let resting = notch.union(shape)
        return CGRect(x: resting.minX, y: resting.minY, width: resting.width, height: resting.height + 1)
    }

    var speed: CGFloat {
        guard let first = samples.first, let last = samples.last else { return 0 }
        let elapsed = last.time.timeIntervalSince(first.time)
        guard elapsed > 0 else { return 0 }
        return hypot(last.point.x - first.point.x, last.point.y - first.point.y) / elapsed
    }

    mutating func feed(at time: Date, pointer: CGPoint, zone: CGRect, pressed: Bool = false) -> Decision {
        remember(time, pointer)
        let clicked = pressed && !wasPressed
        wasPressed = pressed

        guard zone.contains(pointer) else {
            slowInsideSince = nil
            return .hold
        }
        if clicked || opening == .instantly { return .open }
        guard speed <= Self.fastest else {
            slowInsideSince = nil
            return .hold
        }
        let since = slowInsideSince ?? time
        slowInsideSince = since
        return time.timeIntervalSince(since) >= Self.dwell ? .open : .hold
    }

    private mutating func remember(_ time: Date, _ point: CGPoint) {
        samples.append((time, point))
        while samples.count > 2, time.timeIntervalSince(samples[1].time) >= Self.speedWindow {
            samples.removeFirst()
        }
    }
}
