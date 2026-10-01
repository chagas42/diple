import CoreGraphics
import Foundation

struct HumanPath: Sendable {
    struct Leg: Sendable {
        let to: CGPoint
        let seconds: Double
        var pause: Double = 0
    }

    let start: CGPoint
    let legs: [Leg]
    var bow: CGFloat = 6
    var tremor: CGFloat = 0.4

    var duration: Double { legs.reduce(0) { $0 + $1.seconds + $1.pause } }

    static func ease(_ t: Double) -> Double {
        let t = min(1, max(0, t))
        return t * t * t * (10 - 15 * t + 6 * t * t)
    }

    func at(_ t: Double) -> CGPoint {
        var from = start, clock = 0.0
        for (i, leg) in legs.enumerated() {
            if t < clock + leg.seconds {
                let u = CGFloat(Self.ease((t - clock) / leg.seconds))
                let side: CGFloat = i % 2 == 0 ? 1 : -0.85
                let arc = sin(u * .pi) * bow * side
                let dx = leg.to.x - from.x, dy = leg.to.y - from.y
                let length = max(1, hypot(dx, dy))
                let p = CGPoint(x: from.x + dx * u - dy / length * arc,
                                y: from.y + dy * u + dx / length * arc)
                return shaken(p, at: t)
            }
            clock += leg.seconds
            if t < clock + leg.pause { return shaken(leg.to, at: t) }
            clock += leg.pause
            from = leg.to
        }
        return from
    }

    private func shaken(_ p: CGPoint, at t: Double) -> CGPoint {
        let x = sin(t * 23.1) * 0.6 + sin(t * 41.7 + 1.3) * 0.4
        let y = sin(t * 19.3 + 0.7) * 0.6 + sin(t * 37.9 + 2.1) * 0.4
        return CGPoint(x: p.x + tremor * CGFloat(x), y: max(0, p.y + tremor * CGFloat(y)))
    }
}

struct FilmClock: Sendable {
    let fps: Double

    func time(ofFrame frame: Int) -> Double { Double(frame) / fps }

    func frames(in seconds: Double) -> Int { max(1, Int((seconds * fps).rounded())) }
}
