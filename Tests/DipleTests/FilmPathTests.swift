import CoreGraphics
import Testing
@testable import Diple

struct FilmPathTests {
    static let path = HumanPath(start: CGPoint(x: 0, y: 100), legs: [
        .init(to: CGPoint(x: 100, y: 100), seconds: 1, pause: 0.5),
        .init(to: CGPoint(x: 100, y: 0), seconds: 1),
    ], tremor: 0)

    @Test func easingStartsAndEndsAtRestAndPassesTheMiddle() {
        #expect(HumanPath.ease(0) == 0)
        #expect(HumanPath.ease(1) == 1)
        #expect(abs(HumanPath.ease(0.5) - 0.5) < 1e-9)
        #expect(HumanPath.ease(0.01) < 0.001)
        #expect(HumanPath.ease(0.99) > 0.999)
    }

    @Test func theDurationCountsEveryLegAndPause() {
        #expect(Self.path.duration == 2.5)
    }

    @Test func itArrivesAtEachWaypointAndHoldsItThroughThePause() {
        let arrived = Self.path.at(1.0), paused = Self.path.at(1.4)
        #expect(abs(arrived.x - 100) < 0.01 && abs(arrived.y - 100) < 0.01)
        #expect(abs(paused.x - 100) < 0.01 && abs(paused.y - 100) < 0.01)
        let end = Self.path.at(2.5)
        #expect(abs(end.x - 100) < 0.01 && abs(end.y) < 0.01)
    }

    @Test func itNeverJumpsBetweenFrames() {
        var last = Self.path.at(0)
        for frame in 1...150 {
            let p = Self.path.at(Double(frame) / 60)
            #expect(hypot(p.x - last.x, p.y - last.y) < 6)
            last = p
        }
    }

    @Test func aLegBowsOffTheStraightLine() {
        let middle = Self.path.at(0.5)
        #expect(abs(middle.y - 100) > 1)
    }

    @Test func framesMapToTimeAtTheChosenRate() {
        let clock = FilmClock(fps: 60)
        #expect(clock.time(ofFrame: 90) == 1.5)
        #expect(clock.frames(in: 2.2) == 132)
        #expect(clock.frames(in: 0) == 1)
    }

    @Test func theCutoutHugsTheNotchWithRoundedBottomCorners() {
        let path = FilmStage.cutout(CGSize(width: 200, height: 38), centeredAt: 340)
        let box = path.boundingBoxOfPath
        #expect(abs(box.width - 206) < 0.01)
        #expect(abs(box.height - 38) < 0.01)
        #expect(path.contains(CGPoint(x: 340, y: 37)))
        #expect(!path.contains(CGPoint(x: 241, y: 37.5)))
    }
}
