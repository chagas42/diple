import SwiftUI
import AppKit

@MainActor
final class Notch: ObservableObject {
    @Published private(set) var estado: EstadoNotch = .oculto
    @Published private(set) var tamanho: CGSize = .zero
    @Published private(set) var larguraNotch: CGFloat = 185
    @Published private(set) var alturaNotch: CGFloat = 32
    @Published private(set) var olhar: CGPoint = .zero
    @Published private(set) var piscando = false

    private let painel = NotchPanel()
    private weak var modelo: Modelo?
    private var recolher: Task<Void, Never>?
    private var olhos: Timer?
    private var piscada: Task<Void, Never>?

    func montar(modelo: Modelo) {
        self.modelo = modelo
        painel.contentView = NSHostingView(rootView: Hospedeiro(notch: self, modelo: modelo))
        medir()
        painel.setFrame(Geometria.atual().janela(), display: true)
        painel.orderFrontRegardless()
        acompanhar()
        piscarDeVezEmQuando()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.medir()
                self.painel.setFrame(Geometria.atual().janela(), display: true)
            }
        }
    }

    // MARK: - Estados

    private func medir() {
        let g = Geometria.atual()
        larguraNotch = g.larguraNotch
        alturaNotch = g.alturaTopo
        aplicar()
    }

    /// Só troca o tamanho da forma. A janela nunca se mexe — é isso que
    /// mantém a animação líquida e elimina o laço de hover.
    private func aplicar() {
        let g = Geometria.atual()
        let novo: CGSize = switch estado {
        case .oculto:    g.fechado
        case .atividade: g.atividade
        case .aberto:    g.aberto
        case .alerta:    g.alerta
        }
        tamanho = novo

        // Fechado, os cliques atravessam pra barra de menu. Aberto, os botões
        // precisam receber.
        switch estado {
        case .oculto, .atividade: painel.ignoresMouseEvents = true
        case .aberto, .alerta:    painel.ignoresMouseEvents = false
        }
    }

    private func repouso() -> EstadoNotch {
        (modelo?.contador ?? 0) > 0 ? .atividade : .oculto
    }

    func abrir() {
        recolher?.cancel()
        guard estado != .aberto else { return }
        estado = .aberto
        aplicar()
    }

    func fechar(depois: Duration = .milliseconds(240)) {
        recolher?.cancel()
        recolher = Task { [weak self] in
            try? await Task.sleep(for: depois)
            guard !Task.isCancelled, let self else { return }
            self.estado = self.repouso()
            self.aplicar()
        }
    }

    func alertar(_ e: Evento) {
        guard e.tipo.interrompe else { return }
        recolher?.cancel()
        estado = .alerta(e)
        aplicar()
        fechar(depois: .seconds(6))
    }

    /// Chamado quando o contador muda: some ou aparece sem passar pelo hover.
    func revisarRepouso() {
        guard estado == .oculto || estado == .atividade else { return }
        estado = repouso()
        aplicar()
    }

    // MARK: - Ponteiro e olho

    private func acompanhar() {
        olhos = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.verificarPonteiro()
                self.mirar()
            }
        }
    }

    /// A verdade do hover é onde o ponteiro está, testada contra a forma —
    /// não contra a janela, que é bem maior, nem contra eventos de layout.
    private func verificarPonteiro() {
        let g = Geometria.atual()
        let forma = g.retangulo(tamanho)
        // A faixa do recorte sempre conta, pra você poder mirar a notch mesmo
        // quando nada está visível.
        let sensivel = forma.union(g.retangulo(g.fechado))
        let m = NSEvent.mouseLocation

        let aberto = estado == .aberto
        let dentro = aberto ? sensivel.insetBy(dx: -16, dy: -16).contains(m)
                            : sensivel.contains(m)

        if dentro {
            abrir()
        } else if aberto {
            fechar()
        }
    }

    private func mirar() {
        guard estado == .oculto || estado == .atividade else { return }
        let g = Geometria.atual()
        let f = g.retangulo(tamanho)
        let m = NSEvent.mouseLocation
        let alcance: CGFloat = 300
        let dx = max(-1, min(1, (m.x - f.midX) / alcance))
        let dy = max(-1, min(1, (f.midY - m.y) / alcance))
        let novo = CGPoint(x: dx, y: dy)
        if abs(novo.x - olhar.x) > 0.01 || abs(novo.y - olhar.y) > 0.01 { olhar = novo }
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

    private struct Hospedeiro: View {
        @ObservedObject var notch: Notch
        @ObservedObject var modelo: Modelo

        var body: some View {
            NotchView(
                modelo: modelo,
                estado: notch.estado,
                tamanho: notch.tamanho,
                larguraNotch: notch.larguraNotch,
                alturaNotch: notch.alturaNotch,
                olhar: notch.olhar,
                piscando: notch.piscando
            )
        }
    }
}
