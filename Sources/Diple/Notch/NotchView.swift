import SwiftUI

enum EstadoNotch: Equatable {
    /// Exatamente o recorte: o app existe mas não aparece.
    case oculto
    /// O recorte com asas, mostrando o olho e o número.
    case atividade
    case aberto
    case alerta(Evento)

    static func == (a: EstadoNotch, b: EstadoNotch) -> Bool {
        switch (a, b) {
        case (.oculto, .oculto), (.atividade, .atividade), (.aberto, .aberto): true
        case let (.alerta(x), .alerta(y)): x.id == y.id
        default: false
        }
    }
}

struct NotchView: View {
    @ObservedObject var modelo: Modelo
    let estado: EstadoNotch
    let tamanho: CGSize
    let larguraNotch: CGFloat
    let alturaNotch: CGFloat
    let olhar: CGPoint
    let piscando: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(
                    bottomLeadingRadius: raio,
                    bottomTrailingRadius: raio,
                    style: .continuous
                )
                .fill(.black)

                conteudo
            }
            .frame(width: tamanho.width, height: tamanho.height)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // A forma cresce e encolhe com mola; a janela fica parada.
        .animation(.spring(response: 0.38, dampingFraction: 0.74), value: tamanho)
        .animation(.bouncy(duration: 0.4), value: modelo.contador)
    }

    private var raio: CGFloat {
        switch estado {
        case .oculto, .atividade: 10
        case .aberto, .alerta: 22
        }
    }

    @ViewBuilder private var conteudo: some View {
        switch estado {
        case .oculto:
            Color.clear
        case .atividade:
            asas
        case .aberto:
            aberto
        case .alerta(let e):
            alerta(e)
        }
    }

    /// Olho numa asa, número na outra, e o vão do recorte livre no meio.
    private var asas: some View {
        HStack(spacing: 0) {
            OlhoView(olhar: olhar, piscando: piscando, largura: 15)
                .frame(maxWidth: .infinity)
            Spacer(minLength: larguraNotch)
                .frame(width: larguraNotch)
            Text("\(modelo.contador)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(modelo.contador)))
                .frame(maxWidth: .infinity)
        }
        .frame(height: alturaNotch)
    }

    private var aberto: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                OlhoView(olhar: olhar, piscando: piscando, largura: 16)
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
            .padding(.top, alturaNotch + 6)
            .padding(.bottom, 10)

            ForEach(Array(modelo.precisamDeVoce.prefix(3))) { pr in
                Button { modelo.abrir(pr) } label: {
                    HStack(spacing: 11) {
                        Circle()
                            .fill(pr.ci == .falhou ? Color.red : .orange)
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pr.titulo)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(meta(pr))
                                .font(.system(size: 11.5))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(pr.atualizadoEm.formatted(.relative(presentation: .numeric)))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.38))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)

            HStack {
                Text("\(modelo.fila.meus.count) seus · \(modelo.fila.revisar.count) revisando")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.42))
                Spacer()
                Text("⌘0 janela")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.38))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
    }

    private func meta(_ pr: PR) -> String {
        let base = "\(pr.repo.split(separator: "/").last.map(String.init) ?? pr.repo) #\(pr.numero)"
        if let c = pr.ultimoComentario {
            return "\(base) · \(c.autor)\(c.onde.map { " em \($0)" } ?? "")"
        }
        return base
    }

    private func alerta(_ e: Evento) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Circle().fill(.orange).frame(width: 7, height: 7)
                Text(e.titulo)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                if let som = e.tipo.som {
                    Text(som)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
            Text(e.corpo)
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Abrir o PR") { NSWorkspace.shared.open(e.url) }
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Color.white.opacity(0.1), in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.top, alturaNotch + 8)
        .padding(.bottom, 14)
    }
}
