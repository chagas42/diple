import SwiftUI
import AppKit

enum MapLayout {
    static let gap: CGFloat = 22
    static let top: CGFloat = 70

    static func size(_ kind: MapNode.Kind) -> CGSize {
        switch kind {
        case .domain:   CGSize(width: 210, height: 84)
        case .changed:  CGSize(width: 232, height: 104)
        case .affected: CGSize(width: 232, height: 104)
        case .context:  CGSize(width: 244, height: 130)
        }
    }

    static func column(_ kind: MapNode.Kind) -> CGFloat {
        switch kind {
        case .domain:   135
        case .changed:  455
        case .affected: 795
        case .context:  1145
        }
    }

    static func initial(_ map: PRMap, keeping old: [String: CGPoint]) -> [String: CGPoint] {
        var out: [String: CGPoint] = [:]
        let changed = map.nodes(.changed)
        let owner = Dictionary(
            map.edges.filter { $0.kind == .contains }.map { ($0.to, $0.from) },
            uniquingKeysWith: { f, _ in f }
        )

        var y = top
        var domainYs: [String: [CGFloat]] = [:]
        for d in map.nodes(.domain) {
            for m in changed where owner[m.id] == d.id {
                let h = size(.changed).height
                out[m.id] = CGPoint(x: column(.changed), y: y + h / 2)
                domainYs[d.id, default: []].append(y + h / 2)
                y += h + gap
            }
        }

        var domainCursor = top
        for d in map.nodes(.domain) {
            let h = size(.domain).height
            let ys = domainYs[d.id] ?? []
            let wanted = ys.isEmpty ? domainCursor + h / 2 : ys.reduce(0, +) / CGFloat(ys.count)
            let placed = max(wanted, domainCursor + h / 2)
            out[d.id] = CGPoint(x: column(.domain), y: placed)
            domainCursor = placed + h / 2 + gap
        }

        for kind in [MapNode.Kind.affected, .context] {
            let incoming = Dictionary(
                map.edges.filter { $0.kind == (kind == .affected ? .feels : .explains) }.map { ($0.to, $0.from) },
                uniquingKeysWith: { f, _ in f }
            )
            let h = size(kind).height
            let wanted = map.nodes(kind).map { n -> (MapNode, CGFloat) in
                let source = incoming[n.id].flatMap { out[$0]?.y }
                return (n, source ?? .greatestFiniteMagnitude)
            }
            .sorted { $0.1 < $1.1 }

            var cursor = top
            for (n, want) in wanted {
                let desired = want == .greatestFiniteMagnitude ? cursor + h / 2 : want
                let placed = max(desired, cursor + h / 2)
                out[n.id] = CGPoint(x: column(kind), y: placed)
                cursor = placed + h / 2 + gap
            }
        }

        for (id, p) in old where out[id] != nil { out[id] = p }
        return out
    }

    static func bounds(_ positions: [String: CGPoint], nodes: [MapNode]) -> CGSize {
        var w: CGFloat = 400
        var h: CGFloat = 240
        for n in nodes {
            guard let p = positions[n.id] else { continue }
            let s = size(n.kind)
            w = max(w, p.x + s.width / 2 + 60)
            h = max(h, p.y + s.height / 2 + 60)
        }
        return CGSize(width: w, height: h)
    }
}

enum StackPalette {
    static let colors: [Color] = [.blue, .teal, .orange, .pink, .green, .indigo, .brown]

    static func color(_ pr: Int, in stack: [Int]) -> Color {
        guard let i = stack.firstIndex(of: pr) else { return .secondary }
        return colors[i % colors.count]
    }
}

extension MapNode.Kind {
    var tint: Color {
        switch self {
        case .domain:   .indigo
        case .changed:  .blue
        case .affected: .orange
        case .context:  .purple
        }
    }

    var icon: String {
        switch self {
        case .domain:   "square.stack.3d.up"
        case .changed:  "pencil.line"
        case .affected: "dot.radiowaves.left.and.right"
        case .context:  "book.closed"
        }
    }

    var legend: String {
        switch self {
        case .domain:   "domain"
        case .changed:  "changed by the diff"
        case .affected: "unchanged, but feels it"
        case .context:  "context you need to judge"
        }
    }
}

struct MapCanvasView: View {
    @ObservedObject var model: AppModel
    let map: PRMap
    let focus: Int?
    var fill = false
    var onExpand: (() -> Void)?

    @State private var positions: [String: CGPoint] = [:]
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var dragOrigin: [String: CGPoint] = [:]
    @State private var panOrigin: CGSize?
    @State private var zoomOrigin: CGFloat?
    @State private var viewport: CGSize = .zero
    @State private var hovered: String?
    @State private var fitted = false

