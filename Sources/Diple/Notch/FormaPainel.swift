import SwiftUI

/// O painel com cantos de cima CÔNCAVOS.
///
/// No topo a forma ocupa a largura inteira e vai estreitando ao descer, com
/// um filete invertido — o preto derrete na barra em vez de encostar de
/// quina. É o contrário do raio comum, que corta material e deixa aparecer
/// uma fresta de wallpaper no canto.
///
/// O truque está no ponto de controle: puxado pro canto INTERNO a curva fica
/// côncava; puxado pro externo, convexa.
struct FormaPainel: Shape {
    /// Filete côncavo do topo. Zero deixa a lateral reta, pra casar com o
    /// recorte quando fechado.
    var flare: CGFloat
    /// Raio dos cantos de baixo, esses normais.
    var base: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(flare, base) }
        set { flare = newValue.first; base = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        let f = max(0, min(flare, w / 2, h / 2))
        let b = max(0, min(base, (w - f * 2) / 2, h - f))

        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))

        // canto de cima à direita: côncavo, controle no canto interno
        p.addQuadCurve(to: CGPoint(x: w - f, y: f),
                       control: CGPoint(x: w - f, y: 0))

        p.addLine(to: CGPoint(x: w - f, y: h - b))
        p.addQuadCurve(to: CGPoint(x: w - f - b, y: h),
                       control: CGPoint(x: w - f, y: h))

        p.addLine(to: CGPoint(x: f + b, y: h))
        p.addQuadCurve(to: CGPoint(x: f, y: h - b),
                       control: CGPoint(x: f, y: h))

        p.addLine(to: CGPoint(x: f, y: f))
        // canto de cima à esquerda: côncavo também
        p.addQuadCurve(to: CGPoint(x: 0, y: 0),
                       control: CGPoint(x: f, y: 0))

        p.closeSubpath()
        return p
    }
}
