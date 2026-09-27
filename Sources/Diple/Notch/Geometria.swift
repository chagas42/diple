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
        return temNotch ? pendurado(largura: larguraNotch + 56, altura: 26)
                        : solto(largura: 248, altura: 30)
    }

    func aberto() -> NSRect {
        temNotch ? pendurado(largura: 620, altura: 296)
                 : solto(largura: 620, altura: 300)
    }

    func alerta() -> NSRect {
        temNotch ? pendurado(largura: 580, altura: 186)
                 : solto(largura: 580, altura: 190)
    }

    /// Pendurado na borda de baixo do recorte: o topo do painel encosta
    /// exatamente onde o bezel termina.
    private func pendurado(largura: CGFloat, altura: CGFloat) -> NSRect {
        NSRect(x: tela.frame.midX - largura / 2,
               y: tela.frame.maxY - alturaTopo - altura,
               width: largura, height: altura)
    }

    /// Cobre exatamente o recorte (ou o centro da barra, sem recorte).
    /// Nada é desenhado aqui — essa área não é clicável de todo jeito.
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