    private var index: [String: MapNode] {
        Dictionary(map.nodes.map { ($0.id, $0) }, uniquingKeysWith: { f, _ in f })
    }

    private var lit: Set<String> {
        guard let h = hovered else { return [] }
        var s: Set<String> = [h]
        for e in map.edges where e.from == h || e.to == h {
            s.insert(e.from)
            s.insert(e.to)
        }
        return s
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color(nsColor: .underPageBackgroundColor).opacity(0.35)
                    .contentShape(Rectangle())
                    .gesture(panGesture)

                board
                    .scaleEffect(zoom, anchor: .topLeading)
                    .offset(pan)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.2)))
            .overlay(alignment: .topTrailing) { controls.padding(10) }
            .simultaneousGesture(magnify)
            .onAppear {
                viewport = geo.size
                load()
            }
            .onChange(of: geo.size) { _, s in
                viewport = s
                if !fitted { fit() }
            }
            .onChange(of: map) { _, _ in load() }
        }
        .frame(minHeight: fill ? 360 : 480, maxHeight: fill ? .infinity : 480)
    }

    private var board: some View {
        let size = MapLayout.bounds(positions, nodes: map.nodes)
        let highlighted = lit
        return ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in drawEdges(ctx, highlighted: highlighted) }
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)

            ForEach(map.nodes) { n in
                let s = MapLayout.size(n.kind)
                MapNodeCard(
                    node: n, stack: map.stack, focus: focus,
                    lit: highlighted.contains(n.id),
                    dimmed: !highlighted.isEmpty && !highlighted.contains(n.id)
                )
                .frame(width: s.width, height: s.height)
                .onTapGesture {
                    model.openNode(n, in: map, forceWeb: NSEvent.modifierFlags.contains(.option))
                }
                .gesture(drag(n))
                .onHover { inside in
                    if inside { hovered = n.id } else if hovered == n.id { hovered = nil }
                }
                .help(help(n))
                .position(positions[n.id] ?? CGPoint(x: MapLayout.column(n.kind), y: MapLayout.top))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var controls: some View {
        HStack(spacing: 2) {
            button("minus.magnifyingglass", "Zoom out") { zoom = max(zoom / 1.2, 0.3) }
            Text("\(Int((zoom * 100).rounded()))%")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40)
            button("plus.magnifyingglass", "Zoom in") { zoom = min(zoom * 1.2, 2) }
            Divider().frame(height: 14)
            button("arrow.up.left.and.down.right.magnifyingglass", "Fit to view") { fit() }
            button("rectangle.3.group", "Tidy the layout") {
                positions = MapLayout.initial(map, keeping: [:])
                model.saveLayout(positions, for: map)
                fit()
            }
            if let onExpand {
                Divider().frame(height: 14)
                button("arrow.up.left.and.arrow.down.right", "Open in its own window", action: onExpand)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
    }

    private func button(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11.5)).frame(width: 24, height: 20)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func help(_ n: MapNode) -> String {
        guard let p = n.path else { return n.title }
        if n.isDirectory { return "\(p)\nClick opens it on GitHub" }
        return "\(p)\nClick opens in \(model.settings.openIn.label), ⌥-click opens GitHub. Drag to move."
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                let o = panOrigin ?? pan
                if panOrigin == nil { panOrigin = o }
                pan = CGSize(width: o.width + v.translation.width, height: o.height + v.translation.height)
            }
            .onEnded { _ in panOrigin = nil }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                let o = zoomOrigin ?? zoom
                if zoomOrigin == nil { zoomOrigin = o }
                zoom = min(max(o * v.magnification, 0.3), 2)
            }
            .onEnded { _ in zoomOrigin = nil }
    }

    private func drag(_ n: MapNode) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { v in
                let start = dragOrigin[n.id] ?? positions[n.id] ?? .zero
                if dragOrigin[n.id] == nil { dragOrigin[n.id] = start }
                let s = MapLayout.size(n.kind)
                positions[n.id] = CGPoint(
                    x: max(start.x + v.translation.width / zoom, s.width / 2 + 8),
                    y: max(start.y + v.translation.height / zoom, s.height / 2 + 8)
                )
            }
            .onEnded { _ in
                dragOrigin[n.id] = nil
                model.saveLayout(positions, for: map)
            }
    }

    private func load() {
        positions = MapLayout.initial(map, keeping: model.mapLayouts[map.layoutKey] ?? positions)
        fitted = false
        fit()
    }

    private func fit() {
        guard viewport.width > 0, viewport.height > 0 else { return }
        let b = MapLayout.bounds(positions, nodes: map.nodes)
        let z = min(viewport.width / b.width, viewport.height / b.height, 1)
        zoom = max(z, 0.3)
        pan = CGSize(
            width: max((viewport.width - b.width * zoom) / 2, 0),
            height: max((viewport.height - b.height * zoom) / 2, 0)
        )
        fitted = true
    }

    private func drawEdges(_ ctx: GraphicsContext, highlighted: Set<String>) {
        let idx = index
        for e in map.edges {
            guard let a = positions[e.from], let b = positions[e.to],
                  let na = idx[e.from], let nb = idx[e.to] else { continue }
            let sa = MapLayout.size(na.kind)
            let sb = MapLayout.size(nb.kind)
            let sameColumn = abs(a.x - b.x) < sa.width / 2
            let forward = sameColumn || a.x <= b.x
            let p0: CGPoint
            let p1: CGPoint
            let c0: CGPoint
            let c1: CGPoint
            let tip: CGFloat
            if sameColumn {
                p0 = CGPoint(x: a.x + sa.width / 2, y: a.y)
                p1 = CGPoint(x: b.x + sb.width / 2, y: b.y)
                c0 = CGPoint(x: p0.x + 60, y: p0.y)
                c1 = CGPoint(x: p1.x + 60, y: p1.y)
                tip = 7
            } else {
                p0 = CGPoint(x: a.x + (forward ? sa.width / 2 : -sa.width / 2), y: a.y)
                p1 = CGPoint(x: b.x + (forward ? -sb.width / 2 : sb.width / 2), y: b.y)
                let dx = max(abs(p1.x - p0.x) * 0.5, 40) * (forward ? 1 : -1)
                c0 = CGPoint(x: p0.x + dx, y: p0.y)
                c1 = CGPoint(x: p1.x - dx, y: p1.y)
                tip = forward ? -7 : 7
            }

            var path = Path()
            path.move(to: p0)
            path.addCurve(to: p1, control1: c0, control2: c1)

            let on = highlighted.contains(e.from) && highlighted.contains(e.to)
            let dim = !highlighted.isEmpty && !on
            let color = edgeColor(e.kind).opacity(dim ? 0.15 : (on ? 0.95 : 0.5))
            ctx.stroke(path, with: .color(color), style: StrokeStyle(
                lineWidth: on ? 2 : 1.2, lineCap: .round,
                dash: e.kind == .explains ? [5, 3] : []
            ))

            var head = Path()
            head.move(to: p1)
            head.addLine(to: CGPoint(x: p1.x + tip, y: p1.y - 4))
            head.addLine(to: CGPoint(x: p1.x + tip, y: p1.y + 4))
            head.closeSubpath()
            ctx.fill(head, with: .color(color))

            if let label = e.label, !label.isEmpty, !dim {
                let mid = CGPoint(
                    x: (p0.x + 3 * c0.x + 3 * c1.x + p1.x) / 8,
                    y: (p0.y + 3 * c0.y + 3 * c1.y + p1.y) / 8 - 8
                )
                ctx.draw(
                    Text(label).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary),
                    at: mid
                )
            }
        }
    }

    private func edgeColor(_ kind: MapEdge.Kind) -> Color {
        switch kind {
        case .contains: .secondary
        case .relates:  .blue
        case .feels:    .orange
        case .explains: .purple
        }
    }
}

