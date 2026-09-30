import CoreGraphics
import Testing
@testable import Diple

struct GravityTests {
    static let shape = CGRect(x: 1000, y: 1000, width: 292, height: 38)
    let gravity = Gravity()

    @Test func farAwayThereIsNoPull() {
        #expect(gravity.target(pointer: CGPoint(x: 1146, y: 700), shape: Self.shape) == .none)
    }

    @Test func thePullGrowsAsThePointerComesCloser() {
        let far = gravity.target(pointer: CGPoint(x: 1146, y: 880), shape: Self.shape)
        let near = gravity.target(pointer: CGPoint(x: 1146, y: 980), shape: Self.shape)
        #expect(far.depth > 0)
        #expect(near.depth > far.depth)
        #expect(near.depth <= gravity.maxDepth)
    }

    @Test func theBulgeLeansTowardThePointerButStaysOnTheEdge() {
        let right = gravity.target(pointer: CGPoint(x: 1400, y: 990), shape: Self.shape)
        #expect(right.center > 0)
        #expect(right.center <= Self.shape.width / 2 - gravity.halfWidth - 12)
    }

    @Test func insideTheNotchThereIsNoPull() {
        #expect(gravity.target(pointer: CGPoint(x: 1146, y: 1020), shape: Self.shape) == .none)
    }

    @Test func followingEasesTowardTheTargetAndSettlesToNone() {
        var g = Gravity()
        let first = g.follow(Pull(depth: 10, center: 0))
        #expect(first.depth > 0 && first.depth < 10)
        for _ in 0..<60 { _ = g.follow(.none) }
        #expect(g.smoothed == .none)
    }
}
