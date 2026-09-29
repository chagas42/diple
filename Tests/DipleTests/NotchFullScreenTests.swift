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

    @Test func theFullScreenSpacesOfTheDisplayAreRead() {
        let spaces: [[String: Any]] = [
            ["Display Identifier": Self.external, "Spaces": [["ManagedSpaceID": 7, "type": 4]]],
            ["Display Identifier": Self.builtIn, "Spaces": [
                ["ManagedSpaceID": 1, "type": 0], ["ManagedSpaceID": 9789, "type": 4], ["ManagedSpaceID": 9823, "type": 4],
            ]],
        ]
        #expect(NotchGeometry.fullScreenSpaces(display: Self.builtIn, spaces: spaces) == [9789, 9823])
        #expect(NotchGeometry.fullScreenSpaces(display: Self.builtIn, spaces: []).isEmpty)
    }

    @Test func aFullScreenSpaceSlidingInHidesTheNotchBeforeTheSwitchLands() {
        let arriving = Flag(false)
        let n = notch(fullScreen: Flag(false)) { Self.away }
        n.fullScreenArriving = { arriving.on }
        n.refreshIdle()
        n.checkPointer()
        #expect(n.state == .active)

        arriving.on = true
        n.checkPointer()
        #expect(n.state == .hidden)
    }

    @Test func aSwipeGivenUpHalfwayBringsTheNotchBack() {
        let arriving = Flag(true)
        let n = notch(fullScreen: Flag(false)) { Self.away }
        n.fullScreenArriving = { arriving.on }
        n.checkPointer()
        #expect(n.state == .hidden)

        arriving.on = false
        n.checkPointer()
        #expect(n.state == .active)
    }

    @Test func onceTheSwitchLandsTheNotchStaysHidden() {
        let full = Flag(false), arriving = Flag(true)
        let n = notch(fullScreen: full) { Self.away }
        n.fullScreenArriving = { arriving.on }
        n.checkPointer()

        full.on = true
        arriving.on = false
        n.refreshIdle()
        n.checkPointer()
        #expect(n.state == .hidden)
    }

    @Test func launchingOverAFullScreenAppStartsHiddenWithoutShowingTheWingsFirst() {
        let n = notch(fullScreen: Flag(true)) { Self.away }
        n.settleBeforeFirstFrame()
        #expect(n.state == .hidden)
    }

    @Test func launchingOnADesktopStartsWithTheWings() {
        let n = notch(fullScreen: Flag(false)) { Self.away }
        n.settleBeforeFirstFrame()
        #expect(n.state == .active)
    }

    final class Clock {
        var now = Date(timeIntervalSince1970: 0)
    }

    @Test func fullScreenWindowsOnScreenLongerThanASwitchNoLongerHideTheNotch() {
        let clock = Clock()
        let n = notch(fullScreen: Flag(false)) { Self.away }
        n.fullScreenArriving = { true }
        n.clock = { clock.now }
        n.checkPointer()
        #expect(n.state == .hidden)

        clock.now += NotchController.longestSwitch - 0.1
        n.checkPointer()
        #expect(n.state == .hidden)

        clock.now += 0.2
        n.checkPointer()
        #expect(n.state == .active)
    }

    @Test func aNewSwipeAfterTheWindowsLeftHidesAgain() {
        let clock = Clock(), arriving = Flag(true)
        let n = notch(fullScreen: Flag(false)) { Self.away }
        n.fullScreenArriving = { arriving.on }
        n.clock = { clock.now }
        n.checkPointer()
        clock.now += 5
        n.checkPointer()
        #expect(n.state == .active)

        arriving.on = false
        n.checkPointer()
        arriving.on = true
        n.checkPointer()
        #expect(n.state == .hidden)
    }
}
