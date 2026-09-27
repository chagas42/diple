import SwiftUI

enum EstadoNotch: Equatable {
    case repouso
    case aberto
    case alerta(Evento)

    static func == (a: EstadoNotch, b: EstadoNotch) -> Bool {
        switch (a, b) {
        case (.repouso, .repouso), (.aberto, .aberto): true
        case let (.alerta(x), .alerta(y)): x.id == y.id
        default: false
        }
    }
}

/// O painel é preto puro de propósito: é o preto que casa com o bezel e faz
/// parecer que a própria notch cresceu. Por isso os cantos de cima ficam retos.
struct NotchView: View {
    /// Color.black passa por gerenciamento de cor e sai diferente do bezel.
    /// Preto de dispositivo vai cru pro display.
    static let pretoDeDispositivo = Color(
        nsColor: NSColor(colorSpace: .deviceRGB, components: [0, 0, 0, 1], count: 4)
    )

    @ObservedObject var modelo: Modelo
    let estado: EstadoNotch
    /// Verdadeiro quando pendura no recorte físico.
    let pendurado: Bool
    let larguraNotch: CGFloat
    let alturaNotch: CGFloat
    let olhar: CGPoint
    let piscando: Bool

    var body: some View {
        conteudo
            // O topo do painel fica atrás do bezel; o conteúdo começa abaixo.
            .padding(.top, pendurado ? alturaNotch : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Self.pretoDeDispositivo)
            .clipShape(forma)
            .overlay(borda)
            // Pendurado, a sombra fica só embaixo: sombra na borda de cima
            // desenha um degradê que o olho lê como um segundo preto.
            .shadow(color: .black.opacity(pendurado ? 0.35 : 0.5),
                    radius: pendurado ? 10 : 14,
                    y: pendurado ? 8 : 6)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.42, dampingFraction: 0.72), value: raio)
            .animation(.bouncy(duration: 0.45), value: modelo.contador)
    }

    private var forma: AnyShape {
        pendurado
            ? AnyShape(FormaNotch(larguraNotch: larguraNotch,
                                  alturaNotch: pendurado ? alturaNotch : 0,
                                  base: raio))
            : AnyShape(RoundedRectangle(cornerRadius: raio, style: .continuous))
    }

    private var raio: CGFloat {
        switch estado {
        case .repouso: 7
        case .aberto, .alerta: 20
        }
    }

    /// Só a pílula solta ganha contorno. Pendurado, um contorno claro no topo
    /// denunciaria justamente a emenda que a forma esconde.
    @ViewBuilder private var borda: some View {
        if !pendurado {
            forma.stroke(Color.white.opacity(0.13), lineWidth: 1)
        }
    }

    @ViewBuilder private var conteudo: some View {
        switch estado {
        case .repouso: repouso
        case .aberto:  aberto
        case .alerta(let e): alerta(e)
        }
    }

    // MARK: - Repouso

    @ViewBuilder private var repouso: some View {
        if modelo.contador > 0 {
            HStack(spacing: 4) {
                OlhoView(olhar: olhar, piscando: piscando, largura: 11)
                Text("\(modelo.contador)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(modelo.contador)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
        }
    }

    // MARK: - Aberto

    private var aberto: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Text("⟩").font(.system(size: 13, design: .monospaced)).foregroundStyle(.orange)
                Text("\(modelo.contador) esperando você")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                if modelo.carregando {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Button { Task { await modelo.atualizar() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ForEach(Array(modelo.precisamDeVoce.prefix(3))) { pr in
                Button { modelo.abrir(pr) } label: {
                    HStack(spacing: 11) {
                        Circle()
                            .fill(pr.ci == .falhou ? Color.red : .orange)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pr.titulo)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(linhaMeta(pr))
                                .font(.system(size: 11.5))
                                .foregroundStyle(.white.opacity(0.52))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(pr.atualizadoEm.formatted(.relative(presentation: .numeric)))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.001))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Text("\(modelo.fila.meus.count) seus · \(modelo.fila.revisar.count) revisando")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                Text("⌘0 janela")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
    }

    private func linhaMeta(_ pr: PR) -> String {
        let base = "\(pr.repo.split(separator: "/").last.map(String.init) ?? pr.repo) #\(pr.numero)"
        if let c = pr.ultimoComentario {
            return "\(base) · \(c.autor)\(c.onde.map { " em \($0)" } ?? "")"
        }
        return base
    }

    // MARK: - Alerta

    private func alerta(_ e: Evento) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Circle().fill(.orange).frame(width: 8, height: 8)
                Text(e.titulo)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                if let som = e.tipo.som {
                    Text(som)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            Text(e.corpo)
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button("Abrir o PR") { NSWorkspace.shared.open(e.url) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.white.opacity(0.09), in: Capsule())
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }
}
