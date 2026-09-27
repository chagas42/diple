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

    private var foraDesde: Date?

    private var ancora: CGPoint?
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

    private func medir() {
        let g = Geometria.atual()
        larguraNotch = g.larguraNotch
        alturaNotch = g.alturaTopo
        aplicar()
    }

    private func aplicar() {
        let g = Geometria.atual()
        let novo: CGSize = switch estado {
        case .oculto:    g.fechado
        case .atividade: g.atividade
        case .aberto:    g.aberto
        case .alerta:    g.alerta
        }
        tamanho = novo

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

    func fecharAgora() {
        recolher?.cancel()
        recolher = nil
        foraDesde = nil
        ancora = nil
        estado = repouso()
        aplicar()
    }

    func alertar(_ e: Evento) {
        guard e.tipo.interrompe else { return }
        recolher?.cancel()
        ancora = NSEvent.mouseLocation
        estado = .alerta(e)
        aplicar()

        recolher = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self, self.estado != .aberto else { return }
            self.fecharAgora()
        }
    }

    func revisarRepouso() {
        guard estado == .oculto || estado == .atividade else { return }
        estado = repouso()
        aplicar()
    }

    private func acompanhar() {
        olhos = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.verificarPonteiro()
                self.mirar()
            }
        }
    }

    private func verificarPonteiro() {
        let g = Geometria.atual()
        let forma = g.retangulo(tamanho)

        let sensivel = forma.union(g.retangulo(g.fechado))
        let m = NSEvent.mouseLocation

        let aberto = estado == .aberto
        let dentro = aberto ? sensivel.insetBy(dx: -16, dy: -16).contains(m)
                            : sensivel.contains(m)

        if dentro {
            foraDesde = nil
            if case .alerta = estado, let a = ancora {
                let andou = hypot(m.x - a.x, m.y - a.y) > 8
                guard andou else { return }
            }
            ancora = nil
            abrir()
            return
        }

        guard aberto else { foraDesde = nil; return }

        let agora = Date()
        if foraDesde == nil { foraDesde = agora }
        if agora.timeIntervalSince(foraDesde!) >= 0.25 {
            fecharAgora()
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
                piscando: notch.piscando,
                aoFechar: { notch.fecharAgora() }
            )
        }
    }
}
