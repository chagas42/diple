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

            if rodando || !modelo.progressoIA.isEmpty {
                progresso
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

    private var progresso: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if rodando {
                    ProgressView().controlSize(.small)
                    Text("Revisando")
                        .font(.system(size: 12, weight: .semibold))
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Terminado")
                        .font(.system(size: 12, weight: .semibold))
                }
                Spacer()
                if let i = modelo.inicioIA {
                    Text(i, style: .timer)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.bottom, 8)

            ForEach(modelo.progressoIA) { linha in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: linha.concluido ? "checkmark" : "circle.dotted")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(linha.concluido ? .green : .secondary)
                        .frame(width: 12)
                    Text(linha.texto)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(linha.concluido ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if linha.repeticoes > 1 {
                        Text("×\(linha.repeticoes)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
            }

            if rodando {
                Text("O git leva uns 3 segundos. O resto é o Claude lendo o "
                     + "repositório — costuma ir de 30 s a 2 min.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
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
