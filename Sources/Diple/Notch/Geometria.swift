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

    func repouso(pendencias: Int) -> NSRect {
        if temNotch {
            let extra: CGFloat = pendencias > 0 ? 18 : 0
            let l = larguraNotch + (pendencias > 0 ? 48 : 0)
            let a = alturaTopo + extra
            return colado(largura: l, altura: a)
        } else {
            guard pendencias > 0 else { return solto(largura: 1, altura: 1) }
            return solto(largura: 248, altura: 30)
        }
    }

    func aberto() -> NSRect {
        temNotch ? colado(largura: 620, altura: 300)
                 : solto(largura: 620, altura: 300)
    }

    func alerta() -> NSRect {
        temNotch ? colado(largura: 580, altura: 190)
                 : solto(largura: 580, altura: 190)
    }

    /// Encostado no topo: só os cantos de baixo arredondam.
    private func colado(largura: CGFloat, altura: CGFloat) -> NSRect {
        NSRect(x: tela.frame.midX - largura / 2,
               y: tela.frame.maxY - altura,
               width: largura, height: altura)
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
