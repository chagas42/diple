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
    /// Altura do recorte. O painel desce reto nessa faixa — ela fica atrás do
    /// bezel, onde não existe display — e só abre depois dela.
    var alturaNotch: CGFloat = 0
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

        let n = min(alturaNotch, r.height)

        var p = Path()
        p.move(to: CGPoint(x: e, y: 0))
        // desce reto pela lateral do recorte
        p.addLine(to: CGPoint(x: e, y: n))

        // e só então abre pra esquerda, com um filete côncavo
        p.addQuadCurve(to: CGPoint(x: e - f, y: n + f),
                       control: CGPoint(x: e - f, y: n))
        p.addLine(to: CGPoint(x: r.minX + b, y: n + f))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: n + f + b),
                       control: CGPoint(x: r.minX, y: n + f))

        // desce, contorna a base
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - b))
        p.addQuadCurve(to: CGPoint(x: r.minX + b, y: r.maxY),
                       control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - b, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY - b),
                       control: CGPoint(x: r.maxX, y: r.maxY))

        // sobe e fecha com o filete da direita
        p.addLine(to: CGPoint(x: r.maxX, y: n + f + b))
        p.addQuadCurve(to: CGPoint(x: r.maxX - b, y: n + f),
                       control: CGPoint(x: r.maxX, y: n + f))
        p.addLine(to: CGPoint(x: d + f, y: n + f))
        p.addQuadCurve(to: CGPoint(x: d, y: n),
                       control: CGPoint(x: d + f, y: n))
        p.addLine(to: CGPoint(x: d, y: 0))
        p.closeSubpath()
        return p
    }
}
