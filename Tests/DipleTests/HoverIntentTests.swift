import Foundation
import Testing
@testable import Diple

struct HoverIntentTests {
    static let zone = CGRect(x: 1000, y: 1000, width: 185, height: 32)
    static let center = CGPoint(x: 1092, y: 1016)
    static let away = CGPoint(x: 1092, y: 700)
    static let doorstep = CGPoint(x: 1092, y: 996)
    static let justInside = CGPoint(x: 1092, y: 1002)
    static let tick = 1.0 / 30

    final class Run {
        var intent = HoverIntent()
        var now = Date(timeIntervalSinceReferenceDate: 0)

        init(_ opening: HoverOpening = .afterPause) { intent.opening = opening }

        @discardableResult
        func at(_ p: CGPoint, pressed: Bool = false) -> HoverIntent.Decision {
            now += HoverIntentTests.tick
            return intent.feed(at: now, pointer: p, zone: HoverIntentTests.zone, pressed: pressed)
        }

        func arrive() -> HoverIntent.Decision {
            _ = rest(at: HoverIntentTests.doorstep, for: 0.2)
            return at(HoverIntentTests.justInside)
        }

        func rest(at p: CGPoint, for seconds: Double) -> [HoverIntent.Decision] {
            (0..<Int((seconds / HoverIntentTests.tick).rounded())).map { _ in at(p) }
        }

        func move(from a: CGPoint, to b: CGPoint, in seconds: Double) -> [HoverIntent.Decision] {
            let steps = max(1, Int((seconds / HoverIntentTests.tick).rounded()))
            return (1...steps).map { i in
                let u = CGFloat(i) / CGFloat(steps)
                return at(CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u))
            }
        }
    }

    @Test func restingOnTheNotchOpensOnceTheDwellHasPassed() throws {
        let run = Run()
        #expect(run.arrive() == .hold)
        let first = try #require(run.rest(at: Self.justInside, for: 0.3).firstIndex(of: .open))
        #expect(Double(first + 1) * Self.tick >= HoverIntent.dwell - 0.001)
        #expect(Double(first + 1) * Self.tick < HoverIntent.dwell + Self.tick)
    }

    @Test func leavingBeforeTheDwellStartsItOver() {
        let run = Run()
        #expect(run.arrive() == .hold)
        #expect(!run.rest(at: Self.justInside, for: 0.1).contains(.open))
        #expect(run.at(Self.doorstep) == .hold)
        #expect(run.at(Self.justInside) == .hold)
        #expect(!run.rest(at: Self.justInside, for: 0.1).contains(.open))
    }

    @Test func aFastPassAcrossTheNotchNeverOpensIt() {
        let run = Run()
        let left = CGPoint(x: 700, y: 1016), right = CGPoint(x: 1500, y: 1016)
        run.at(left)
        #expect(!run.move(from: left, to: right, in: 0.5).contains(.open))
        #expect(!run.move(from: right, to: left, in: 0.5).contains(.open))
    }

    @Test func aPassJustOverTheThresholdStaysClosedForAsLongAsItLastsInside() {
        let run = Run()
        let left = CGPoint(x: 900, y: 1016), right = CGPoint(x: 1300, y: 1016)
        run.at(left)
        let seconds = Double((right.x - left.x) / (HoverIntent.fastest * 1.2))
        #expect(!run.move(from: left, to: right, in: seconds).contains(.open))
    }

    @Test func aSlowArrivalOpens() {
        let run = Run()
        run.at(Self.away)
        let decisions = run.move(from: Self.away, to: Self.center, in: 1.2) + run.rest(at: Self.center, for: 0.3)
        #expect(decisions.contains(.open))
    }

    @Test func stoppingInsideAfterAFastEntryOpensAfterTheDwell() throws {
        let run = Run()
        let left = CGPoint(x: 600, y: 1016)
        run.at(left)
        #expect(!run.move(from: left, to: Self.center, in: 0.2).contains(.open))
        let first = try #require(run.rest(at: Self.center, for: 0.5).firstIndex(of: .open))
        #expect(Double(first + 1) * Self.tick >= HoverIntent.dwell)
    }

    @Test func aClickOnTheNotchOpensAtOnce() {
        let run = Run()
        run.at(Self.doorstep)
        #expect(run.at(Self.justInside, pressed: true) == .open)
    }

    @Test func holdingTheButtonWhileDraggingAcrossIsNotAClick() {
        let run = Run()
        run.at(Self.doorstep, pressed: true)
        #expect(run.at(Self.justInside, pressed: true) == .hold)
    }

    @Test func instantlyOpensOnTheFirstTickInside() {
        let run = Run(.instantly)
        let left = CGPoint(x: 700, y: 1016)
        run.at(left)
        #expect(run.move(from: left, to: CGPoint(x: 1500, y: 1016), in: 0.3).contains(.open))
    }

    @Test func theZoneIsTheRestingShapeAndTheCutoutWithTheTopPixel() {
        let notch = CGRect(x: 1000, y: 1000, width: 185, height: 32)
        let shape = CGRect(x: 958, y: 1000, width: 269, height: 32)
        let zone = HoverIntent.zone(notch: notch, shape: shape)
        #expect(zone.contains(CGPoint(x: 960, y: 1010)))
        #expect(zone.contains(CGPoint(x: 1092, y: 1032)))
        #expect(!zone.contains(CGPoint(x: 1092, y: 995)))
    }
}

