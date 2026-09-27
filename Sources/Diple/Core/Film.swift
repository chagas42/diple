import AppKit
import SwiftUI

@MainActor
enum Film {
    static var isOn: Bool { CommandLine.arguments.contains("--film") }

    static var outputDirectory: URL {
        if let i = CommandLine.arguments.firstIndex(of: "--film"),
           i + 1 < CommandLine.arguments.count,
           !CommandLine.arguments[i + 1].hasPrefix("--") {
            return URL(fileURLWithPath: CommandLine.arguments[i + 1])
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("diple-film")
    }

    private static let fps: Double = 20

    struct Beat {
        let name: String
        let seconds: Double
        let act: @MainActor () -> Void
    }

    static func roll(notch: NotchController, model: AppModel) async {
        let dir = outputDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let beats: [Beat] = [
            Beat(name: "01-resting", seconds: 1.6) { notch.closeNow() },
            Beat(name: "02-open", seconds: 2.2) {
                model.tab = .needsYou
                notch.open()
            },
            Beat(name: "03-tab-mine", seconds: 1.8) { model.tab = .mine },
            Beat(name: "04-tab-reviewing", seconds: 1.8) { model.tab = .reviewing },
            Beat(name: "05-team", seconds: 2.2) { model.notchTab = .team },
            Beat(name: "06-rank-week", seconds: 2.4) {
                model.notchTab = .ranking
                model.rankPeriod = .week
            },
            Beat(name: "07-rank-month", seconds: 2.0) { model.rankPeriod = .month },
            Beat(name: "08-rank-quarter", seconds: 2.0) { model.rankPeriod = .quarter },
            Beat(name: "09-activity", seconds: 2.6) { model.notchTab = .activity },
            Beat(name: "10-queue", seconds: 1.4) { model.notchTab = .queue },
            Beat(name: "11-alert", seconds: 3.2) {
                guard let pr = Demo.queue.mine.first(where: { $0.lastComment != nil }),
                      let c = pr.lastComment else { return }
                notch.alert(Event(
                    id: "film/replied",
                    kind: .repliedToYou,
                    key: pr.key,
                    url: pr.url,
                    title: "\(c.author) replied to you",
                    body: "\(pr.key) · \(c.excerpt)",
                    threadId: c.threadId
                ))
            },
            Beat(name: "12-settle", seconds: 1.6) { notch.closeNow() },
        ]

        var index = 0
        for beat in beats {
            beat.act()
            FileHandle.standardOutput.write(
                "beat \(beat.name): state=\(notch.state) tab=\(model.notchTab)\n".data(using: .utf8)!
            )
            let frames = Int(beat.seconds * fps)
            for _ in 0..<frames {
                try? await Task.sleep(for: .milliseconds(Int(1000 / fps)))
                capture(notch: notch, to: dir, index: &index)
            }
        }

        FileHandle.standardOutput.write(
            "\(index) frames -> \(dir.path)\n".data(using: .utf8)!
        )
        exit(0)
    }

    private static func capture(notch: NotchController, to dir: URL, index: inout Int) {
        guard let view = notch.panelContentView else { return }
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let name = String(format: "frame-%05d.png", index)
        try? png.write(to: dir.appendingPathComponent(name))
        index += 1
    }
}
