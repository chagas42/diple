import SwiftUI

struct MapaView: View {
    @ObservedObject var modelo: Modelo
    let pr: PR

    private var mapa: Mapa? { modelo.mapas[pr.chave] }
    private var rodando: Bool { modelo.desenhandoMapa == pr.chave }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let m = mapa {
                proposta(m)
                grafo(m)
                if !m.contexto.isEmpty { faixaContexto(m) }
                legenda
            } else {
                vazio
            }
        }
    }

    private func proposta(_ m: Mapa) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("A PROPOSTA")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await modelo.desenharMapa(pr) }
                } label: { Label("Redesenhar", systemImage: "arrow.clockwise") }
                    .buttonStyle(.link)
                    .font(.system(size: 11.5))
                    .disabled(modelo.desenhandoMapa != nil)
            }
            Text(m.proposta)
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

    private func grafo(_ m: Mapa) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 10) {
                ForEach(m.alterados) { mo in CaixaModulo(modulo: mo, alterado: true) }
            }
            .frame(maxWidth: .infinity)

            VStack {
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text("sente")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(width: 58)

            VStack(spacing: 10) {
                if m.impactados.isEmpty {
                    Text("Nada fora do diff depende disto.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(m.impactados) { mo in CaixaModulo(modulo: mo, alterado: false) }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func faixaContexto(_ m: Mapa) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("O PR NÃO TOCA NISTO, MAS VOCÊ PRECISA CONHECER PRA JULGAR")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.purple)
            HStack(alignment: .top, spacing: 10) {
                ForEach(m.contexto) { c in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(c.titulo)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.purple)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(c.porque)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if let o = c.onde, !o.isEmpty {
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
            item(.blue.opacity(0.12), borda: .blue.opacity(0.5), "alterado pelo PR")
            item(.clear, borda: .secondary.opacity(0.35), "não muda, mas sente")
            item(.purple.opacity(0.06), borda: .purple.opacity(0.35), "contexto que você precisa ter")
            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private func item(_ fundo: Color, borda: Color, _ t: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(fundo)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(borda, lineWidth: 1))
                .frame(width: 13, height: 13)
            Text(t)
        }
    }

    private var vazio: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Veja o que este PR toca antes de revisar")
                .font(.system(size: 14, weight: .semibold))
            Text("O que muda sai do diff. O que **sente** a mudança e o que você "
                 + "precisa conhecer pra julgar saem do seu Claude.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await modelo.desenharMapa(pr) }
            } label: {
                if rodando {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Desenhando…")
                    }
                } else {
                    Label("Desenhar o mapa", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
            }
            .disabled(modelo.desenhandoMapa != nil)
        }
    }
}

struct CaixaModulo: View {
    let modulo: Modulo
    let alterado: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Text(modulo.nome)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(alterado ? Color.blue : .primary)
                Spacer(minLength: 4)
                if let d = modulo.diff {
                    Text(d)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(alterado ? Color.blue : .secondary)
                }
            }
            Text(modulo.caminho)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
            Text(modulo.detalhe)
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
