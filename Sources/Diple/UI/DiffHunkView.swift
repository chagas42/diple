import SwiftUI

struct DiffHunkView: View {
    let hunk: String

    private struct Linha: Identifiable {
        let id = UUID()
        let numero: Int?
        let sinal: Character
        let texto: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(linhas) { l in
                HStack(spacing: 0) {
                    Text(l.numero.map(String.init) ?? "")
                        .frame(width: 46, alignment: .trailing)
                        .padding(.trailing, 12)
                        .foregroundStyle(.tertiary)
                    Text(String(l.sinal))
                        .frame(width: 12, alignment: .leading)
                        .foregroundStyle(cor(l.sinal))
                    Text(l.texto)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 11.5, design: .monospaced))
                .padding(.vertical, 1.5)
                .background(fundo(l.sinal))
            }
        }
        .padding(.vertical, 6)
    }

    private var linhas: [Linha] {
        var saida: [Linha] = []
        var n: Int? = nil
        for bruta in hunk.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(bruta)
            if s.hasPrefix("@@") {
                if let mais = s.split(separator: "+").dropFirst().first,
                   let num = Int(mais.prefix(while: \.isNumber)) {
                    n = num
                }
                saida.append(Linha(numero: nil, sinal: " ", texto: s))
                continue
            }
            let sinal = s.first ?? " "
            let texto = String(s.dropFirst())
            if sinal == "-" {
                saida.append(Linha(numero: nil, sinal: sinal, texto: texto))
            } else {
                saida.append(Linha(numero: n, sinal: sinal, texto: texto))
                if let atual = n { n = atual + 1 }
            }
        }
        return saida
    }

    private func cor(_ s: Character) -> Color {
        switch s { case "+": .green; case "-": .red; default: .secondary.opacity(0.55) }
    }

    private func fundo(_ s: Character) -> Color {
        switch s {
        case "+": .green.opacity(0.10)
        case "-": .red.opacity(0.09)
        default:  .clear
        }
    }
}
