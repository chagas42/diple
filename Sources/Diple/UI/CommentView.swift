import SwiftUI

struct CommentView: View {
    let comment: PR.ThreadComment
    let path: String
    var alwaysNamed = false

    @Environment(\.codeTheme) private var theme
    @State private var expanded = false
    @State private var hovering = false

    var body: some View {
        if comment.isBot {
            bot
        } else {
            human
        }
    }

    private var human: some View {
        HStack(alignment: .top, spacing: 10) {
            InitialsBubble(login: comment.author)
                .help(comment.author)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    if hovering || alwaysNamed {
                        Text(comment.author)
                            .font(.system(size: 12.5, weight: .semibold))
                            .transition(.opacity)
                    }
                    Text(comment.at.formatted(.relative(presentation: .numeric)))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .frame(height: 15)

                Markdownish(text: comment.text, path: path)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .contentShape(Rectangle())
        .onHover { over in
            withAnimation(.easeOut(duration: 0.12)) { hovering = over }
        }
    }

    private var bot: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(comment.author)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(comment.at.formatted(.relative(presentation: .numeric)))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.quaternary)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14).padding(.vertical, 8)

            if expanded {
                Markdownish(text: comment.text, path: path)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 11)
            }
        }
        .background(.quaternary.opacity(0.18))
    }

    private var summary: String {
        let clean = comment.text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { line in
                !line.isEmpty
                && !line.hasPrefix("#")
                && !line.hasPrefix("```")
                && !line.hasPrefix("<!--")
            } ?? ""
        let stripped = clean
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
        return stripped.count > 90 ? String(stripped.prefix(90)) + "…" : stripped
    }
}

struct InitialsBubble: View {
    let login: String

    private var initials: String {
        let parts = login.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == "." })
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    private var tint: Color {
        let hues: [Color] = [.orange, .purple, .teal, .pink, .indigo, .green, .blue, .red]
        var seed: UInt64 = 5381
        for b in login.utf8 { seed = seed &* 33 &+ UInt64(b) }
        return hues[Int(seed % UInt64(hues.count))]
    }

    var body: some View {
        Circle()
            .fill(tint.opacity(0.22))
            .overlay(
                Text(initials)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
            )
            .frame(width: 24, height: 24)
    }
}

struct Markdownish: View {
    let text: String
    var path: String = ""

    @Environment(\.codeTheme) private var theme

    private enum Block: Identifiable {
        case prose(String)
        case code(String, String)
        case bullet([String])
        var id: String {
            switch self {
            case .prose(let s):   "p" + s.prefix(24)
            case .code(let s, _): "c" + s.prefix(24)
            case .bullet(let b):  "b" + (b.first?.prefix(24) ?? "")
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                switch block {
                case .prose(let s):
                    Text(inline(s))
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .bullet(let items):
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 7) {
                                Text("•").foregroundStyle(.tertiary)
                                Text(inline(item))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.system(size: 13))
                        }
                    }
                case .code(let body, let lang):
                    ScrollView(.horizontal, showsIndicators: false) {
                        CodeBlock(source: body, language: lang.isEmpty ? path : "x.\(lang)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(s)
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var prose: [String] = []
        var bullets: [String] = []
        var code: [String] = []
        var lang = ""
        var inCode = false

        func flushProse() {
            let joined = prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { out.append(.prose(joined)) }
            prose = []
        }
        func flushBullets() {
            if !bullets.isEmpty { out.append(.bullet(bullets)); bullets = [] }
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let t = line.trimmingCharacters(in: .whitespaces)

            if t.hasPrefix("```") {
                if inCode {
                    out.append(.code(code.joined(separator: "\n"), lang))
                    code = []; lang = ""; inCode = false
                } else {
                    flushProse(); flushBullets()
                    lang = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inCode = true
                }
                continue
            }
            if inCode { code.append(line); continue }

            if t.hasPrefix("- ") || t.hasPrefix("* ") {
                flushProse()
                bullets.append(String(t.dropFirst(2)))
                continue
            }
            flushBullets()
            prose.append(line)
        }
        if inCode, !code.isEmpty { out.append(.code(code.joined(separator: "\n"), lang)) }
        flushProse(); flushBullets()
        return out
    }
}

struct CodeBlock: View {
    let source: String
    let language: String

    @Environment(\.codeTheme) private var theme

    var body: some View {
        let h = Highlighter(language: .of(path: language))
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(source.split(separator: "\n", omittingEmptySubsequences: false).enumerated()),
                    id: \.offset) { _, line in
                h.spans(String(line))
                    .reduce(Text("")) { $0 + Text($1.0).foregroundColor(theme.color($1.1)) }
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(theme.gutter.opacity(0.2), lineWidth: 1)
        )
    }
}
