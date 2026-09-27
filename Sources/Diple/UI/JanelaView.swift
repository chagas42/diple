import SwiftUI

struct JanelaView: View {
    @ObservedObject var modelo: Modelo

    var body: some View {
        NavigationSplitView {
            barraLateral
                .navigationSplitViewColumnWidth(min: 200, ideal: 232, max: 280)
        } content: {
            lista
                .navigationSplitViewColumnWidth(min: 340, ideal: 420, max: 520)
        } detail: {
            if let pr = modelo.selecionado {
                DetalheView(modelo: modelo, pr: pr)
            } else {
                ContentUnavailableView(
                    "Escolha um pull request",
                    systemImage: "chevron.right",
                    description: Text("A fila à esquerda mostra o que espera por você.")
                )
            }
        }
        .navigationTitle("Diple")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await modelo.atualizar() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(modelo.carregando)
                .help("Sincronizar agora")
            }
        }
    }

    private var barraLateral: some View {
        List(selection: Binding(get: { modelo.aba }, set: { modelo.aba = $0 ?? .esperando })) {
            Section("Fila") {
                ForEach(Modelo.Aba.allCases) { aba in
                    HStack {
                        Label(aba.titulo, systemImage: aba.icone)
                        Spacer()
                        Text("\(modelo.contagem(aba))")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .tag(aba)
                }
            }
            Section("Repositórios") {
                ForEach(repos, id: \.0) { nome, quantos in
                    HStack {
                        Text(nome)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer()
                        Text("\(quantos)")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var repos: [(String, Int)] {
        Dictionary(grouping: modelo.fila.todos, by: \.repo)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
            .prefix(8)
            .map { $0 }
    }

    private var lista: some View {
        List(modelo.prs(modelo.aba), selection: Binding(
            get: { modelo.selecionado?.chave },
            set: { chave in modelo.selecionado = modelo.prs(modelo.aba).first { $0.chave == chave } }
        )) { pr in
            LinhaJanela(pr: pr, naoLido: modelo.naoLidos.contains(pr.chave))
                .tag(pr.chave)
        }
        .navigationTitle(modelo.aba.titulo)
        .overlay {
            if modelo.prs(modelo.aba).isEmpty && !modelo.carregando {
                ContentUnavailableView("Nada aqui", systemImage: "checkmark.circle")
            }
        }
    }
}

struct LinhaJanela: View {
    let pr: PR
    let naoLido: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: glifo)
                .font(.system(size: 13))
                .foregroundStyle(cor)
                .frame(width: 16)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(pr.titulo)
                    .font(.system(size: 13, weight: naoLido ? .semibold : .regular))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text("\(pr.repo.split(separator: "/").last.map(String.init) ?? pr.repo) #\(pr.numero)")
                        .font(.system(size: 11, design: .monospaced))
                    if let c = pr.ultimoComentario {
                        Text("· \(c.autor)\(c.onde.map { " em \($0)" } ?? "")")
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 4) {
                Text(pr.atualizadoEm.formatted(.relative(presentation: .numeric)))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                if !pr.threads.isEmpty {
                    Label("\(pr.threads.count)", systemImage: "bubble.left")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var glifo: String {
        if pr.ci == .falhou { "xmark.circle.fill" }
        else if pr.aprovado { "checkmark.circle.fill" }
        else if pr.rascunho { "circle.dashed" }
        else { "arrow.triangle.branch" }
    }

    private var cor: Color {
        if pr.ci == .falhou { .red }
        else if pr.aprovado { .green }
        else if naoLido { .orange }
        else { .secondary }
    }
}
