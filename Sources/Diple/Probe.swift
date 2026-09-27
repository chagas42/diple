import Foundation
import AppKit

enum Probe {
    static func run() async {
        do {
            let queue = try await GitHubClient().fetchQueue()
            dump("MEUS PRS", queue.mine)
            dump("PRA REVISAR", queue.toReview)
            dump("ENVOLVIDO", queue.following)
            print("\nrate limit left: \(queue.rateLimitLeft)")
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func dump(_ title: String, _ prs: [PR]) {
        print("\n## \(title) (\(prs.count))")
        for p in prs.prefix(6) {
            let checks: String = switch p.checks {
            case .passing: "green" case .failing: "RED"
            case .running: "running" case .none: "-"
            }
            var line = "  \(p.key.padding(toLength: min(34, max(p.key.count, 34)), withPad: " ", startingAt: 0))"
            line += " checks=\(checks.padding(toLength: 9, withPad: " ", startingAt: 0))"
            line += p.approved ? " APROVADO" : "         "
            line += " \(p.title.prefix(46))"
            print(line)
            if let c = p.lastComment {
                print("      ↳ \(c.author)\(c.location.map { " at \($0)" } ?? ""): \(c.excerpt.prefix(64))")
            }
        }
    }
}

@MainActor
enum NotchProbe {
    static func run() {
        for (i, t) in NSScreen.screens.enumerated() {
            let g = NotchGeometry(screen: t)
            print("screen \(i): \(Int(t.frame.width))x\(Int(t.frame.height)) scale \(t.backingScaleFactor)")
            print("  safeAreaInsets.top: \(t.safeAreaInsets.top)")
            print("  has notch: \(g.hasNotch)")
            print("  altura do topo: \(g.topInset)")
            print("  largura do recorte: \(g.notchWidth)")
            if let e = t.auxiliaryTopLeftArea, let d = t.auxiliaryTopRightArea {
                print("  left area: \(Int(e.width))  right area: \(Int(d.width))")
            } else {
                print("  auxiliary areas: none (screen has no notch)")
            }
            print("  closed:   \(g.closed)  -> \(g.rect(g.closed))")
            print("  active: \(g.active)  -> \(g.rect(g.active))")
            print("  open:    \(g.open)  -> \(g.rect(g.open))")
            print("  windowFrame fixa: \(g.windowFrame())")
        }
    }
}
