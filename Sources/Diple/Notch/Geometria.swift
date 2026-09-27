import AppKit

/// A janela é fixa, do tamanho aberto, e nunca redimensiona. O que muda de
/// tamanho é a forma preta desenhada dentro dela. É assim que os apps de notch
/// fazem: sem resize de janela não existe laço de hover nem animação travada.
@MainActor
struct Geometria {
    let tela: NSScreen

    var temNotch: Bool { tela.auxiliaryTopLeftArea != nil }

    /// Altura do recorte, ou da barra de menu quando não há recorte.
    var alturaTopo: CGFloat {
        temNotch ? tela.safeAreaInsets.top : 32
    }

    /// Largura física do recorte, medida pelo que sobra dos dois lados.
    var larguraNotch: CGFloat {
        guard let esq = tela.auxiliaryTopLeftArea,
              let dir = tela.auxiliaryTopRightArea else { return 185 }
        return max(0, tela.frame.width - esq.width - dir.width)
    }

    // MARK: - Tamanhos da forma

    /// Exatamente o recorte: indistinguível da notch de verdade.
    var fechado: CGSize { CGSize(width: larguraNotch, height: alturaTopo) }

    /// O recorte com duas asas, pra caber o olho de um lado e o número do
    /// outro. Mesma altura — nada desce abaixo da barra de menu.
    var atividade: CGSize {
        CGSize(width: larguraNotch + asa * 2, height: alturaTopo)
    }

    var aberto: CGSize { CGSize(width: 680, height: 330) }

    var alerta: CGSize { CGSize(width: 560, height: 186) }

    var asa: CGFloat { 42 }

    // MARK: - A janela

    /// Sempre do tamanho do maior estado, colada no topo e centrada.
    func janela() -> NSRect {
        let l = max(aberto.width, alerta.width)
        let a = max(aberto.height, alerta.height)
        return NSRect(x: tela.frame.midX - l / 2,
                      y: tela.frame.maxY - a,
                      width: l, height: a)
    }

    /// Onde a forma de fato está, em coordenadas de tela. É contra isto que o
    /// ponteiro é testado — não contra a janela, que é muito maior.
    func retangulo(_ tamanho: CGSize) -> NSRect {
        NSRect(x: tela.frame.midX - tamanho.width / 2,
               y: tela.frame.maxY - tamanho.height,
               width: tamanho.width, height: tamanho.height)
    }

    static func atual() -> Geometria {
        let comNotch = NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil }
        return Geometria(tela: comNotch ?? NSScreen.main ?? NSScreen.screens[0])
    }
}
