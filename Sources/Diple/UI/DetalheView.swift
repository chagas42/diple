import SwiftUI

struct DetalheView: View {
    @ObservedObject var modelo: Modelo
    let pr: PR

    enum Secao: String, CaseIterable, Identifiable {
        case conversa = "Conversa"
        case mapa = "Visão geral"
        case ia = "Review da IA"
        var id: String { rawValue }
    }
    @State private var secao: Secao = .conversa

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                cabecalho
                Divider()
                estatisticas

                Picker("", selection: $secao) {
                    ForEach(Secao.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch secao {
                case .conversa:
                    if pr.threads.isEmpty {
                        semThreads
                    } else {
                        ForEach(pr.threads) { t in
                            ThreadView(modelo: modelo, thread: t)
                        }
                    }
                case .mapa:
                    MapaView(modelo: modelo, pr: pr)
                case .ia:
                    RevisaoIAView(modelo: modelo, pr: pr)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: pr.chave) { secao = .conversa }
        .toolbar {
            ToolbarItem {
                Button {
                    modelo.abrir(pr)
                } label: {
                    Label("Abrir no GitHub", systemImage: "arrow.up.forward.square")
                }
                .help("Abrir no GitHub")
            }
        }
    }

    private var cabecalho: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                selo
                Text("\(pr.repo) #\(pr.numero)")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(pr.titulo)
                .font(.system(size: 20, weight: .semibold))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(pr.autor) abriu · atualizado \(pr.atualizadoEm.formatted(.relative(presentation: .numeric)))")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var selo: some View {
        let (texto, cor): (String, Color) =
            if pr.ci == .falhou { ("Check falhou", .red) }
            else if pr.aprovado { ("Aprovado", .green) }
            else if pr.rascunho { ("Rascunho", .secondary) }
            else if !pr.threads.isEmpty { ("Conversa aberta", .orange) }
            else { ("Aberto", .blue) }
        Text(texto)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(cor.opacity(0.14), in: Capsule())
            .foregroundStyle(cor)
    }

    private var estatisticas: some View {
        HStack(spacing: 8) {
            rotulo(pr.ci == .falhou ? "checks vermelhos" : pr.ci == .passou ? "checks verdes" : "checks rodando")
            Text("·").foregroundStyle(.tertiary)
            rotulo("\(pr.threads.count) conversa\(pr.threads.count == 1 ? "" : "s") aberta\(pr.threads.count == 1 ? "" : "s")")
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(.secondary)
    }

    private func rotulo(_ t: String) -> some View { Text(t) }

    private var semThreads: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle").foregroundStyle(.green)
            Text("Nenhuma conversa de gente aberta neste PR.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

struct ThreadView: View {
    @ObservedObject var modelo: Modelo
    let thread: PR.ThreadPR

    @State private var resposta = ""
    @State private var erro: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(thread.arquivo)
                    .font(.system(size: 11.5, design: .monospaced))
                if let l = thread.linha {
                    Text("linha \(l)")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Resolver") {
                    Task { erro = await modelo.resolver(thread: thread.id) }
                }
                .buttonStyle(.link)
                .font(.system(size: 11.5))
                .disabled(modelo.enviando)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.quaternary.opacity(0.4))

            if let h = thread.diffHunk {
                DiffHunkView(hunk: h)
                    .padding(.horizontal, 4)
                Divider()
            }

            ForEach(thread.comentarios) { fala in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(fala.autor)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(fala.ehBot ? .secondary : .primary)
                        if fala.ehBot {
                            Text("bot")
                                .font(.system(size: 9.5, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                        }
                        Text(fala.quando.formatted(.relative(presentation: .numeric)))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    Text(fala.texto)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .opacity(fala.ehBot ? 0.55 : 1)
                Divider()
            }

            VStack(alignment: .leading, spacing: 7) {
                if let e = erro {
                    Label(e, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 8) {
                    TextField("Responder nesta thread…", text: $resposta, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                    Button("Comentar") {
                        Task {
                            erro = await modelo.responder(thread: thread.id, texto: resposta)
                            if erro == nil { resposta = "" }
                        }
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(resposta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || modelo.enviando)
                }
            }
            .padding(12)
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1))
    }
}
