import SwiftUI
import AppKit

@MainActor
final class Notch: ObservableObject {
    @Published private(set) var estado: EstadoNotch = .repouso
    @Published private(set) var pendurado = true
    @Published private(set) var larguraNotch: CGFloat = 209
    @Published private(set) var olhar: CGPoint = .zero
    @Published private(set) var piscando = false

    private let painel = NotchPanel()
    private weak var modelo: Modelo?
    private var recolher: Task<Void, Never>?
    private var hover = false
    private var olhos: Timer?
    private var piscada: Task<Void, Never>?

    func montar(modelo: Modelo) {
        self.modelo = modelo
        painel.contentView = NSHostingView(rootView: Hospedeiro(notch: self, modelo: modelo))
        aplicar(animado: false)
        painel.orderFrontRegardless()
        seguirPonteiro()
        piscarDeVezEmQuando()

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

    // MARK: - O olho

    /// Ler NSEvent.mouseLocation num timer evita monitor global de eventos,
    /// que em alguns sistemas pede permissão. 30 Hz é imperceptível e basta.
    private func seguirPonteiro() {
        olhos = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.verificarPonteiro()
                guard self.estado == .repouso else { return }
                let centro = CGPoint(x: self.painel.frame.midX, y: self.painel.frame.midY)
                let m = NSEvent.mouseLocation
                let alcance: CGFloat = 320
                let dx = max(-1, min(1, (m.x - centro.x) / alcance))
                // Coordenada de tela cresce pra cima; a da view, pra baixo.
                let dy = max(-1, min(1, (centro.y - m.y) / alcance))
                let novo = CGPoint(x: dx, y: dy)
                if abs(novo.x - self.olhar.x) > 0.01 || abs(novo.y - self.olhar.y) > 0.01 {
                    self.olhar = novo
                }
            }
        }
    }

    /// A fonte da verdade do hover é onde o ponteiro está, não um evento de
    /// layout. onHover do SwiftUI dispara durante a própria animação de
    /// redimensionar: abre, o layout muda, dispara saída, fecha, entra de novo.
    /// Isso era o piscar.
    private func verificarPonteiro() {
        let m = NSEvent.mouseLocation
        let sensivel = painel.frame.union(Geometria.atual().zonaNotch())
        // Folga assimétrica: entra justo, sai com margem. Sem histerese o
        // ponteiro parado na borda faz o painel tremer.
        let dentro = estado == .repouso
            ? sensivel.contains(m)
            : sensivel.insetBy(dx: -14, dy: -14).contains(m)

        if dentro { abrir() } else if hover { fechar() }
    }

    private func piscarDeVezEmQuando() {
        piscada = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 4...9)))
                guard let self, !Task.isCancelled else { return }
                self.piscando = true
                try? await Task.sleep(for: .milliseconds(110))
                self.piscando = false
            }
        }
    }

    // MARK: - Geometria

    private func aplicar(animado: Bool) {
        let g = Geometria.atual()
        pendurado = g.temNotch
        larguraNotch = g.larguraNotch

        let alvo: NSRect = switch estado {
        case .repouso: g.repouso(pendencias: modelo?.contador ?? 0)
        case .aberto:  g.aberto()
        case .alerta:  g.alerta()
        }

        guard animado else { painel.setFrame(alvo, display: true); return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.42
            // O segundo ponto de controle passa de 1: a curva ultrapassa o
            // destino e volta. É o que dá o peso de líquido em vez de slide.
            ctx.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.30, 1.42, 0.50, 1.0
            )
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
                pendurado: notch.pendurado,
                larguraNotch: notch.larguraNotch,
                olhar: notch.olhar,
                piscando: notch.piscando
            )
        }
    }
}
