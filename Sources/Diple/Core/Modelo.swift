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

    /// Intervalo de 60s: a query custa 1 ponto de 5000/hora.
    private let intervalo: TimeInterval = 60

    private var iniciado = false

    func iniciar() {
        guard !iniciado else { return }
        iniciado = true
        notificador.instalar()
        notificador.aoMudar = { [weak self] in await self?.atualizar() }
        naoLidos = store.estado.naoLidos

        Task {
            permissao = await notificador.autorizado()
            if !permissao { permissao = await notificador.pedirPermissao() }
            await atualizar()
        }

        timer = Timer.scheduledTimer(withTimeInterval: intervalo, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.atualizar() }
        }

        // Dormir e acordar deixa a fila velha; sincroniza ao voltar.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
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
