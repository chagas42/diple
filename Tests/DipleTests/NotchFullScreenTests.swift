import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct NotchFullScreenTests {
    static let builtIn = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
    static let external = "16E78404-5477-4F8A-856B-779D15556068"

    static func display(_ id: String, currentType: Int) -> [String: Any] {
        ["Display Identifier": id, "Current Space": ["type": currentType]]
    }

    @Test func aFullScreenSpaceOnTheDisplayHidesIt() {
        let spaces = [Self.display(Self.external, currentType: 0), Self.display(Self.builtIn, currentType: 4)]
        #expect(NotchGeometry.isUnderFullScreen(display: Self.builtIn, spaces: spaces))
    }

    @Test func aFullScreenSpaceOnAnotherDisplayDoesNot() {
        let spaces = [Self.display(Self.external, currentType: 4), Self.display(Self.builtIn, currentType: 0)]
        #expect(!NotchGeometry.isUnderFullScreen(display: Self.builtIn, spaces: spaces))
    }

    @Test func theIdentifierIsMatchedWhateverItsCase() {
        let spaces = [Self.display(Self.external, currentType: 0), Self.display(Self.builtIn.lowercased(), currentType: 4)]
        #expect(NotchGeometry.isUnderFullScreen(display: Self.builtIn, spaces: spaces))
    }

    @Test func withSpacesSharedAcrossDisplaysTheSingleEntryDecides() {
        #expect(NotchGeometry.isUnderFullScreen(display: Self.builtIn, spaces: [Self.display("Main", currentType: 4)]))
    }

    @Test func noSpacesMeansNotFullScreen() {
        #expect(!NotchGeometry.isUnderFullScreen(display: Self.builtIn, spaces: []))
    }

    static let screen = CGRect(x: 1920, y: -163, width: 1920, height: 1243)

    func reveals(_ y: CGFloat, x: CGFloat = 2100, shown: Bool) -> Bool {
        NotchGeometry.revealsMenuBar(pointer: CGPoint(x: x, y: y), screen: Self.screen, barHeight: 37.5, shown: shown)
    }

    @Test func theTopEdgeRevealsTheMenuBar() {
        #expect(reveals(Self.screen.maxY, shown: false))
    }

    @Test func movingIntoTheBarFromBelowDoesNotRevealIt() {
        #expect(!reveals(Self.screen.maxY - 20, shown: false))
    }

    @Test func aRevealedBarStaysWhileThePointerIsOnItAndGoesBelowIt() {
        #expect(reveals(Self.screen.maxY - 30, shown: true))
        #expect(!reveals(Self.screen.maxY - 40, shown: true))
    }

    @Test func theTopEdgeOfAnotherDisplayDoesNot() {
        #expect(!reveals(1080, x: 500, shown: false))
    }

    final class Flag {
        var on: Bool
        init(_ on: Bool) { self.on = on }
    }

    static let away = CGPoint(x: -1000, y: -1000)

    var notchCenter: CGPoint {
        let g = NotchGeometry.current()
        let r = g.rect(g.closed)
        return CGPoint(x: r.midX, y: r.midY)
    }

    func notch(fullScreen: Flag, pointer: @escaping @MainActor () -> CGPoint) -> NotchController {
        let n = NotchController()
        n.fullScreen = { fullScreen.on }
        n.pointer = pointer
        return n
    }

    @Test func theNotchHidesWhileAnAppIsFullScreenAndComesBackAfter() {
        let flag = Flag(true)
        let n = notch(fullScreen: flag) { Self.away }
        n.refreshIdle()
        #expect(n.state == .hidden)

        flag.on = false
        n.refreshIdle()
        #expect(n.state == .active)
    }

    @Test func revealingTheMenuBarBringsTheNotchBackUntilThePointerLeavesIt() {
        let top = NotchGeometry.current().screen.frame
        var at = Self.away
        let n = notch(fullScreen: Flag(true)) { at }
        n.refreshIdle()
        #expect(n.state == .hidden)

        at = CGPoint(x: top.minX + 40, y: top.maxY)
        n.checkPointer()
        #expect(n.state == .active)

        at.y -= 20
        n.checkPointer()
        #expect(n.state == .active)

        at.y = top.midY
        n.checkPointer()
        #expect(n.state == .hidden)
    }

    @Test func hoveringTheHiddenNotchStillOpensItAndLeavingHidesItAgain() async throws {
        var at = Self.away
        let n = notch(fullScreen: Flag(true)) { at }
        n.refreshIdle()

        at = notchCenter
        n.checkPointer()
        #expect(n.state == .open)

        at = Self.away
        for _ in 0..<40 where n.state == .open {
            n.checkPointer()
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(n.state == .hidden)
    }
}
