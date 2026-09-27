import SwiftUI

struct DiffHunkView: View {
    let hunk: String
    var path: String = ""

    @Environment(\.codeTheme) private var theme

    private struct Row: Identifiable {
        let id = UUID()
        let number: Int?
        let mark: Character
        let text: String
        var isHeader: Bool { mark == "@" }
    }

    private var highlighter: Highlighter {
        Highlighter(language: .of(path: path))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                if row.isHeader {
                    Text(row.text)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.comment)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.gutter.opacity(0.10))
                } else {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(edge(row.mark))
                            .frame(width: 2)

                        Text(row.number.map(String.init) ?? " ")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(theme.gutter)
                            .frame(width: 42, alignment: .trailing)
                            .padding(.trailing, 10)

                        Text(String(row.mark == " " ? " " : row.mark))
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(edge(row.mark))
                            .frame(width: 14, alignment: .leading)

                        highlighted(row.text)
                            .font(.system(size: 11.5, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.trailing, 12)
                    }
                    .padding(.vertical, 2)
                    .background(tint(row.mark))
                }
            }
        }
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.gutter.opacity(0.22), lineWidth: 1)
        )
    }

    private func highlighted(_ line: String) -> Text {
        highlighter.spans(line).reduce(Text("")) { acc, span in
            acc + Text(span.0).foregroundColor(theme.color(span.1))
        }
    }

    private func edge(_ mark: Character) -> Color {
        switch mark {
        case "+": theme.addedMark
        case "-": theme.removedMark
        default:  .clear
        }
    }

    private func tint(_ mark: Character) -> Color {
        switch mark {
        case "+": theme.addedTint
        case "-": theme.removedTint
        default:  .clear
        }
    }

    private var rows: [Row] {
        var out: [Row] = []
        var n: Int?
        for raw in hunk.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(raw)
            if s.hasPrefix("@@") {
                if let additions = s.split(separator: "+").dropFirst().first,
                   let num = Int(additions.prefix(while: \.isNumber)) {
                    n = num
                }
                out.append(Row(number: nil, mark: "@", text: s))
                continue
            }
            let mark = s.first ?? " "
            let text = String(s.dropFirst())
            if mark == "-" {
                out.append(Row(number: nil, mark: mark, text: text))
            } else {
                out.append(Row(number: n, mark: mark, text: text))
                if let c = n { n = c + 1 }
            }
        }
        return out
    }
}
