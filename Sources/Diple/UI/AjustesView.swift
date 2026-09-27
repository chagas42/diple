import SwiftUI
import AppKit

struct AjustesView: View {
    @ObservedObject var modelo: Modelo

    var body: some View {
        TabView {
            PainelNotificacoes(modelo: modelo)
                .tabItem { Label("Notificações", systemImage: "bell") }
            PainelRepositorios(modelo: modelo)
                .tabItem { Label("Repositórios", systemImage: "book.closed") }
            PainelClaude(modelo: modelo)
                .tabItem { Label("Claude", systemImage: "sparkles") }
            PainelConta(modelo: modelo)
                .tabItem { Label("Conta", systemImage: "person.crop.circle") }
        }
        .frame(width: 620, height: 460)
    }
}

struct PainelNotificacoes: View {
    @ObservedObject var modelo: Modelo

    var body: some View {
        Form {
            if modelo.silenciandoAgora {
                Section {
                    HStack(spacing: 9) {
                        Image(systemName: "moon.fill").foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("O silêncio está valendo agora")
                                .font(.system(size: 12.5, weight: .semibold))
                            Text("Só quem responde você diretamente passa. "
                                 + "Testar ignora isso de propósito.")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }

            Section {
                ForEach(TipoEvento.allCases, id: \.self) { t in
                    HStack(spacing: 12) {
                        Toggle("", isOn: Binding(
                            get: { modelo.config.avisa(t) },
                            set: { modelo.config.avisa[t.rawValue] = $0 }
                        ))
                        .labelsHidden()

                        VStack(alignment: .leading, spacing: 1) {
                            Text(titulo(t)).font(.system(size: 12.5))
                            HStack(spacing: 5) {
                                Text(dica(t))
                                if modelo.config.som(t) == nil, modelo.config.avisa(t) {
                                    Text("· chega sem som")
                                        .foregroundStyle(.orange)
                                }
                            }
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Picker("", selection: Binding(
                            get: { modelo.config.som(t) ?? "" },
                            set: { modelo.config.sons[t.rawValue] = $0 }
                        )) {
                            Text("Nenhum").tag("")
                            Divider()
                            ForEach(Config.sonsDisponiveis, id: \.self) { s in
                                Text(s).tag(s)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                        .disabled(!modelo.config.avisa(t))

                        Button {
                            if let s = modelo.config.som(t) { NSSound(named: s)?.play() }
                        } label: { Image(systemName: "speaker.wave.2.fill") }
                            .disabled(modelo.config.som(t) == nil)
                            .help("Ouvir só o som")

                        Button("Testar") { Task { await modelo.testar(t) } }
                            .help("Dispara um aviso de verdade, com banner, som e a animação da notch")
                    }
                    .padding(.vertical, 2)
                }
                HStack {
                    Button("Testar todos em sequência") {
                        Task {
                            for t in TipoEvento.allCases where modelo.config.avisa(t) {
                                await modelo.testar(t)
                                try? await Task.sleep(for: .seconds(2.5))
                            }
                        }
                    }
                    Spacer()
                }
            } header: {
                Text("Quando isto acontece")
            } footer: {
                Text("O que fica desligado continua entrando na fila — só não interrompe. "
                     + "Testar dispara um aviso real: banner, som e a notch abrindo.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Section("Silêncio") {
                Toggle("Silenciar fora do horário", isOn: $modelo.config.silencioLigado)
                HStack {
                    Text("Das")
                    Picker("", selection: $modelo.config.silencioDe) {
                        ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                    }.labelsHidden().frame(width: 90)
                    Text("às")
                    Picker("", selection: $modelo.config.silencioAte) {
                        ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                    }.labelsHidden().frame(width: 90)
                    Spacer()
                }
                .disabled(!modelo.config.silencioLigado)
                Toggle("Também nos fins de semana", isOn: $modelo.config.silencioNoFimDeSemana)
                    .disabled(!modelo.config.silencioLigado)
                Text("Quem responde você diretamente fura o silêncio.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func titulo(_ t: TipoEvento) -> String {
        switch t {
        case .responderamVoce: "Responderam você numa conversa"
        case .comentaram:      "Comentaram num PR seu"
        case .pediramReview:   "Pediram sua review"
        case .checkFalhou:     "Um check falhou num PR seu"
        case .aprovaram:       "Aprovaram um PR seu"
        }
    }

    private func dica(_ t: TipoEvento) -> String {
        switch t {
        case .responderamVoce: "O único que fura o silêncio."
        case .comentaram:      "Conversa do PR e comentário inline no código."
        case .pediramReview:   "Direto a você ou por um time seu."
        case .checkFalhou:     "Só na primeira falha; retentativa não repete."
        case .aprovaram:       "Costuma bastar ver quando abrir a fila."
        }
    }
}

struct PainelRepositorios: View {
    @ObservedObject var modelo: Modelo

    private var repos: [(String, Int)] {
        Dictionary(grouping: modelo.fila.todos, by: \.repo)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        Form {
            Section {
                if repos.isEmpty {
                    Text("A fila ainda não carregou.").foregroundStyle(.secondary)
                }
                ForEach(repos, id: \.0) { nome, quantos in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(nome).font(.system(size: 12.5, design: .monospaced))
                            Text("\(quantos) na fila")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("Silenciado", isOn: Binding(
                            get: { modelo.config.silenciados.contains(nome) },
                            set: { on in
                                if on { modelo.config.silenciados.insert(nome) }
                                else { modelo.config.silenciados.remove(nome) }
                            }
                        ))
                    }
                }
            } header: {
                Text("Repositórios na sua fila")
            } footer: {
                Text("Silenciado continua aparecendo na lista; só não gera aviso.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct PainelConta: View {
    @ObservedObject var modelo: Modelo

    var body: some View {
        Form {
            Section("GitHub") {
                LabeledContent("Conta", value: modelo.fila.eu.isEmpty ? "—" : modelo.fila.eu)
                LabeledContent("Token") {
                    Text("emprestado do gh")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Cota restante") {
                    Text("\(modelo.fila.cotaRestante) de 5000")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Text("O Diple não guarda token. Ele chama `gh auth token` a cada requisição.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Section("Sincronização") {
                Picker("A cada", selection: $modelo.config.intervalo) {
                    Text("30 segundos").tag(TimeInterval(30))
                    Text("1 minuto").tag(TimeInterval(60))
                    Text("5 minutos").tag(TimeInterval(300))
                    Text("15 minutos").tag(TimeInterval(900))
                }
                Text("Uma sincronização custa 1 ponto dos 5000 por hora.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Sincronizar agora") { Task { await modelo.atualizar() } }
                        .disabled(modelo.carregando)
                    Spacer()
                    Button("Sair do Diple") { NSApplication.shared.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct PainelClaude: View {
    @ObservedObject var modelo: Modelo

    private var repos: [String] {
        Array(Set(modelo.fila.todos.map(\.repo))).sorted()
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 9) {
                    Circle()
                        .fill(temClaude ? .green : .orange)
                        .frame(width: 7, height: 7)
                    Text(temClaude ? "claude encontrado no PATH"
                                   : "claude não está no PATH")
                    Spacer()
                }
                Picker("Modelo", selection: $modelo.config.modeloIA) {
                    Text("Opus").tag("opus")
                    Text("Sonnet").tag("sonnet")
                    Text("Haiku").tag("haiku")
                }
                Text("O Diple não tem IA própria. Ele chama o claude da sua máquina, "
                     + "com a sua conta e as suas skills. Os tokens contam no seu plano.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } header: {
                Text("Sessão")
            }

            Section {
                HStack(spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LIBERADO")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.green)
                        Text("Read · Grep · Glob\nBash(git diff/log/show/status)")
                            .font(.system(size: 10.5, design: .monospaced))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BLOQUEADO")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.red)
                        Text("Write · Edit · WebFetch\nBash(gh/push/commit/curl)")
                            .font(.system(size: 10.5, design: .monospaced))
                    }
                    Spacer()
                }
            } header: {
                Text("Limites da sessão")
            } footer: {
                Text("Não dá para desligar: a sessão nasce sem as ferramentas de escrita, "
                     + "então a IA não tem como publicar nada.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Section {
                if repos.isEmpty {
                    Text("A fila ainda não carregou.").foregroundStyle(.secondary)
                }
                ForEach(repos, id: \.self) { r in
                    HStack {
                        Text(r).font(.system(size: 12, design: .monospaced))
                        Spacer()
                        if let u = Worktree.localDe(r, configurados: modelo.config.caminhos) {
                            Text(atalho(u.path))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Escolher…") { escolher(r) }
                        }
                    }
                }
            } header: {
                Text("Onde cada repositório está")
            } footer: {
                Text("O Diple procura sozinho em @work, @studies, dev, work, Developer, "
                     + "code e src. Cada review roda num worktree descartável em "
                     + "~/.diple/worktrees — o seu checkout não é tocado.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var temClaude: Bool {
        if ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .contains(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return true
        }
        return which()
    }

    private func which() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["which", "claude"]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus == 0
    }

    private func atalho(_ p: String) -> String {
        p.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    private func escolher(_ repo: String) {
        let painel = NSOpenPanel()
        painel.canChooseDirectories = true
        painel.canChooseFiles = false
        painel.prompt = "Usar esta pasta"
        if painel.runModal() == .OK, let u = painel.url {
            modelo.config.caminhos[repo] = u.path
        }
    }
}
