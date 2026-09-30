import CoreGraphics
import Testing
@testable import Diple

struct GravityTests {
    static let shape = CGRect(x: 1000, y: 1000, width: 292, height: 38)
    let gravity = Gravity()

    @Test func beyondTheReachThereIsNoPull() {
        #expect(gravity.target(pointer: CGPoint(x: 1146, y: 1000 - 120), shape: Self.shape) == .none)
    }

    @Test func fromBelowTheBottomBulgesAndSagsMoreAsThePointerNears() {
        let far = gravity.target(pointer: CGPoint(x: 1146, y: 920), shape: Self.shape)
        let near = gravity.target(pointer: CGPoint(x: 1146, y: 985), shape: Self.shape)
        #expect(far.bulge > 0)
        #expect(near.bulge > far.bulge && near.sag > far.sag)
        #expect(near.bulge <= gravity.maxBulge)
        #expect(near.left < 0.5 && near.right < 0.5)
    }

    @Test func underTheEdgeButOffCentreItStillBulgesAndLeansThatWay() {
        let pull = gravity.target(pointer: CGPoint(x: 1210, y: 992), shape: Self.shape)
        #expect(pull.bulge > gravity.maxBulge / 2)
        #expect(pull.right > 0 && pull.left == 0)
    }

    @Test func fromTheSideTheNearEdgeStretchesAndTheBottomDoesNot() {
        let right = gravity.target(pointer: CGPoint(x: 1292 + 30, y: 1020), shape: Self.shape)
        #expect(right.right > 0)
        #expect(right.left == 0)
        #expect(right.bulge == 0)
        let left = gravity.target(pointer: CGPoint(x: 1000 - 30, y: 1020), shape: Self.shape)
        #expect(left.left > 0 && left.right == 0)
    }

    @Test func theBulgeLeansTowardThePointerButStaysOnTheEdge() {
        let pull = gravity.target(pointer: CGPoint(x: 1280, y: 990), shape: Self.shape)
        #expect(pull.center > 0)
        #expect(pull.center <= Self.shape.width / 2 - gravity.halfWidth - 12)
    }

    @Test func insideTheNotchThereIsNoPull() {
        #expect(gravity.target(pointer: CGPoint(x: 1146, y: 1020), shape: Self.shape) == .none)
    }

    @Test func followingEasesTowardTheTargetAndSettlesToNone() {
        var g = Gravity()
        let first = g.follow(Pull(bulge: 10, sag: 3))
        #expect(first.bulge > 0 && first.bulge < 10)
        for _ in 0..<60 { _ = g.follow(.none) }
        #expect(g.smoothed == .none)
    }
}
