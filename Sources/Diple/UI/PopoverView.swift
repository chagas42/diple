import SwiftUI

struct LinhaPR: View {
    let pr: PR
    let naoLido: Bool
    let acao: () -> Void

    var body: some View {
        Button(action: acao) {
            HStack(alignment: .top, spacing: 9) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(cor)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(pr.repo.split(separator: "/").last.map(String.init) ?? pr.repo)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("#\(pr.numero)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 4)
                        if naoLido {
                            Circle().fill(cor).frame(width: 5, height: 5)
                        }
                        Text(pr.atualizadoEm.formatted(.relative(presentation: .numeric)))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    Text(pr.titulo)
                        .font(.system(size: 12.5, weight: naoLido ? .semibold : .regular))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let c = pr.ultimoComentario {
                        Text("\(c.autor)\(c.onde.map { " em \($0)" } ?? ""): \(c.trecho)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var cor: Color {
        if pr.ci == .falhou { .red }
        else if naoLido { .orange }
        else if pr.aprovado { .green }
        else { .secondary.opacity(0.35) }
    }
}

struct Secao: View {
    let titulo: String
    let prs: [PR]
    let naoLidos: Set<String>
    let abrir: (PR) -> Void

    var body: some View {
        if !prs.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
                ForEach(prs) { pr in
                    LinhaPR(pr: pr, naoLido: naoLidos.contains(pr.chave)) { abrir(pr) }
                }
            }
        }
    }
}

struct PopoverView: View {
    @ObservedObject var modelo: Modelo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            cabecalho

            if let erro = modelo.erro {
                Label(erro, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Secao(titulo: "Precisam de você", prs: modelo.precisamDeVoce,
                          naoLidos: modelo.naoLidos, abrir: modelo.abrir)
                    Secao(titulo: "Seus PRs", prs: Array(modelo.resto.prefix(8)),
                          naoLidos: modelo.naoLidos, abrir: modelo.abrir)

                    if modelo.fila.todos.isEmpty && !modelo.carregando {
                        Text("Nada na fila.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                }
            }
            .frame(maxHeight: 420)

            Divider()
            rodape
        }
        .padding(12)
        .frame(width: 340)
    }

    private var cabecalho: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("⟩")
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(modelo.contador > 0 ? .orange : .secondary)
            Text("\(modelo.contador)")
                .font(.system(size: 26, weight: .semibold))
            Text(modelo.contador == 1 ? "precisa de você" : "precisam de você")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            if modelo.carregando {
                ProgressView().controlSize(.small)
            } else {
                Button { Task { await modelo.atualizar() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Sincronizar agora")
            }
        }
    }

    private var rodape: some View {
        HStack(spacing: 8) {
            if let s = modelo.ultimaSync {
                Text("sync \(s.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            if !modelo.permissao {
                Text("· sem permissão de aviso")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button("Limpar") { modelo.limparTudo() }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
            Button("Sair") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
        }
    }
}
