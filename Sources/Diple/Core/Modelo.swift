import Foundation
import SwiftUI
import AppKit

@MainActor
final class Modelo: ObservableObject {
    static let compartilhado = Modelo()

    /// A notch se pendura aqui pra abrir sozinha quando algo chega.
    var aoEvento: ((Evento) -> Void)?
    var aoContadorMudar: (() -> Void)?

    @Published private(set) var fila = Fila()
    @Published private(set) var carregando = false
    @Published private(set) var erro: String?
    @Published private(set) var ultimaSync: Date?
    @Published private(set) var permissao = false
    @Published private(set) var naoLidos: Set<String> = []

    // Abas do painel expandido
    @Published var abaNotch: AbaNotch = .fila
    @Published private(set) var equipe: [Pessoa] = []
    @Published private(set) var rank: [LinhaRank] = []
    @Published private(set) var ritmo: [DiaRitmo] = []
    @Published private(set) var seguindo: Set<String> = []
    @Published private(set) var carregandoAba = false
    // Review pela sua própria sessão do Claude
    @Published private(set) var achados: [String: [Achado]] = [:]
    @Published private(set) var passoIA: PassoIA?
    @Published private(set) var revisandoIA: String?
    @Published private(set) var mapas: [String: Mapa] = [:]
    @Published private(set) var desenhandoMapa: String?

    @Published var config = Config() {
        didSet {
            guard config != oldValue else { return }
            store.guardarConfig(config)
            notificador.config = config
            if config.intervalo != oldValue.intervalo { religarTimer() }
        }
    }

    enum AbaNotch: String, CaseIterable, Identifiable {
        case fila, time, rank, ritmo
        var id: String { rawValue }
        var icone: String {
            switch self {
            case .fila:  "tray.full"
            case .time:  "person.2"
            case .rank:  "trophy"
            case .ritmo: "square.grid.3x3"
            }
        }
        var titulo: String {
            switch self {
            case .fila:  "Fila"
            case .time:  "Time"
            case .rank:  "Rank"
            case .ritmo: "Ritmo"
            }
        }
    }

    // Seleção da janela
    @Published var aba: Aba = .esperando
    @Published var selecionado: PR?
    @Published private(set) var enviando = false

    enum Aba: String, CaseIterable, Identifiable {
        case esperando, meus, revisando, observando
        var id: String { rawValue }
        var titulo: String {
            switch self {
            case .esperando:  "Esperando você"
            case .meus:       "Seus PRs"
            case .revisando:  "Revisando"
            case .observando: "Observando"
            }
        }
        var icone: String {
            switch self {
            case .esperando:  "tray.full"
            case .meus:       "arrow.triangle.branch"
            case .revisando:  "bubble.left.and.bubble.right"
            case .observando: "eye"
            }
        }
    }

    private let cliente = GitHubClient()
    private let store = Store()
    private let notificador = Notificador()
    private var timer: Timer?



    private var iniciado = false

