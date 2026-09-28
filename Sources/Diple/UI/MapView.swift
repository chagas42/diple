import SwiftUI

struct MapaView: View {
    @ObservedObject var model: AppModel
    let pr: PR

    private var map: PRMap? { model.maps[pr.key] }
    private var running: Bool { model.isMapping(pr.key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let m = map {
                MapHeader(model: model, pr: pr, map: m, running: running)
                if let run = model.mapRun(pr.key) { MapProgressView(run: run) }
                if let n = model.mapNotice(pr.key) { notice(n) }
                MapCanvasView(model: model, map: m, focus: pr.number) {
                    Windows.shared.openMap(model, pr)
                }
                MapLegend(map: m)
            } else if let run = model.mapRun(pr.key) {
                MapProgressView(run: run)
            } else {
                empty
            }
        }
    }

    private func notice(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("See what this PR touches before you review")
                .font(.system(size: 14, weight: .semibold))
            Text("The domains and modules that changed come from the diff and appear at once. What **feels** the change and what you need to know to judge it come from your Claude, and the timer shows how long that part should take for a PR this size.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await model.buildMap(pr) }
            } label: {
                Label(model.stackOf(pr).count > 1 ? "Draw the map of the stack" : "Draw the map",
                      systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
            .disabled(model.isMapping(pr.key))
        }
    }
}

struct MapHeader: View {
    @ObservedObject var model: AppModel
    let pr: PR
    let map: PRMap
    let running: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(map.stack.count > 1 ? "THE INTENT OF THE STACK" : "THE INTENT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                if !map.enriched {
                    Text("diff only")
                        .font(.system(size: 9.5, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                FeedbackButton(model: model, feature: .map)
                Button {
                    Task { await model.buildMap(pr) }
                } label: { Label(map.enriched ? "Redraw" : "Draw with Claude", systemImage: "arrow.clockwise") }
                    .buttonStyle(.link)
                    .font(.system(size: 11.5))
                    .disabled(model.isMapping(pr.key))
            }
            Text(Inline.markdown(map.intent.isEmpty ? pr.title : map.intent))
                .font(.system(size: 15, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 7) {
                chip(sizeLine, mono: true)
            }
            if !map.deltas.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(map.deltas, id: \.self) { delta in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                            Text(Inline.markdown(delta))
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, 2)
            }
            if map.stack.count > 1 {
                HStack(spacing: 6) {
                    ForEach(map.stack, id: \.self) { n in
                        let c = StackPalette.color(n, in: map.stack)
                        HStack(spacing: 4) {
                            Circle().fill(c).frame(width: 7, height: 7)
                            Text("#\(n)")
                                .font(.system(size: 10.5, weight: n == pr.number ? .bold : .regular, design: .monospaced))
                        }
                        if n != map.stack.last {
                            Image(systemName: "arrow.right").font(.system(size: 8.5)).foregroundStyle(.tertiary)
                        }
                    }
                    Text("reading order").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var sizeLine: String {
        let s = map.size
        return "\(s.files) files · +\(s.additions) −\(s.deletions) · \(s.domains) domain\(s.domains == 1 ? "" : "s")"
    }

    private func chip(_ text: String, mono: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 11.5, design: mono ? .monospaced : .default))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(.quaternary.opacity(0.5), in: Capsule())
    }
}

struct MapProgressView: View {
    let run: MapRun
    @State private var showMath = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let now = ctx.date
            let remaining = run.remaining(now)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(run.phase).font(.system(size: 12, weight: .medium))
                    if let t = run.lastTool {
                        Text(t)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(run.overdue(now)
                         ? "longer than expected"
                         : remaining < 3 ? "almost there" : "≈ \(Self.clock(remaining)) left")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .contentTransition(.numericText())
                }
                ProgressView(value: run.progress(now))
                    .progressViewStyle(.linear)
                HStack(spacing: 10) {
                    Text("\(Self.clock(run.elapsed(now))) elapsed · estimated \(Self.clock(run.estimate.seconds))"
                         + (run.toolCalls > 0 ? " · \(run.toolCalls)/\(run.expectedTools) steps" : ""))
                    Spacer()
                    Button(showMath ? "Hide the math" : "How is this estimated?") { showMath.toggle() }
                        .buttonStyle(.link)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

                if showMath { math(now) }
            }
            .padding(12)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func math(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(run.estimate.parts) { p in
                HStack {
                    Text(p.label)
                    Spacer()
                    Text("\(MapTiming.fmt(p.seconds))s")
                }
            }
            Divider()
            HStack {
                Text("sum")
                Spacer()
                Text("\(MapTiming.fmt(run.estimate.raw))s")
            }
            HStack {
                Text(run.estimate.calibration)
                Spacer()
                Text("\(MapTiming.fmt(run.estimate.seconds))s")
            }
            Text("While it runs, the estimate moves toward the pace of the session itself: "
                 + "\(run.toolCalls) of about \(run.expectedTools) steps done, projecting "
                 + "\(Self.clock(run.total(now))) in total.")
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
        }
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundStyle(.secondary)
    }

    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s < 60 ? "\(s)s" : "\(s / 60)m \(String(format: "%02d", s % 60))s"
    }
}

struct MapLegend: View {
    let map: PRMap

    var body: some View {
        HStack(spacing: 14) {
            ForEach(MapNode.Kind.allCases, id: \.self) { k in
                HStack(spacing: 5) {
                    Image(systemName: k.icon).font(.system(size: 10)).foregroundStyle(k.tint)
                    Text(k.legend)
                }
            }
            Spacer()
            if map.hidden > 0 {
                Text("\(map.hidden) smaller module\(map.hidden == 1 ? "" : "s") not drawn")
            }
            Text("hover to read · drag to arrange · scroll or pinch to zoom · click to open")
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
    }
}

struct MapWindowView: View {
    @ObservedObject var model: AppModel
    let pr: PR

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let m = model.maps[pr.key] {
                MapHeader(model: model, pr: pr, map: m, running: model.isMapping(pr.key))
                if let run = model.mapRun(pr.key) { MapProgressView(run: run) }
                MapCanvasView(model: model, map: m, focus: pr.number, fill: true, onExpand: nil)
                MapLegend(map: m)
            } else {
                Text("No map for \(pr.key) yet.").foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(minWidth: 760, minHeight: 520)
    }
}

enum Inline {
    static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
