import CoreGraphics
import Testing
@testable import Diple

@MainActor
struct NotchWingsTests {
    @Test func roomyMenuBarKeepsFullWingsEachSide() {
        let w = NotchGeometry.wings(freeRight: 60, full: 42)
        #expect(w == Wings(left: 42, right: 42))
        #expect(w.shift == 0)
    }

    @Test func narrowGapShrinksBothWingsAndStaysCentered() {
        let w = NotchGeometry.wings(freeRight: 40, full: 42)
        #expect(w == Wings(left: 34, right: 34))
        #expect(w.shift == 0)
    }

    @Test func aTightGapKeepsBothWingsAtTheirSmallest() {
        let w = NotchGeometry.wings(freeRight: 23.5, full: 42)
        #expect(w == Wings(left: NotchGeometry.minWing, right: NotchGeometry.minWing))
        #expect(w.shift == 0)
    }

    @Test func bothWingsAlwaysExistAndStayCentered() {
        for free in stride(from: CGFloat(0), through: 80, by: 0.5) {
            let w = NotchGeometry.wings(freeRight: free, full: 42)
            #expect(w.left == w.right)
            #expect(w.right >= NotchGeometry.minWing)
            #expect(w.right <= 42)
        }
    }
}
