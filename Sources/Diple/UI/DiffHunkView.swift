import SwiftUI

struct DiffHunkView: View {
    let hunk: String
    var path: String = ""
    var line: Int?
    var startLine: Int?

    @Environment(\.codeTheme) private var theme

    struct Row: Identifiable {
        let id: Int
        let number: Int?
        let mark: Character
        let text: String
        let spans: [(String, Syntax)]
        var isHeader: Bool { mark == "@" }
    }

    @State private var expanded = false

    static let contextAbove = 3

    let folds: Bool

    init(hunk: String, path: String = "", line: Int? = nil, startLine: Int? = nil, folds: Bool = true) {
        self.hunk = hunk
        self.path = path
        self.line = line
        self.startLine = startLine
        self.folds = folds
    }

    static func visible(_ rows: [Row], expanded: Bool, line: Int? = nil, startLine: Int? = nil) -> (hidden: Int, rows: ArraySlice<Row>) {
        let code = rows.drop { $0.isHeader }
        guard !expanded else { return (0, rows[...]) }
        let end = line.flatMap { l in code.lastIndex { $0.number == l } } ?? code.indices.last
        guard let end else { return (0, rows[...]) }
        let first = startLine ?? (code[end].number.map { $0 - contextAbove })
        let start = first.flatMap { f in code[...end].firstIndex { ($0.number ?? .min) >= f } }
            ?? code.index(end, offsetBy: -contextAbove, limitedBy: code.startIndex) ?? code.startIndex
        let shown = code[start...end]
        let hidden = code.count - shown.count
        return hidden > 1 ? (hidden, shown) : (0, rows[...])
    }

    var body: some View {
        let all = HunkCache.rows(for: hunk, path: path)
        let folds = self.folds ? Self.visible(all, expanded: false, line: line, startLine: startLine).hidden : 0
        let shown = Self.visible(all, expanded: expanded || !self.folds, line: line, startLine: startLine)
        VStack(alignment: .leading, spacing: 0) {
            if folds > 0 {
                Button { expanded.toggle() } label: {
                    Label(expanded ? "Hide \(folds) lines" : "Show \(folds) more lines",
                          systemImage: expanded ? "arrow.down.and.line.horizontal.and.arrow.up"
                                                : "arrow.up.and.line.horizontal.and.arrow.down")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(theme.comment)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.gutter.opacity(0.10))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            ForEach(shown.rows) { row in
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

                        highlighted(row.spans)
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

    private func highlighted(_ spans: [(String, Syntax)]) -> Text {
        spans.reduce(Text("")) { acc, span in
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

    static func parse(_ hunk: String, highlighter: Highlighter) -> [Row] {
        var out: [Row] = []
        var n: Int?
        for raw in hunk.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(raw)
            if s.hasPrefix("@@") {
                if let additions = s.split(separator: "+").dropFirst().first,
                   let num = Int(additions.prefix(while: \.isNumber)) {
                    n = num
                }
                out.append(Row(id: out.count, number: nil, mark: "@", text: s, spans: [(s, .plain)]))
                continue
            }
            let mark = s.first ?? " "
            let text = String(s.dropFirst())
            if mark == "-" {
                out.append(Row(id: out.count, number: nil, mark: mark, text: text, spans: highlighter.spans(text)))
            } else {
                out.append(Row(id: out.count, number: n, mark: mark, text: text, spans: highlighter.spans(text)))
                if let c = n { n = c + 1 }
            }
        }
        return out
    }
}

@MainActor
enum HunkCache {
    private static var store: [String: [DiffHunkView.Row]] = [:]
    static let keeps = 300
    private(set) static var parses = 0

    static func rows(for hunk: String, path: String) -> [DiffHunkView.Row] {
        let key = path + "\u{0}" + hunk
        if let hit = store[key] { return hit }
        if store.count >= keeps { store.removeAll(keepingCapacity: true) }
        parses += 1
        let rows = DiffHunkView.parse(hunk, highlighter: Highlighter(language: .of(path: path)))
        store[key] = rows
        return rows
    }
}
