import Combine
import CoreGraphics
import Foundation
import SwiftUI

struct Pull: Equatable, VectorArithmetic {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var strength: CGFloat = 0

    static let none = Pull()
    static var zero: Pull { .none }

    var isNone: Bool { strength < 0.005 }

    static func + (a: Pull, b: Pull) -> Pull {
        Pull(x: a.x + b.x, y: a.y + b.y, strength: a.strength + b.strength)
    }

    static func - (a: Pull, b: Pull) -> Pull {
        Pull(x: a.x - b.x, y: a.y - b.y, strength: a.strength - b.strength)
    }

    mutating func scale(by k: Double) {
        let k = CGFloat(k)
        x *= k; y *= k; strength *= k
    }

    var magnitudeSquared: Double { Double(x * x + y * y + strength * strength) }
}

@MainActor
final class PullState: ObservableObject {
    @Published var pull = Pull.none
    private(set) var snaps = false

    func show(_ next: Pull) {
        if pull.isNone, !next.isNone, !snaps {
            snaps = true
            pull = Pull(x: next.x, y: next.y, strength: 0)
            return
        }
        snaps = false
        pull = next
    }
}

struct Gravity {
    var reach: CGFloat = 110
    var belowTheBar: CGFloat = 16
    var smoothing: CGFloat = 0.18

    private(set) var smoothed = Pull.none

    func target(pointer p: CGPoint, shape: CGRect) -> Pull {
        let local = CGPoint(x: p.x - shape.minX, y: shape.maxY - p.y)
        let nearest = CGPoint(x: min(max(p.x, shape.minX), shape.maxX),
                              y: min(max(p.y, shape.minY), shape.maxY))
        let distance = hypot(p.x - nearest.x, p.y - nearest.y)
        guard distance > 0, distance < reach else { return Pull(x: local.x, y: local.y, strength: 0) }
        let under = min(1, max(0, (shape.minY - p.y) / belowTheBar))
        let clearOfTheBar = under * under * (3 - 2 * under)
        return Pull(x: local.x, y: local.y, strength: pow(1 - distance / reach, 2) * clearOfTheBar)
    }

    mutating func follow(_ target: Pull) -> Pull {
        if smoothed.isNone, target.isNone {
            smoothed = Pull(x: target.x, y: target.y, strength: 0)
            return .none
        }
        if smoothed.isNone { smoothed.x = target.x; smoothed.y = target.y }
        smoothed = smoothed + (target - smoothed).scaled(by: Double(smoothing))
        return smoothed.isNone ? Pull(x: smoothed.x, y: smoothed.y, strength: 0) : smoothed
    }
}

enum Blob {
    static let reachOfTouch: CGFloat = 90
    static let maxStretch: CGFloat = 12
    static let spacing: CGFloat = 3
    static let sideways: CGFloat = 0.35

    struct Point: Equatable {
        var at: CGPoint
        var normal: CGVector
    }

    static func outline(width w: CGFloat, height h: CGFloat, radius b: CGFloat) -> [Point] {
        var points: [Point] = []
        func line(_ a: CGPoint, _ z: CGPoint, normal: CGVector) {
            let n = max(1, Int((hypot(z.x - a.x, z.y - a.y) / spacing).rounded()))
            for i in 0..<n {
                let t = CGFloat(i) / CGFloat(n)
                points.append(Point(at: CGPoint(x: a.x + (z.x - a.x) * t, y: a.y + (z.y - a.y) * t), normal: normal))
            }
        }
        func arc(center c: CGPoint, from: CGFloat, to: CGFloat) {
            let n = max(6, Int((b * abs(to - from) / 1.5).rounded()))
            for i in 0..<n {
                let a = from + (to - from) * CGFloat(i) / CGFloat(n)
                points.append(Point(at: CGPoint(x: c.x + cos(a) * b, y: c.y + sin(a) * b),
                                    normal: CGVector(dx: cos(a), dy: sin(a))))
            }
        }
        line(CGPoint(x: w, y: 0), CGPoint(x: w, y: h - b), normal: CGVector(dx: 1, dy: 0))
        arc(center: CGPoint(x: w - b, y: h - b), from: 0, to: .pi / 2)
        line(CGPoint(x: w - b, y: h), CGPoint(x: b, y: h), normal: CGVector(dx: 0, dy: 1))
        arc(center: CGPoint(x: b, y: h - b), from: .pi / 2, to: .pi)
        line(CGPoint(x: 0, y: h - b), CGPoint(x: 0, y: 0), normal: CGVector(dx: -1, dy: 0))
        points.append(Point(at: CGPoint(x: 0, y: 0), normal: CGVector(dx: -1, dy: 0)))
        return points
    }

    static func drawn(_ points: [Point], height h: CGFloat, toward pull: Pull) -> [CGPoint] {
        let a = CGPoint(x: pull.x, y: pull.y)
        let sigma2 = 2 * reachOfTouch * reachOfTouch
        let peak = maxStretch * pull.strength
        func field(_ q: CGPoint) -> CGFloat {
            let dx = a.x - q.x, dy = a.y - q.y
            return peak * exp(-(dx * dx + dy * dy) / sigma2)
        }
        return points.map { point in
            let p = point.at
            let t0 = min(1, max(0, p.y / h))
            let anchored = t0 * t0 * (3 - 2 * t0)
            guard anchored > 0 else { return p }
            var t: CGFloat = 0
            for _ in 0..<4 {
                t = field(CGPoint(x: p.x + point.normal.dx * t, y: p.y + point.normal.dy * t)) * anchored
            }
            return CGPoint(x: p.x + point.normal.dx * t * sideways, y: p.y + point.normal.dy * t)
        }
    }

    static func path(through q: [CGPoint]) -> Path {
        var path = Path()
        guard let first = q.first, let last = q.last else { return path }
        path.move(to: CGPoint(x: last.x, y: 0))
        path.addLine(to: first)
        for i in 0..<(q.count - 1) {
            let p0 = q[max(0, i - 1)], p1 = q[i], p2 = q[i + 1], p3 = q[min(q.count - 1, i + 2)]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        path.closeSubpath()
        return path
    }
}