struct MapNodeCard: View {
    let node: MapNode
    let stack: [Int]
    let focus: Int?
    let lit: Bool
    let dimmed: Bool

    var body: some View {
        let tint = node.kind.tint
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: node.kind.icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(tint)
                Text(node.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let d = node.diff {
                    Text(d)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(node.kind == .changed ? tint : .secondary)
                }
            }
            if !node.subtitle.isEmpty {
                Text(node.subtitle)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Text(node.detail)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(node.kind == .context ? 4 : 2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if stack.count > 1 {
                    ForEach(node.prs, id: \.self) { n in
                        let c = StackPalette.color(n, in: stack)
                        Text("#\(n)")
                            .font(.system(size: 9, weight: n == focus ? .bold : .medium, design: .monospaced))
                            .foregroundStyle(c)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(c.opacity(n == focus ? 0.22 : 0.1), in: Capsule())
                    }
                }
                Spacer(minLength: 0)
                if node.path != nil {
                    Image(systemName: node.isDirectory ? "globe" : "arrow.up.forward.square")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor))
                RoundedRectangle(cornerRadius: 10).fill(tint.opacity(node.kind == .changed ? 0.1 : 0.05))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10).strokeBorder(
                tint.opacity(lit ? 0.9 : 0.4),
                style: StrokeStyle(lineWidth: lit ? 2 : 1, dash: node.kind == .context ? [5, 3] : [])
            )
        )
        .shadow(color: .black.opacity(lit ? 0.18 : 0.06), radius: lit ? 8 : 3, y: 1)
        .opacity(dimmed ? 0.45 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}
