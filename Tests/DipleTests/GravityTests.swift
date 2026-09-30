import CoreGraphics
import Testing
@testable import Diple

struct GravityTests {
    static let shape = CGRect(x: 1000, y: 1000, width: 292, height: 38)
    let gravity = Gravity()

    @Test func beyondTheReachThereIsNoPull() {
        #expect(gravity.target(pointer: CGPoint(x: 1146, y: 880), shape: Self.shape).isNone)
    }

    @Test func thePullGrowsAsThePointerComesCloserAndSitsWhereThePointerIs() {
        let far = gravity.target(pointer: CGPoint(x: 1146, y: 920), shape: Self.shape)
        let near = gravity.target(pointer: CGPoint(x: 1146, y: 985), shape: Self.shape)
        #expect(near.strength > far.strength && far.strength > 0)
        #expect(near.x == 146 && near.y == 38 + 15)
    }

    @Test func atMenuBarHeightBesideTheNotchThereIsNoPull() {
        #expect(gravity.target(pointer: CGPoint(x: 1292 + 20, y: 1020), shape: Self.shape).isNone)
        #expect(gravity.target(pointer: CGPoint(x: 1000 - 20, y: 1030), shape: Self.shape).isNone)
    }

    @Test func thePullComesInAsThePointerDropsBelowTheNotch() {
        let level = gravity.target(pointer: CGPoint(x: 1146, y: 998), shape: Self.shape)
        let under = gravity.target(pointer: CGPoint(x: 1146, y: 980), shape: Self.shape)
        #expect(under.strength > level.strength)
    }

    @Test func followingEasesTowardTheTargetAndSettlesToNone() {
        var g = Gravity()
        let first = g.follow(Pull(x: 146, y: 60, strength: 1))
        #expect(first.strength > 0 && first.strength < 1)
        for _ in 0..<60 { _ = g.follow(Pull(x: 146, y: 200, strength: 0)) }
        #expect(g.follow(Pull(x: 146, y: 200, strength: 0)).isNone)
    }
}

struct BlobTests {
    static let w: CGFloat = 292, h: CGFloat = 38
    let outline = Blob.outline(width: w, height: h, radius: 10)

    @Test func theTopEdgeStaysAttached() {
        let drawn = Blob.drawn(outline, height: Self.h, toward: Pull(x: 146, y: 60, strength: 1))
        for (p, q) in zip(outline, drawn) where p.at.y == 0 {
            #expect(q == p.at)
        }
    }

    @Test func thePointNearestThePointerMovesMostAndTowardIt() {
        let pull = Pull(x: 220, y: 60, strength: 1)
        let drawn = Blob.drawn(outline, height: Self.h, toward: pull)
        let moves = zip(outline, drawn).map { hypot($1.x - $0.at.x, $1.y - $0.at.y) }
        let most = moves.indices.max { moves[$0] < moves[$1] }!
        #expect(abs(outline[most].at.x - 220) < 20)
        #expect(drawn[most].y > outline[most].at.y)
        #expect(moves[most] <= Blob.maxStretch)
    }

    @Test func theSidesGrowMuchLessThanTheBottom() {
        let drawn = Blob.drawn(outline, height: Self.h, toward: Pull(x: Self.w + 10, y: Self.h + 10, strength: 1))
        let out = zip(outline, drawn).map { ($1.x - $0.at.x, $1.y - $0.at.y) }
        let widest = out.map(\.0).max()!, deepest = out.map(\.1).max()!
        #expect(widest < deepest / 2)
        #expect(widest <= Blob.maxStretch * Blob.sideways)
    }

    @Test func pointsFarFromThePointerMoveFarLessThanTheNearest() {
        let drawn = Blob.drawn(outline, height: Self.h, toward: Pull(x: 280, y: 60, strength: 1))
        let moves = zip(outline, drawn).map { ($0.at, hypot($1.x - $0.at.x, $1.y - $0.at.y)) }
        let nearest = moves.max { $0.1 < $1.1 }!.1
        let far = moves.filter { $0.0.x < 20 && $0.0.y > 30 }.map(\.1).max()!
        #expect(far < nearest / 10)
    }

    static func crosses(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        func side(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> CGFloat {
            (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
        }
        return side(a, b, c) * side(a, b, d) < 0 && side(c, d, a) * side(c, d, b) < 0
    }

    @Test func movingThePointerAroundTheCornerNeverFoldsTheOutline() {
        for y in stride(from: CGFloat(0), through: 70, by: 2) {
            for x in [Self.w + 5, Self.w + 20, Self.w - 10] {
                let q = Blob.drawn(outline, height: Self.h, toward: Pull(x: x, y: y, strength: 1))
                var folded = false
                for i in 0..<(q.count - 3) {
                    for j in (i + 2)..<(q.count - 1) where !folded {
                        folded = Self.crosses(q[i], q[i + 1], q[j], q[j + 1])
                    }
                }
                #expect(!folded, "outline folds with the pointer at \(x), \(y)")
            }
        }
    }
}
