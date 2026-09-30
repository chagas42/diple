import CoreGraphics
import Foundation
import Combine

struct Pull: Equatable {
    var depth: CGFloat = 0
    var center: CGFloat = 0

    static let none = Pull()
}

@MainActor
final class PullState: ObservableObject {
    @Published var pull = Pull.none
}

struct Gravity {
    static var isOn: Bool { ProcessInfo.processInfo.environment["DIPLE_GRAVITY"] == "1" }

    var reach: CGFloat = 180
    var maxDepth: CGFloat = 14
    var halfWidth: CGFloat = 52
    var smoothing: CGFloat = 0.3

    private(set) var smoothed = Pull.none

    func target(pointer: CGPoint, shape: CGRect) -> Pull {
        let edgeY = shape.minY
        guard pointer.y < edgeY else { return .none }
        let x = min(max(pointer.x, shape.minX), shape.maxX)
        let distance = hypot(pointer.x - x, edgeY - pointer.y)
        guard distance < reach else { return .none }
        let strength = pow(1 - distance / reach, 2)
        let room = max(0, shape.width / 2 - halfWidth - 12)
        let center = min(max(pointer.x - shape.midX, -room), room)
        return Pull(depth: maxDepth * strength, center: center * strength.squareRoot())
    }

    mutating func follow(_ target: Pull) -> Pull {
        smoothed.depth += (target.depth - smoothed.depth) * smoothing
        smoothed.center += (target.center - smoothed.center) * smoothing
        if smoothed.depth < 0.05 { smoothed = .none }
        return smoothed
    }
}
