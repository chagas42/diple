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
        List(selection: Binding(
            get: { modelo.selecionado?.chave },
            set: { chave in modelo.selecionado = modelo.prs(modelo.aba).first { $0.chave == chave } }
        )) {
            ForEach(modelo.prs(modelo.aba).emPilhas()) { pilha in
                if pilha.empilhada {
                    Section {
                        ForEach(Array(pilha.prs.enumerated()), id: \.element.chave) { i, pr in
                            LinhaJanela(
                                pr: pr,
                                naoLido: modelo.naoLidos.contains(pr.chave),
                                degrau: i + 1,
                                degraus: pilha.prs.count
                            )
                            .tag(pr.chave)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.3.layers.3d.down.right")
                                .font(.system(size: 10))
                            Text("Pilha de \(pilha.prs.count)")
                                .font(.system(size: 10.5, weight: .semibold))
                            Text(pilha.base?.repo.split(separator: "/").last.map(String.init) ?? "")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("leia de baixo pra cima")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                } else if let pr = pilha.prs.first {
                    LinhaJanela(pr: pr, naoLido: modelo.naoLidos.contains(pr.chave))
                        .tag(pr.chave)
                }
            }
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
    var degrau: Int? = nil
    var degraus: Int? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let d = degrau, let n = degraus {
                Text("\(d)/\(n)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                    .padding(.top, 3)
            }

            AvatarPR(url: pr.avatarAutor, login: pr.autor)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(pr.titulo)
                    .font(.system(size: 13, weight: naoLido ? .semibold : .regular))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Image(systemName: glifo)
                        .font(.system(size: 10))
                        .foregroundStyle(cor)
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

struct AvatarPR: View {
    let url: URL?
    let login: String
    var lado: CGFloat = 24

    var body: some View {
        AsyncImage(url: url) { fase in
            switch fase {
            case .success(let img): img.resizable().scaledToFill()
            default:
                ZStack {
                    Color.secondary.opacity(0.18)
                    Text(String(login.prefix(2)).uppercased())
                        .font(.system(size: lado * 0.34, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: lado, height: lado)
        .clipShape(Circle())
    }
}
