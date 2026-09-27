import SwiftUI
import AppKit

@MainActor
final class Notch: ObservableObject {
    @Published private(set) var estado: EstadoNotch = .repouso

    private let painel = NotchPanel()
    private weak var modelo: Modelo?
    private var recolher: Task<Void, Never>?
    private var hover = false

    func montar(modelo: Modelo) {
        self.modelo = modelo
        painel.contentView = NSHostingView(rootView: Hospedeiro(notch: self, modelo: modelo))
        aplicar(animado: false)
        painel.orderFrontRegardless()

        // Plugar ou desplugar monitor muda tudo: qual tela, se tem notch, onde é o centro.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.aplicar(animado: false) }
        }
    }

    // MARK: - Estados

    func abrir() {
        hover = true
        recolher?.cancel()
        guard estado != .aberto else { return }
        estado = .aberto
        aplicar(animado: true)
    }

    func fechar() {
        hover = false
        // Um respiro antes de recolher: sair do painel por um pixel não deve fechá-lo.
        recolher?.cancel()
        recolher = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, let self, !self.hover else { return }
            self.estado = .repouso
            self.aplicar(animado: true)
        }
    }

    /// Um evento chegando abre a notch sozinho e recolhe depois.
    func alertar(_ e: Evento) {
        guard e.tipo.interrompe else { return }
        recolher?.cancel()
        estado = .alerta(e)
        aplicar(animado: true)
        recolher = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self, !self.hover else { return }
            self.estado = .repouso
            self.aplicar(animado: true)
        }
    }

    /// Chamado quando o contador muda, pra fita crescer ou sumir em repouso.
    func revisarRepouso() {
        guard estado == .repouso else { return }
        aplicar(animado: true)
    }

    // MARK: - Geometria

    private func aplicar(animado: Bool) {
        let g = Geometria.atual()

        let alvo: NSRect = switch estado {
        case .repouso: g.repouso(pendencias: modelo?.contador ?? 0)
        case .aberto:  g.aberto()
        case .alerta:  g.alerta()
        }

        guard animado else { painel.setFrame(alvo, display: true); return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.26
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            painel.animator().setFrame(alvo, display: true)
        }
    }

    private struct Hospedeiro: View {
        @ObservedObject var notch: Notch
        @ObservedObject var modelo: Modelo

        var body: some View {
            NotchView(
                modelo: modelo,
                estado: notch.estado,
                aoEntrar: { notch.abrir() },
                aoSair: { notch.fechar() }
            )
        }
    }
}
