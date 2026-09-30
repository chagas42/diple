import CoreGraphics
import Testing
@testable import Diple

struct PointerGlowTests {
    static let cutout = CGRect(x: 2880, y: 1205.5, width: 200, height: 37.5)

    @Test func farFromTheCutoutThereIsNoGlow() {
        #expect(Glow.target(pointer: CGPoint(x: 2980, y: 1150), cutout: Self.cutout) == .off)
        #expect(Glow.target(pointer: CGPoint(x: 2820, y: 1230), cutout: Self.cutout) == .off)
    }

    @Test func approachingTheCutoutTheRimComesUpBeforeThePointerEntersIt() {
        let far = Glow.target(pointer: CGPoint(x: 2980, y: 1175), cutout: Self.cutout)
        let near = Glow.target(pointer: CGPoint(x: 2980, y: 1200), cutout: Self.cutout)
        let inside = Glow.target(pointer: CGPoint(x: 2980, y: 1210), cutout: Self.cutout)
        #expect(far.rim > 0 && near.rim > far.rim && inside.rim >= near.rim)
        #expect(far.spill == 0 && near.spill == 0 && inside.spill == 1)
    }

    @Test func theLightSitsWhereThePointerIs() {
        let g = Glow.target(pointer: CGPoint(x: 3000, y: 1210), cutout: Self.cutout)
        #expect(g.isOn)
        #expect(g.x == 20)
        #expect(g.y == CGFloat(1243 - 1210))
    }

    @Test func movingFromTheBottomToASideMovesTheLightContinuously() {
        var last: Glow?
        for x in stride(from: CGFloat(2980), through: 3078, by: 2) {
            let g = Glow.target(pointer: CGPoint(x: x, y: 1212), cutout: Self.cutout)
            if let last { #expect(abs(g.x - last.x) <= 2 && abs(g.y - last.y) < 0.001) }
            last = g
        }
    }

    @Test func deeperInTheCutoutGlowsBrighter() {
        let shallow = Glow.target(pointer: CGPoint(x: 2980, y: 1208), cutout: Self.cutout)
        let deep = Glow.target(pointer: CGPoint(x: 2980, y: 1240), cutout: Self.cutout)
        #expect(deep.rim > shallow.rim)
        #expect(deep.rim <= 1)
    }

    @Test func theLightReachesFurtherTheFurtherThePointerIsFromAVisibleEdge() {
        let byTheBottom = Glow.target(pointer: CGPoint(x: 2980, y: 1207), cutout: Self.cutout)
        let atTheTop = Glow.target(pointer: CGPoint(x: 2980, y: 1242), cutout: Self.cutout)
        #expect(atTheTop.depth > byTheBottom.depth)
        #expect(abs(atTheTop.depth - (1242 - 1205.5)) < 0.001)
    }

    @Test func atTheVeryTopOfTheScreenItStillGlowsFully() {
        let g = Glow.target(pointer: CGPoint(x: 2980, y: 1243), cutout: Self.cutout)
        #expect(g.spill == 1)
        #expect(abs(g.rim - 0.85) < 0.001)
        #expect(abs(g.depth - 37.5) < 0.001)
    }

    @Test func noCutoutNoGlow() {
        #expect(Glow.target(pointer: .zero, cutout: .zero) == .off)
    }
}
