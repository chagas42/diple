import AppKit
import SwiftUI

@MainActor
enum Film {
    static var isOn: Bool { CommandLine.arguments.contains("--film") || option("--video") != nil }

    static var outputDirectory: URL? {
        guard let i = CommandLine.arguments.firstIndex(of: "--film") else { return nil }
        if i + 1 < CommandLine.arguments.count, !CommandLine.arguments[i + 1].hasPrefix("--") {
            return URL(fileURLWithPath: CommandLine.arguments[i + 1])
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("diple-film")
    }

    static func option(_ name: String) -> String? {
        guard let i = CommandLine.arguments.firstIndex(of: name), i + 1 < CommandLine.arguments.count else { return nil }
        let value = CommandLine.arguments[i + 1]
        return value.hasPrefix("--") ? nil : value
    }

    struct Beat {
        let name: String
        let seconds: Double
        var pointer: HumanPath?
        var act: @MainActor () -> Void = {}
    }

    struct Scene {
        let name: String
        let crop: FilmCrop
        let beats: (NotchController, AppModel) -> [Beat]
    }

    static let scenes: [Scene] = [tour, approach, focus, focusBreathing, focusPomodoro, focusMoon, rankingModes]

    static func roll(notch: NotchController, model: AppModel) async {
        let video = option("--video").map { URL(fileURLWithPath: $0) }
        let pngs = outputDirectory
        let scene = option("--scene").flatMap { name in scenes.first { $0.name == name } } ?? tour
        let fps = option("--fps").flatMap(Double.init) ?? (video == nil ? 20 : 60)
        let composites = option("--composite").map { $0 != "off" } ?? (video != nil)
        let crop = option("--crop").flatMap(FilmCrop.init(rawValue:)) ?? scene.crop
        let clock = FilmClock(fps: fps)

        notch.fullScreen = { false }
        notch.fullScreenArriving = { false }
        notch.pointer = { CGPoint(x: -10_000, y: -10_000) }
        notch.refreshIdle()

        guard let view = notch.panelContentView else { exit(1) }
        let g = NotchGeometry.current()
        let stage = FilmStage(
            view: view.bounds.size,
            scale: view.window?.backingScaleFactor ?? 2,
            cutout: g.hasNotch ? CGSize(width: g.notchWidth, height: g.topInset) : nil,
            crop: crop,
            backdrop: composites ? option("--backdrop").flatMap(image(at:)) : nil
        )
        if let pngs { try? FileManager.default.createDirectory(at: pngs, withIntermediateDirectories: true) }
        let encoder: FilmVideo?
        do {
            encoder = try video.map { url in
                let size = stage.pixelSize
                return try FilmVideo(url: url, width: size.width, height: size.height, fps: Int(fps))
            }
        } catch {
            say("cannot write \(video?.path ?? ""): \(error.localizedDescription)")
            exit(1)
        }

        let cutout = g.rect(g.closed)
        let start = ContinuousClock.now
        var index = 0
        for beat in scene.beats(notch, model) {
            beat.act()
            say("beat \(beat.name): state=\(notch.state) tab=\(model.notchTab)")
            for frame in 0..<clock.frames(in: beat.seconds) {
                var tip: CGPoint?
                if let path = beat.pointer {
                    let p = path.at(clock.time(ofFrame: frame))
                    tip = CGPoint(x: stage.view.width / 2 + p.x, y: p.y)
                    let onScreen = CGPoint(x: cutout.midX + p.x, y: cutout.maxY - p.y)
                    notch.pointer = { onScreen }
                    notch.followPointer()
                }
                try? await ContinuousClock().sleep(until: start + .seconds(clock.time(ofFrame: index)))
                guard let panel = snapshot(view) else { continue }
                let shown = composites ? stage.compose(panel, pointer: tip) : panel
                guard let shown else { continue }
                if let pngs { write(shown, to: pngs.appendingPathComponent(String(format: "frame-%05d.png", index))) }
                encoder?.append(shown, frame: index)
                index += 1
            }
        }

        do {
            try await encoder?.finish()
        } catch {
            say("video failed: \(error.localizedDescription)")
            exit(1)
        }
        let late = start.duration(to: .now) - .seconds(clock.time(ofFrame: index))
        if late > .milliseconds(250) { say("capture fell \(late) behind; animations run faster than the pointer") }
        say("\(index) frames at \(Int(fps)) fps -> \([video?.path, pngs?.path].compactMap { $0 }.joined(separator: ", "))")
        exit(0)
    }

    private static func snapshot(_ view: NSView) -> CGImage? {
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        return rep.cgImage
    }

    private static func write(_ image: CGImage, to url: URL) {
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func image(at path: String) -> CGImage? {
        NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func say(_ line: String) {
        FileHandle.standardOutput.write((line + "\n").data(using: .utf8)!)
    }
}

extension Film {
    static let tour = Scene(name: "tour", crop: .panel) { notch, model in [
        Beat(name: "01-resting", seconds: 1.6) { notch.closeNow() },
        Beat(name: "02-open", seconds: 2.2) {
            model.notchTab = .queue
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
    ] }

    static let approachPath = HumanPath(start: CGPoint(x: -230, y: 210), legs: [
        .init(to: CGPoint(x: -120, y: 100), seconds: 0.9, pause: 0.1),
        .init(to: CGPoint(x: -48, y: 50), seconds: 0.6, pause: 0.15),
        .init(to: CGPoint(x: -30, y: 28), seconds: 0.45, pause: 0.6),
        .init(to: CGPoint(x: -10, y: 125), seconds: 0.8, pause: 0.4),
        .init(to: CGPoint(x: 60, y: 175), seconds: 0.7, pause: 0.6),
        .init(to: CGPoint(x: 140, y: 150), seconds: 0.6, pause: 0.3),
        .init(to: CGPoint(x: 330, y: 365), seconds: 0.8, pause: 1.3),
    ])

    static let approach = Scene(name: "approach", crop: .panel) { notch, model in [
        Beat(name: "01-resting", seconds: 0.5) {
            model.notchTab = .queue
            model.tab = .needsYou
            notch.closeNow()
        },
        Beat(name: "02-approach", seconds: approachPath.duration, pointer: approachPath),
    ] }

    static let openEye = CGPoint(x: -299, y: 19)

    static func still(at p: CGPoint, for seconds: Double) -> HumanPath {
        HumanPath(start: p, legs: [.init(to: CGPoint(x: p.x + 2, y: p.y + 1), seconds: seconds)], bow: 0)
    }

    static let toTheEye = HumanPath(start: CGPoint(x: -140, y: 230), legs: [
        .init(to: CGPoint(x: -60, y: 60), seconds: 0.8, pause: 0.1),
        .init(to: CGPoint(x: -40, y: 24), seconds: 0.35, pause: 0.5),
        .init(to: CGPoint(x: -150, y: 150), seconds: 0.7, pause: 0.35),
        .init(to: openEye, seconds: 0.8, pause: 0.5),
    ])

    static func focusing(_ look: FocusLook) -> Scene {
        Scene(name: look == .terminal ? "focus" : "focus-\(look.rawValue)", crop: .panel) { notch, model in [
            Beat(name: "01-resting", seconds: 0.6) {
                model.notchTab = .queue
                model.tab = .needsYou
                model.settings.focusLook = look
                notch.closeNow()
            },
            Beat(name: "02-to-the-eye", seconds: toTheEye.duration, pointer: toTheEye),
            Beat(name: "03-poke-in", seconds: 4.2, pointer: still(at: openEye, for: 4.2)) { notch.poke() },
            Beat(name: "04-poke-out", seconds: 3.4, pointer: still(at: openEye, for: 3.4)) { notch.poke() },
        ] }
    }

    static let focus = focusing(.terminal)
    static let focusBreathing = focusing(.breathing)
    static let focusPomodoro = focusing(.pomodoro)

    static let moon = CGPoint(x: -295, y: 19)

    static let focusMoon = Scene(name: "focus-moon", crop: .panel) { notch, model in [
        Beat(name: "01-open", seconds: 1.2, pointer: still(at: moon, for: 1.2)) {
            model.notchTab = .queue
            model.settings.showsEye = false
            model.settings.focusLook = .terminal
            notch.open()
        },
        Beat(name: "02-moon-in", seconds: 4, pointer: still(at: moon, for: 4)) { model.focus.toggle() },
        Beat(name: "03-moon-out", seconds: 3, pointer: still(at: moon, for: 3)) { model.focus.toggle() },
    ] }

    static let rankingModes = Scene(name: "ranking-modes", crop: .panel) { notch, model in [
        Beat(name: "01-board", seconds: 2.4) {
            model.settings.rankingMode = .team
            model.rankPeriod = .week
            model.notchTab = .ranking
            notch.open()
        },
        Beat(name: "02-pace", seconds: 3) { model.settings.rankingMode = .pace },
        Beat(name: "03-pace-month", seconds: 2.4) { model.rankPeriod = .month },
    ] }
}

