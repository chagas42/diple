import CoreGraphics
import Testing
@testable import Diple

struct PointerGlowTests {
    static let cutout = CGRect(x: 2880, y: 1205.5, width: 200, height: 37.5)

    @Test func outsideTheCutoutThereIsNoGlow() {
        #expect(Glow.target(pointer: CGPoint(x: 2980, y: 1190), cutout: Self.cutout) == .off)
        #expect(Glow.target(pointer: CGPoint(x: 2860, y: 1230), cutout: Self.cutout) == .off)
    }

    @Test func nearTheBottomItGlowsOnTheBottomEdgeUnderThePointer() {
        let g = Glow.target(pointer: CGPoint(x: 3000, y: 1210), cutout: Self.cutout)
        #expect(g.isOn)
        #expect(g.x == 20)
        #expect(g.y == 37.5 && !g.onSide)
    }

    @Test func nearASideItGlowsOnThatSide() {
        let left = Glow.target(pointer: CGPoint(x: 2885, y: 1230), cutout: Self.cutout)
        #expect(left.x == -100 && left.onSide)
        let right = Glow.target(pointer: CGPoint(x: 3075, y: 1230), cutout: Self.cutout)
        #expect(right.x == 100)
    }

    @Test func deeperInTheCutoutGlowsBrighter() {
        let shallow = Glow.target(pointer: CGPoint(x: 2980, y: 1208), cutout: Self.cutout)
        let deep = Glow.target(pointer: CGPoint(x: 2980, y: 1240), cutout: Self.cutout)
        #expect(deep.intensity > shallow.intensity)
        #expect(deep.intensity <= 1)
    }

    @Test func noCutoutNoGlow() {
        #expect(Glow.target(pointer: .zero, cutout: .zero) == .off)
    }
}
