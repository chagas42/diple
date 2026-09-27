import AppKit

/// Onde o painel encosta, e de que forma.
/// Com notch o painel cola no topo e só arredonda embaixo, pra o preto dele
/// virar continuação do bezel. Sem notch vira pílula solta, com borda e sombra
/// — deliberadamente diferente, porque ali não há bezel pra fingir.
@MainActor
struct Geometria {
    let tela: NSScreen

    var temNotch: Bool { tela.safeAreaInsets.top > 0 }

    /// Altura do recorte (ou da barra de menu, quando não há recorte).
    var alturaTopo: CGFloat {
        temNotch ? tela.safeAreaInsets.top : (NSApp.mainMenu?.menuBarHeight ?? 24)
    }

    /// Largura física do recorte, medida pelo que sobra dos dois lados.
    var larguraNotch: CGFloat {
        guard temNotch,
              let esq = tela.auxiliaryTopLeftArea,
              let dir = tela.auxiliaryTopRightArea else { return 180 }
        return max(0, tela.frame.width - esq.width - dir.width)
    }

    // MARK: - Molduras, em coordenadas de tela (origem embaixo à esquerda)

    /// Zerado, o painel some mas continua existindo: um alvo invisível do
    /// tamanho do recorte, só pra o hover ter onde acontecer.
    func repouso(pendencias: Int) -> NSRect {
        guard pendencias > 0 else { return alvoInvisivel() }
        // Largura exata do recorte: o flare fica zero e não sobra degrau
        // nenhum nas laterais. Parece só que a notch ficou um pouco mais alta.
        // Estreito de propósito: mais largo que isso vira aba, e o contador
        // já existe na barra de menu. Aqui o olho é o que importa.
        return temNotch ? pendurado(largura: 58, visivel: 15)
                        : solto(largura: 74, altura: 20)
    }

    func aberto() -> NSRect {
        temNotch ? pendurado(largura: 620, visivel: 296)
                 : solto(largura: 620, altura: 300)
    }

    func alerta() -> NSRect {
        temNotch ? pendurado(largura: 580, visivel: 186)
                 : solto(largura: 580, altura: 190)
    }

    /// Começa no topo da tela: os primeiros `alturaTopo` pontos ficam atrás do
    /// recorte, onde não existe display, e o corpo aparece abaixo dele. É isso
    /// que faz a forma sair de dentro da notch em vez de pendurar nela.
    /// `visivel` é a altura do que de fato se vê.
    private func pendurado(largura: CGFloat, visivel: CGFloat) -> NSRect {
        NSRect(x: tela.frame.midX - largura / 2,
               y: tela.frame.maxY - alturaTopo - visivel,
               width: largura, height: alturaTopo + visivel)
    }

    /// Cobre exatamente o recorte (ou o centro da barra, sem recorte).
    /// Nada é desenhado aqui — essa área não é clicável de todo jeito.
    /// A faixa do recorte em si. O ponteiro passando aqui já conta como hover,
    /// senão você teria que mirar os 17pt do repouso.
    func zonaNotch() -> NSRect {
        let l = temNotch ? larguraNotch : 180
        return NSRect(x: tela.frame.midX - l / 2,
                      y: tela.frame.maxY - alturaTopo,
                      width: l, height: alturaTopo)
    }

    private func alvoInvisivel() -> NSRect {
        let l = temNotch ? larguraNotch : 180
        return NSRect(x: tela.frame.midX - l / 2,
                      y: tela.frame.maxY - alturaTopo,
                      width: l, height: alturaTopo)
    }

    /// Solto abaixo da barra de menu.
    private func solto(largura: CGFloat, altura: CGFloat) -> NSRect {
        NSRect(x: tela.frame.midX - largura / 2,
               y: tela.frame.maxY - alturaTopo - 8 - altura,
               width: largura, height: altura)
    }

    /// A tela que tem notch, se houver; senão a que tem a barra de menu.
    static func atual() -> Geometria {
        let comNotch = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        return Geometria(tela: comNotch ?? NSScreen.main ?? NSScreen.screens[0])
    }
}
