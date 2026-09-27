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
    @Environment(\.openWindow) private var abrirJanela
    @ObservedObject var modelo: Modelo
    let estado: EstadoNotch
    let tamanho: CGSize
    let larguraNotch: CGFloat
    let alturaNotch: CGFloat
    let olhar: CGPoint
    let piscando: Bool
    let aoFechar: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                forma.fill(.black)
                conteudo
            }
            .frame(width: tamanho.width, height: tamanho.height)
            // Recorta o conteúdo na forma que está animando. Sem isto o texto
            // é disposto no tamanho final e vaza por cima do wallpaper antes
            // de a forma alcançá-lo.
            .clipShape(forma)
            .contextMenu {
                Button("Ajustes…") {
                    NSApp.activate(ignoringOtherApps: true)
                    abrirJanela(id: Janela.ajustes)
                }
                Button("Janela principal") {
                    NSApp.activate(ignoringOtherApps: true)
                    abrirJanela(id: Janela.principal)
                }
                Divider()
                Button("Sair do Diple") { NSApplication.shared.terminate(nil) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // A forma cresce e encolhe com mola; a janela fica parada.
        .animation(.spring(response: 0.38, dampingFraction: 0.74), value: tamanho)
        .animation(.bouncy(duration: 0.4), value: modelo.contador)
    }

    private var forma: FormaPainel {
        FormaPainel(flare: flare, base: raio)
    }

    private var raio: CGFloat {
        switch estado {
        case .oculto, .atividade: 10
        case .aberto, .alerta: 22
        }
    }

    /// Fechado a lateral é reta, pra casar com o recorte. Aberto o topo se
    /// alarga e desce com filete côncavo.
    private var flare: CGFloat {
        switch estado {
        case .oculto, .atividade: 0
        case .aberto, .alerta: 16
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

    // MARK: - Aberto
    // A faixa do topo fica na altura da barra de menu, com o vão do recorte
    // livre no meio. O corpo são cartões, não linhas de lista.

    private var aberto: some View {
        VStack(spacing: 0) {
            faixaDoTopo
            corpo
        }
    }

    private var faixaDoTopo: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                OlhoView(olhar: olhar, piscando: piscando, largura: 15)
                    .padding(.trailing, 2)
                ForEach(Modelo.AbaNotch.allCases) { aba in
                    Button { modelo.abaNotch = aba } label: {
                        Image(systemName: aba.icone)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(modelo.abaNotch == aba ? 0.95 : 0.42))
                            .frame(width: 30, height: 26)
                            .background(
                                Capsule().fill(
                                    modelo.abaNotch == aba
                                        ? Color.white.opacity(0.15) : .white.opacity(0.001)
                                )
                            )
                            // A área de toque é o retângulo inteiro, não o glifo.
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(aba.titulo)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 14 + flare)
            .frame(maxWidth: .infinity)

            Spacer(minLength: larguraNotch).frame(width: larguraNotch)

            HStack(spacing: 7) {
                Spacer(minLength: 0)
                botaoIcone("macwindow") {
                    NSApp.activate(ignoringOtherApps: true)
                    abrirJanela(id: Janela.principal)
                    aoFechar()
                }
                if modelo.carregando || modelo.carregandoAba {
                    ProgressView().controlSize(.small).tint(.white).frame(width: 22)
                } else {
                    botaoIcone("arrow.clockwise") { Task { await modelo.atualizar() } }
                }
                botaoIcone("gearshape") {
                    NSApp.activate(ignoringOtherApps: true)
                    abrirJanela(id: Janela.ajustes)
                    aoFechar()
                }
                botaoIcone("xmark") { aoFechar() }
            }
            .padding(.trailing, 14 + flare)
            .frame(maxWidth: .infinity)
        }
        .frame(height: alturaNotch)
    }

    private func botaoIcone(_ nome: String, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: nome)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.1), in: Circle())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var corpo: some View {
        Group {
            switch modelo.abaNotch {
            case .fila:
                HStack(spacing: 12) { cartaoResumo; cartaoFila }
            case .time:
                PainelTime(modelo: modelo)
            case .rank:
                PainelRank(modelo: modelo)
            case .ritmo:
                PainelRitmo(modelo: modelo)
            }
        }
        .padding(.horizontal, 16 + flare)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: modelo.abaNotch) { await modelo.carregarAba(modelo.abaNotch) }
    }

    private var cartaoResumo: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(modelo.contador)")
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(modelo.contador)))
            Text(modelo.contador == 1 ? "espera por você" : "esperam por você")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 2)

            Spacer(minLength: 10)

            VStack(alignment: .leading, spacing: 5) {
                miudo("seus PRs", modelo.fila.meus.count)
                miudo("revisando", modelo.fila.revisar.count)
                miudo("acompanhando", modelo.fila.envolvido.count)
            }
        }
        .padding(14)
        .frame(width: 176, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func miudo(_ rotulo: String, _ n: Int) -> some View {
        HStack(spacing: 6) {
            Text("\(n)")
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
            Text(rotulo)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.42))
        }
    }

    private var cartaoFila: some View {
        VStack(alignment: .leading, spacing: 0) {
            if modelo.precisamDeVoce.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Nada esperando por você")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(Array(modelo.precisamDeVoce.prefix(3).enumerated()), id: \.element.id) { i, pr in
                    if i > 0 {
                        Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
                    }
                    Button { modelo.abrir(pr) } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(pr.ci == .falhou ? Color.red : .orange)
                                .frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(pr.titulo)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(meta(pr))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.45))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text(pr.atualizadoEm.formatted(.relative(presentation: .numeric)))
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        )
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
        .padding(.top, alturaNotch + 10)
        .padding(.bottom, 16)
    }
}
