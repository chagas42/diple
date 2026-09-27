import SwiftUI

/// Um olho que acompanha o ponteiro. É o que o repouso mostra: só ele e o número.
struct OlhoView: View {
    /// Direção do olhar, cada eixo de -1 a 1.
    var olhar: CGPoint
    var piscando: Bool
    var tamanho: CGFloat = 17

    private var raioPupila: CGFloat { tamanho * 0.30 }
    private var alcance: CGFloat { tamanho * 0.21 }

    var body: some View {
        ZStack {
            Ellipse()
                .fill(.white.opacity(0.93))
            Circle()
                .fill(.black)
                .frame(width: raioPupila * 2, height: raioPupila * 2)
                .offset(x: olhar.x * alcance, y: olhar.y * alcance)
            // O brilho fica preso à pupila, senão o olho parece de vidro.
            Circle()
                .fill(.white.opacity(0.75))
                .frame(width: raioPupila * 0.5, height: raioPupila * 0.5)
                .offset(x: olhar.x * alcance - raioPupila * 0.35,
                        y: olhar.y * alcance - raioPupila * 0.35)
        }
        .frame(width: tamanho, height: tamanho * (piscando ? 0.08 : 0.72))
        .clipShape(Ellipse())
        .animation(.easeInOut(duration: 0.09), value: piscando)
        .animation(.spring(response: 0.22, dampingFraction: 0.62), value: olhar)
    }
}
