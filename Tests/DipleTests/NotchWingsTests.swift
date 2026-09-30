import CoreGraphics
import Testing
@testable import Diple

@MainActor
struct NotchWingsTests {
    @Test func roomyMenuBarKeepsFullWingsEachSide() {
        let w = NotchGeometry.wings(freeRight: 60, full: 42)
        #expect(w == Wings(left: 42, right: 42))
        #expect(!w.countOnLeft)
        #expect(w.shift == 0)
    }

    @Test func narrowGapShrinksBothWingsAndStaysCentered() {
        let w = NotchGeometry.wings(freeRight: 40, full: 42)
        #expect(w == Wings(left: 34, right: 34))
        #expect(w.shift == 0)
    }

    @Test func tightGapMovesTheCountLeftAndHidesTheEye() {
        let w = NotchGeometry.wings(freeRight: 26.5, full: 42)
        #expect(w == Wings(left: 42, right: 0))
        #expect(w.countOnLeft)
        #expect(w.shift == -21)
    }

    @Test func rightWingNeverReachesTheFirstStatusItem() {
        for free in stride(from: CGFloat(0), through: 80, by: 0.5) {
            #expect(NotchGeometry.wings(freeRight: free, full: 42).right <= max(0, free - 6))
        }
    }
}

@MainActor
struct MenuBarItemsTests {
    static let notchRight: CGFloat = 2984
    static let screenMaxX: CGFloat = 3840

    func free(_ lefts: [CGFloat]) -> CGFloat {
        MenuBarItems.freeRight(notchRight: Self.notchRight, screenMaxX: Self.screenMaxX, lefts: lefts)
    }

    @Test func theNearestItemRightOfTheNotchSetsTheGap() {
        #expect(free([3780, 3640, 3020]) == 36)
    }

    @Test func itemsBehindTheNotchAreHiddenAndIgnored() {
        #expect(free([3780, 3020, 2940]) == 36)
    }

    @Test func noItemsLeavesTheWholeRightSideFree() {
        #expect(free([]) == 856)
    }
}
