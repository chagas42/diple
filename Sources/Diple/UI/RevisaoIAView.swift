import SwiftUI
import AppKit

struct RevisaoIAView: View {
    @ObservedObject var modelo: Modelo
    let pr: PR

    private var achados: [Achado] { modelo.achados[pr.chave] ?? [] }
    private var rodando: Bool { modelo.revisandoIA == pr.chave }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            cabecalho

            if rodando, let passo = modelo.passoIA {
                progresso(passo)
            } else if case .falhou(let msg) = modelo.passoIA, achados.isEmpty, !rodando {
                Label(msg, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !achados.isEmpty {
                aviso
                ForEach(achados) { a in
                    CartaoAchado(achado: a) { modelo.descartarAchado(pr, a) }
                }
            } else if !rodando, case .pronto = modelo.passoIA {
                Label("A IA não encontrou nada que valesse apontar.",
                      systemImage: "checkmark.circle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var cabecalho: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkles").foregroundStyle(.purple)
            Text("Review da IA").font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                Task { await modelo.revisarComIA(pr) }
            } label: {
                Label(achados.isEmpty ? "Revisar com IA" : "Revisar de novo",
                      systemImage: "play.fill")
            }
            .disabled(modelo.revisandoIA != nil)
            .keyboardShortcut("r", modifiers: [.command, .option])
        }
    }

    private func progresso(_ passo: PassoIA) -> some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.small)
            Text(descricao(passo))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func descricao(_ p: PassoIA) -> String {
        switch p {
        case .preparando(let t): t
        case .pensando:          "pensando…"
        case .ferramenta(let t): t
        case .pronto(let l):     "\(l.count) apontamentos"
        case .falhou(let m):     m
        }
    }

    private var aviso: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill").font(.system(size: 10))
            Text("Rascunho local. A sessão roda sem `gh` e sem escrita — publicar é sempre você.")
                .font(.system(size: 11))
            Spacer()
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct CartaoAchado: View {
    let achado: Achado
    let aoDescartar: () -> Void
    @State private var copiado = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                selo(achado.categoria.rotulo, cor: corCategoria)
                selo(achado.veredito.rotulo,
                     cor: achado.veredito == .confirmado ? .green : .secondary)
                Spacer()
                Text(achado.onde)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text(achado.resumo)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(achado.detalhe)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let c = achado.cenario, !c.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text("CENÁRIO")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.purple)
                        .padding(.top, 1)
                    Text(c)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            }

            HStack(spacing: 8) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(achado.markdown, forType: .string)
                    copiado = true
                } label: {
                    Label(copiado ? "Copiado" : "Copiar comentário",
                          systemImage: copiado ? "checkmark" : "doc.on.doc")
                }
                Spacer()
                Button("Descartar", action: aoDescartar)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1))
    }

    private var corCategoria: Color {
        switch achado.categoria {
        case .correcao:      .red
        case .simplificacao: .purple
        case .eficiencia:    .blue
        case .teste:         .teal
        case .outro:         .secondary
        }
    }

    private func selo(_ t: String, cor: Color) -> some View {
        Text(t.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(cor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(cor)
    }
}