@MainActor
@Suite struct NotchHoverIntentTests {
    final class Spot {
        var at: CGPoint
        var now = Date(timeIntervalSinceReferenceDate: 0)
        var pressed = false
        init(_ at: CGPoint) { self.at = at }
    }

    var cutout: CGRect {
        let g = NotchGeometry.current()
        return g.rect(g.closed)
    }

    var doorstep: CGPoint { CGPoint(x: cutout.midX, y: cutout.minY - 4) }
    var justInside: CGPoint { CGPoint(x: cutout.midX, y: cutout.minY + 2) }

    func notch(_ spot: Spot, opening: HoverOpening = .afterPause) -> NotchController {
        let n = NotchController()
        n.pointer = { spot.at }
        n.clock = { spot.now }
        n.pressed = { spot.pressed }
        n.fullScreen = { false }
        n.fullScreenArriving = { false }
        n.opensOnHover = { opening }
        n.closeNow()
        n.checkPointer()
        return n
    }

    func tick(_ n: NotchController, _ spot: Spot, times: Int = 1) {
        for _ in 0..<times {
            spot.now += 1.0 / 30
            n.checkPointer()
        }
    }

    @Test func theNotchWaitsForThePointerToSettleBeforeOpening() {
        let spot = Spot(doorstep)
        let n = notch(spot)
        spot.at = justInside
        tick(n, spot)
        #expect(n.state == .active)
        tick(n, spot, times: 5)
        #expect(n.state == .open)
    }

    @Test func aClickOnTheNotchOpensItWithoutWaiting() {
        let spot = Spot(doorstep)
        let n = notch(spot)
        spot.at = justInside
        spot.pressed = true
        tick(n, spot)
        #expect(n.state == .open)
    }

    @Test func instantlyOpensOnTheFirstTick() {
        let spot = Spot(doorstep)
        let n = notch(spot, opening: .instantly)
        spot.at = justInside
        tick(n, spot)
        #expect(n.state == .open)
    }

    @Test func theLeanTowardThePointerDoesNotWidenWhereItOpens() {
        let spot = Spot(doorstep)
        let n = notch(spot, opening: .instantly)
        n.pulling.show(Pull(x: 0, y: 40, strength: 1))
        n.pulling.show(Pull(x: 0, y: 40, strength: 1))
        spot.at = CGPoint(x: cutout.midX, y: cutout.minY - Blob.maxStretch / 2)
        tick(n, spot, times: 10)
        #expect(n.state == .active)
        spot.at = justInside
        tick(n, spot)
        #expect(n.state == .open)
    }
}
