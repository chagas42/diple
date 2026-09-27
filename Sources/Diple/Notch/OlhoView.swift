import SwiftUI

/// Amêndoa: duas curvas que se encontram em ponta. Elipse achatada não lê
/// como olho — falta o canto.
struct FormaOlho: Shape {
    /// 1 = aberto, 0 = fechado.
    var abertura: CGFloat = 1

    var animatableData: CGFloat {
        get { abertura }
        set { abertura = newValue }
    }

    func path(in r: CGRect) -> Path {
        let cy = r.midY
        let h = (r.height / 2) * max(0.04, abertura)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: cy))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: cy),
                       control: CGPoint(x: r.midX, y: cy - h * 2))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: cy),
                       control: CGPoint(x: r.midX, y: cy + h * 2))
        p.closeSubpath()
        return p
    }
}

struct OlhoView: View {
    /// Direção do olhar, cada eixo de -1 a 1.
    var olhar: CGPoint
    var piscando: Bool
    var largura: CGFloat = 15

    private var abertura: CGFloat { piscando ? 0.05 : 1 }
    private var forma: FormaOlho { FormaOlho(abertura: abertura) }
    private var pupila: CGFloat { largura * 0.30 }
    private var alcance: CGFloat { largura * 0.17 }

    var body: some View {
        ZStack {
            forma.fill(.white.opacity(0.94))
            Circle()
                .fill(Color(red: 0.07, green: 0.08, blue: 0.10))
                .frame(width: pupila, height: pupila)
                .offset(x: olhar.x * alcance, y: olhar.y * alcance * 0.55)
                .overlay(
                    Circle()
                        .fill(.white.opacity(0.8))
                        .frame(width: pupila * 0.34, height: pupila * 0.34)
                        .offset(x: olhar.x * alcance - pupila * 0.22,
                                y: olhar.y * alcance * 0.55 - pupila * 0.22)
                )
        }
        .frame(width: largura, height: largura * 0.62)
        .clipShape(forma)
        .animation(.easeInOut(duration: 0.085), value: abertura)
        .animation(.spring(response: 0.24, dampingFraction: 0.6), value: olhar)
    }
}
