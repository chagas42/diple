import SwiftUI

struct MapaView: View {
    @ObservedObject var model: AppModel
    let pr: PR

    private var mapa: PRMap? { model.maps[pr.key] }
    private var running: Bool { model.mappingKey == pr.key }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let m = mapa {
                intent(m)
                grafo(m)
                if !m.context.isEmpty { faixaContexto(m) }
                legenda
            } else {
                empty
            }
        }
    }

    private func intent(_ m: PRMap) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("THE INTENT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await model.buildMap(pr) }
                } label: { Label("Redraw", systemImage: "arrow.clockwise") }
                    .buttonStyle(.link)
                    .font(.system(size: 11.5))
                    .disabled(model.mappingKey != nil)
            }
            Text(m.intent)
                .font(.system(size: 15, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 7) {
                ForEach(m.deltas, id: \.self) { d in
                    Text(d)
                        .font(.system(size: 11.5))
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(.quaternary.opacity(0.5), in: Capsule())
                }
            }
        }
    }

    private func grafo(_ m: PRMap) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 10) {
                ForEach(m.changed) { mo in ModuleBox(modulo: mo, alterado: true) }
            }
            .frame(maxWidth: .infinity)

            VStack {
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text("feels it")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(width: 58)

            VStack(spacing: 10) {
                if m.affected.isEmpty {
                    Text("Nothing outside the diff depends on this.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(m.affected) { mo in ModuleBox(modulo: mo, alterado: false) }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func faixaContexto(_ m: PRMap) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("THIS PR DOES NOT TOUCH THIS, BUT YOU NEED IT TO JUDGE")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.purple)
            HStack(alignment: .top, spacing: 10) {
                ForEach(m.context) { c in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(c.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.purple)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(c.why)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if let o = c.location, !o.isEmpty {
                            Text(o)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                    .background(.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.purple.opacity(0.28),
                                          style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    )
                }
            }
        }
    }

    private var legenda: some View {
        HStack(spacing: 16) {
            item(.blue.opacity(0.12), border: .blue.opacity(0.5), "changed by this PR")
            item(.clear, border: .secondary.opacity(0.35), "unchanged, but affected")
            item(.purple.opacity(0.06), border: .purple.opacity(0.35), "context you need to have")
            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private func item(_ fundo: Color, border: Color, _ t: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(fundo)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(border, lineWidth: 1))
                .frame(width: 13, height: 13)
            Text(t)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("See what this PR touches before you review")
                .font(.system(size: 14, weight: .semibold))
            Text("What changes comes from the diff. What **feels** the change and what you "
                 + "need to know to judge come from your Claude.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await model.buildMap(pr) }
            } label: {
                if running {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Drawing…")
                    }
                } else {
                    Label("Draw the map", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
            }
            .disabled(model.mappingKey != nil)
        }
    }
}

struct ModuleBox: View {
    let modulo: Module
    let alterado: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Text(modulo.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(alterado ? Color.blue : .primary)
                Spacer(minLength: 4)
                if let d = modulo.diff {
                    Text(d)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(alterado ? Color.blue : .secondary)
                }
            }
            Text(modulo.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
            Text(modulo.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alterado ? Color.blue.opacity(0.1) : .clear,
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(alterado ? Color.blue.opacity(0.45) : .secondary.opacity(0.3),
                        lineWidth: alterado ? 1.5 : 1)
        )
    }
}
