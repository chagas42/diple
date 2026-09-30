import Combine
import CoreGraphics
import Foundation
import SwiftUI

struct Pull: Equatable, VectorArithmetic {
    var bulge: CGFloat = 0
    var center: CGFloat = 0
    var left: CGFloat = 0
    var right: CGFloat = 0
    var sag: CGFloat = 0

    static let none = Pull()
    static var zero: Pull { .none }

    var isNone: Bool { max(bulge, left, right, sag) < 0.05 }

    static func + (a: Pull, b: Pull) -> Pull {
        Pull(bulge: a.bulge + b.bulge, center: a.center + b.center,
             left: a.left + b.left, right: a.right + b.right, sag: a.sag + b.sag)
    }

    static func - (a: Pull, b: Pull) -> Pull {
        Pull(bulge: a.bulge - b.bulge, center: a.center - b.center,
             left: a.left - b.left, right: a.right - b.right, sag: a.sag - b.sag)
    }

    mutating func scale(by k: Double) {
        let k = CGFloat(k)
        bulge *= k; center *= k; left *= k; right *= k; sag *= k
    }

    var magnitudeSquared: Double {
        Double(bulge * bulge + center * center + left * left + right * right + sag * sag)
    }
}

@MainActor
final class PullState: ObservableObject {
    @Published var pull = Pull.none
}

struct Gravity {
    static var isOn: Bool { ProcessInfo.processInfo.environment["DIPLE_GRAVITY"] == "1" }

    var reach: CGFloat = 110
    var maxBulge: CGFloat = 12
    var maxStretch: CGFloat = 14
    var maxSag: CGFloat = 3
    var halfWidth: CGFloat = 52
    var smoothing: CGFloat = 0.3

    private(set) var smoothed = Pull.none

    func target(pointer p: CGPoint, shape: CGRect) -> Pull {
        let nearest = CGPoint(x: min(max(p.x, shape.minX), shape.maxX),
                              y: min(max(p.y, shape.minY), shape.maxY))
        let distance = hypot(p.x - nearest.x, p.y - nearest.y)
        guard distance > 0, distance < reach else { return .none }
        let strength = pow(1 - distance / reach, 2)

        let dx = p.x - shape.midX
        let below = max(0, (nearest.y - p.y) / distance)
        let lean = min(max(dx / (shape.width / 2), -1), 1) * 0.5
        let across = min(max((p.x - nearest.x) / distance + lean, -1), 1)

        let room = max(0, shape.width / 2 - halfWidth - 12)
        return Pull(
            bulge: maxBulge * strength * below,
            center: min(max(dx, -room), room) * strength.squareRoot(),
            left: maxStretch * strength * max(0, -across),
            right: maxStretch * strength * max(0, across),
            sag: maxSag * strength * below
        )
    }

    mutating func follow(_ target: Pull) -> Pull {
        smoothed = smoothed + (target - smoothed).scaled(by: Double(smoothing))
        if smoothed.isNone, target.isNone { smoothed = .none }
        return smoothed
    }
}
