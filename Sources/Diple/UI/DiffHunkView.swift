import SwiftUI

struct DiffHunkView: View {
    let hunk: String

    private struct Row: Identifiable {
        let id = UUID()
        let number: Int?
        let sinal: Character
        let text: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { l in
                HStack(spacing: 0) {
                    Text(l.number.map(String.init) ?? "")
                        .frame(width: 46, alignment: .trailing)
                        .padding(.trailing, 12)
                        .foregroundStyle(.tertiary)
                    Text(String(l.sinal))
                        .frame(width: 12, alignment: .leading)
                        .foregroundStyle(color(l.sinal))
                    Text(l.text)
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

    private var rows: [Row] {
        var out: [Row] = []
        var n: Int? = nil
        for bruta in hunk.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(bruta)
            if s.hasPrefix("@@") {
                if let additions = s.split(separator: "+").dropFirst().first,
                   let num = Int(additions.prefix(while: \.isNumber)) {
                    n = num
                }
                out.append(Row(number: nil, sinal: " ", text: s))
                continue
            }
            let sinal = s.first ?? " "
            let text = String(s.dropFirst())
            if sinal == "-" {
                out.append(Row(number: nil, sinal: sinal, text: text))
            } else {
                out.append(Row(number: n, sinal: sinal, text: text))
                if let current = n { n = current + 1 }
            }
        }
        return out
    }

    private func color(_ s: Character) -> Color {
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
