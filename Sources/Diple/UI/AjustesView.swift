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
            PainelConta(modelo: modelo)
                .tabItem { Label("Conta", systemImage: "person.crop.circle") }
        }
        .frame(width: 620, height: 460)
    }
}

// MARK: - Notificações e sons

struct PainelNotificacoes: View {
    @ObservedObject var modelo: Modelo

    var body: some View {
        Form {
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
                            Text(dica(t))
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
                        } label: { Image(systemName: "play.fill") }
                            .disabled(modelo.config.som(t) == nil)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Quando isto acontece")
            } footer: {
                Text("O que fica desligado continua entrando na fila — só não interrompe.")
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

// MARK: - Repositórios

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

// MARK: - Conta

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