    func iniciar() {
        guard !iniciado else { return }
        iniciado = true
        notificador.instalar()
        notificador.aoMudar = { [weak self] in await self?.atualizar() }
        naoLidos = store.estado.naoLidos
        seguindo = store.estado.seguindo
        config = store.estado.config
        notificador.config = config

        Task {
            permissao = await notificador.autorizado()
            if !permissao { permissao = await notificador.pedirPermissao() }
            await atualizar()
        }

        religarTimer()

        // Dormir e acordar deixa a fila velha; sincroniza ao voltar.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.atualizar() }
        }
    }

    /// Uma sincronização custa 1 ponto dos 5000 por hora, então 60s gasta 60.
    private func religarTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: config.intervalo, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.atualizar() }
        }
    }

    func atualizar() async {
        guard !carregando else { return }
        carregando = true
        defer { carregando = false }

        do {
            let nova = try await cliente.buscarFila()
            let eventos = store.diferenca(nova, meuLogin: nova.eu)
                .filter { e in
                    let repo = e.chave.split(separator: "#").first.map(String.init) ?? ""
                    return !config.silenciados.contains(repo)
                }
            fila = nova
            if let s = selecionado {
                selecionado = nova.todos.first { $0.chave == s.chave } ?? s
            }
            naoLidos = store.estado.naoLidos
            ultimaSync = Date()
            erro = nil
            await notificador.postar(eventos)
            aoContadorMudar?()
            if let primeiro = eventos.first(where: { $0.tipo.interrompe }) {
                aoEvento?(primeiro)
            }
        } catch {
            erro = error.localizedDescription
        }
    }

    /// A organização sai dos repositórios que já estão na fila — nada fixo
    /// no código.
    var org: String {
        let donos = fila.todos.compactMap { $0.repo.split(separator: "/").first.map(String.init) }
        let contagem = Dictionary(grouping: donos, by: { $0 }).mapValues(\.count)
        return contagem.max { $0.value < $1.value }?.key ?? ""
    }

    func seguir(_ login: String) {
        store.alternarSeguir(login)
        seguindo = store.estado.seguindo
    }

    /// Carrega o que a aba precisa, uma vez. Nada disso entra na sincronização
    /// de 60s — é dado que muda devagar.
    func carregarAba(_ aba: AbaNotch) async {
        guard !org.isEmpty, !carregandoAba else { return }
        switch aba {
        case .fila: return
        case .time where !equipe.isEmpty: return
        case .rank where !rank.isEmpty: return
        case .ritmo where !ritmo.isEmpty: return
        default: break
        }

        carregandoAba = true
        defer { carregandoAba = false }
        do {
            if equipe.isEmpty { equipe = try await cliente.buscarEquipe(org: org) }
            switch aba {
            case .rank:
                let desde = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
                rank = try await cliente.buscarRank(org: org, pessoas: equipe, desde: desde)
            case .ritmo:
                ritmo = try await cliente.buscarRitmo(org: org, login: fila.eu)
            default: break
            }
        } catch {
            erro = error.localizedDescription
        }
    }

    /// Roda o Claude da SUA máquina, com a SUA conta, num worktree
    /// descartável. Nada é publicado: a sessão nasce sem as ferramentas de
    /// escrita e sem o gh.
    func revisarComIA(_ pr: PR) async {
        guard revisandoIA == nil else { return }
        revisandoIA = pr.chave
        passoIA = .preparando("procurando o repositório")
        defer { revisandoIA = nil }

        guard let origem = Worktree.localDe(pr.repo, configurados: config.caminhos) else {
            passoIA = .falhou("não achei \(pr.repo) na sua máquina. Aponte a pasta em Ajustes.")
            return
        }

        var destino: URL?
        do {
            passoIA = .preparando("preparando worktree descartável")
            let w = try await Worktree.preparar(origem: origem, repo: pr.repo, pr: pr.numero)
            destino = w

            for await passo in RevisorIA().revisar(pr: pr, em: w, modelo: config.modeloIA) {
                passoIA = passo
                if case .pronto(let lista) = passo { achados[pr.chave] = lista }
            }
        } catch {
            passoIA = .falhou(error.localizedDescription)
        }

        if let d = destino { await Worktree.descartar(origem: origem, destino: d) }
    }

    /// O que muda sai do diff, sem IA. Só a pergunta que exige julgamento —
    /// o que sente a mudança e o que você precisa conhecer — vai pro Claude.
    func desenharMapa(_ pr: PR) async {
        guard desenhandoMapa == nil else { return }
        desenhandoMapa = pr.chave
        defer { desenhandoMapa = nil }

        guard let origem = Worktree.localDe(pr.repo, configurados: config.caminhos) else {
            erro = "não achei \(pr.repo) na sua máquina. Aponte a pasta em Ajustes."
            return
        }

        var destino: URL?
        do {
            let alterados = try await cliente.modulosAlterados(repo: pr.repo, pr: pr.numero)
            let w = try await Worktree.preparar(origem: origem, repo: pr.repo, pr: pr.numero)
            destino = w

            if let m = await MapaIA().desenhar(
                pr: pr, alterados: alterados, em: w, modelo: config.modeloIA
            ) {
                mapas[pr.chave] = m
            } else {
                // Sem julgamento a gente ainda mostra o que o diff dá.
                mapas[pr.chave] = Mapa(
                    proposta: pr.titulo,
                    deltas: [],
                    alterados: alterados,
                    impactados: [],
                    contexto: []
                )
                erro = "o mapa saiu só com o que o diff dá; a sessão não respondeu em JSON"
            }
        } catch {
            erro = error.localizedDescription
        }

        if let d = destino { await Worktree.descartar(origem: origem, destino: d) }
    }

    func descartarAchado(_ pr: PR, _ a: Achado) {
        achados[pr.chave]?.removeAll { $0.id == a.id }
    }

    func abrir(_ pr: PR) {
        NSWorkspace.shared.open(pr.url)
        store.marcarLido(pr.chave)
        naoLidos = store.estado.naoLidos
    }

    func limparTudo() {
        store.marcarTudoLido()
        naoLidos = store.estado.naoLidos
    }

    // MARK: - O que de fato espera por você

    var precisamDeVoce: [PR] {
        var vistos = Set<String>()
        var saida: [PR] = []
        for pr in fila.revisar + fila.meus.filter({ $0.ci == .falhou })
                 + fila.todos.filter({ naoLidos.contains($0.chave) }) {
            if vistos.insert(pr.chave).inserted { saida.append(pr) }
        }
        return saida
    }

    var contador: Int { precisamDeVoce.count }

    func prs(_ aba: Aba) -> [PR] {
        switch aba {
        case .esperando:  precisamDeVoce
        case .meus:       fila.meus
        case .revisando:  fila.revisar
        case .observando: fila.envolvido
        }
    }

    func contagem(_ aba: Aba) -> Int { prs(aba).count }

    /// Responde numa thread pela janela. Recarrega a fila pra conversa refletir.
    func responder(thread: String, texto: String) async -> String? {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        enviando = true
        defer { enviando = false }
        do {
            try await cliente.responder(threadId: thread, corpo: t)
            await atualizar()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func resolver(thread: String) async -> String? {
        enviando = true
        defer { enviando = false }
        do {
            try await cliente.resolver(threadId: thread)
            await atualizar()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var resto: [PR] {
        let urgentes = Set(precisamDeVoce.map(\.chave))
        return fila.meus.filter { !urgentes.contains($0.chave) }
    }
}
