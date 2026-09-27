import SwiftUI

/// A forma que faz o painel parecer continuação da notch.
///
/// O painel pendura a partir da borda de baixo do recorte, nasce com a largura
/// exata dele e se abre pros lados com filetes côncavos. Não tenta igualar o
/// preto do bezel — num LCD isso é impossível, o backlight nunca chega a zero.
/// Em vez disso esconde a emenda na geometria: sobra só uma linha horizontal da
/// largura do recorte, e os filetes puxam o olho pra fora dela.
struct FormaNotch: Shape {
    /// Largura do recorte físico, em pontos.
    var larguraNotch: CGFloat
    /// Raio do filete côncavo onde o painel se abre.
    var flare: CGFloat = 11
    /// Raio dos cantos de baixo.
    var base: CGFloat = 20

    func path(in r: CGRect) -> Path {
        let l = min(larguraNotch, r.width)
        let meio = r.midX
        let e = meio - l / 2          // borda esquerda do recorte
        let d = meio + l / 2          // borda direita
        let f = min(flare, max(0, (r.width - l) / 2))
        let b = min(base, r.height / 2)

        var p = Path()
        p.move(to: CGPoint(x: e, y: 0))

        // abre pra esquerda com um filete côncavo
        p.addQuadCurve(to: CGPoint(x: e - f, y: f),
                       control: CGPoint(x: e - f, y: 0))
        p.addLine(to: CGPoint(x: r.minX + b, y: f))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: f + b),
                       control: CGPoint(x: r.minX, y: f))

        // desce, contorna a base
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - b))
        p.addQuadCurve(to: CGPoint(x: r.minX + b, y: r.maxY),
                       control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - b, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY - b),
                       control: CGPoint(x: r.maxX, y: r.maxY))

        // sobe e fecha com o filete da direita
        p.addLine(to: CGPoint(x: r.maxX, y: f + b))
        p.addQuadCurve(to: CGPoint(x: r.maxX - b, y: f),
                       control: CGPoint(x: r.maxX, y: f))
        p.addLine(to: CGPoint(x: d + f, y: f))
        p.addQuadCurve(to: CGPoint(x: d, y: 0),
                       control: CGPoint(x: d + f, y: 0))
        p.closeSubpath()
        return p
    }
}
