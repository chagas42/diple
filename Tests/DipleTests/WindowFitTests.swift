import AppKit
import SwiftUI
import Testing
@testable import Diple

@MainActor
@Suite struct WindowFitTests {
    let visible = NSRect(x: 0, y: 70, width: 1710, height: 970)

    @Test func aWindowTallerThanTheScreenIsBroughtBackOnIt() {
        let saved = NSRect(x: 58, y: -394, width: 1572, height: 1467)
        let f = Windows.fitted(saved, in: visible)
        #expect(f.height == 970)
        #expect(f.minY == visible.minY && f.maxY == visible.maxY)
        #expect(f.minX == 58 && f.width == 1572)
    }

    @Test func aWindowThatFitsStaysWhereItIs() {
        let saved = NSRect(x: 100, y: 200, width: 1320, height: 820)
        #expect(Windows.fitted(saved, in: visible) == saved)
    }

    @Test func aWindowOffTheRightEdgeSlidesBackIn() {
        let saved = NSRect(x: 1500, y: 200, width: 900, height: 600)
        let f = Windows.fitted(saved, in: visible)
        #expect(f.maxX == visible.maxX && f.width == 900)
    }

    @Test func resizableWindowsDoNotGrowWithTheirContent() {
        let host = Windows.host(Text("hi"))
        #expect(host.sizingOptions == [.minSize])
    }
}
