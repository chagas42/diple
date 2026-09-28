import SwiftUI

enum Syntax: Sendable {
    case plain, keyword, type, string, number, comment, function, punctuation
}

struct Highlighter {
    let language: Language

    enum Language: String, Sendable, CaseIterable {
        case swift, typescript, python, go, ruby, rust, sql, shell, none

        static func of(path: String) -> Language {
            switch path.split(separator: ".").last.map(String.init)?.lowercased() {
            case "swift":                      .swift
            case "ts", "tsx", "js", "jsx", "mjs": .typescript
            case "py":                         .python
            case "go":                         .go
            case "rb":                         .ruby
            case "rs":                         .rust
            case "sql":                        .sql
            case "sh", "bash", "zsh":          .shell
            default:                           .none
            }
        }

        private static let keywordSets: [Language: Set<String>] = Dictionary(
            uniqueKeysWithValues: allCases.map { ($0, $0.keywordList) }
        )

        var keywords: Set<String> { Self.keywordSets[self] ?? [] }

        private var keywordList: Set<String> {
            switch self {
            case .swift:
                ["func", "let", "var", "if", "else", "guard", "return", "struct", "class",
                 "enum", "case", "switch", "for", "in", "while", "import", "extension",
                 "protocol", "private", "public", "internal", "static", "async", "await",
                 "throws", "try", "catch", "do", "self", "nil", "true", "false", "some",
                 "where", "init", "deinit", "defer", "actor", "nonisolated", "throw"]
            case .typescript:
                ["const", "let", "var", "function", "return", "if", "else", "for", "while",
                 "class", "interface", "type", "enum", "import", "export", "from", "async",
                 "await", "new", "this", "null", "undefined", "true", "false", "try",
                 "catch", "throw", "extends", "implements", "public", "private", "readonly",
                 "static", "as", "of", "in", "default", "yield"]
            case .python:
                ["def", "class", "return", "if", "elif", "else", "for", "while", "import",
                 "from", "as", "with", "try", "except", "raise", "async", "await", "lambda",
                 "None", "True", "False", "self", "not", "and", "or", "in", "is", "pass",
                 "yield", "global"]
            case .go:
                ["func", "var", "const", "type", "struct", "interface", "return", "if",
                 "else", "for", "range", "package", "import", "go", "defer", "chan", "map",
                 "nil", "true", "false", "switch", "case", "select"]
            case .ruby:
                ["def", "end", "class", "module", "if", "elsif", "else", "unless", "while",
                 "do", "return", "require", "attr_accessor", "nil", "true", "false", "self",
                 "yield", "begin", "rescue", "raise"]
            case .rust:
                ["fn", "let", "mut", "if", "else", "match", "struct", "enum", "impl",
                 "trait", "use", "pub", "return", "for", "in", "while", "loop", "async",
                 "await", "self", "Self", "None", "Some", "Ok", "Err", "true", "false"]
            case .sql:
                ["select", "from", "where", "join", "left", "right", "inner", "outer", "on",
                 "group", "order", "by", "having", "insert", "into", "values", "update",
                 "set", "delete", "create", "table", "alter", "drop", "and", "or", "not",
                 "null", "as", "with", "union", "limit", "distinct"]
            case .shell:
                ["if", "then", "else", "fi", "for", "in", "do", "done", "while", "case",
                 "esac", "function", "return", "export", "local", "echo", "set", "exit"]
            case .none: []
            }
        }

        var lineComment: String? {
            switch self {
            case .python, .ruby, .shell: "#"
            case .sql:                   "--"
            case .none:                  nil
            default:                     "//"
            }
        }
    }

    func spans(_ line: String) -> [(String, Syntax)] {
        guard language != .none else { return [(line, .plain)] }

        if let marker = language.lineComment {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(marker) { return [(line, .comment)] }
            if let r = line.range(of: marker), !insideString(line, upTo: r.lowerBound) {
                return spans(String(line[line.startIndex..<r.lowerBound]))
                     + [(String(line[r.lowerBound...]), .comment)]
            }
        }

        var out: [(String, Syntax)] = []
        var buffer = ""
        var i = line.startIndex

        func flush() {
            guard !buffer.isEmpty else { return }
            out.append((buffer, classify(buffer, next: i < line.endIndex ? line[i] : " ")))
            buffer = ""
        }

        while i < line.endIndex {
            let c = line[i]

            if c == "\"" || c == "'" || c == "`" {
                flush()
                var lit = String(c)
                var j = line.index(after: i)
                while j < line.endIndex {
                    let d = line[j]
                    lit.append(d)
                    if d == c && line[line.index(before: j)] != "\\" { j = line.index(after: j); break }
                    j = line.index(after: j)
                }
                out.append((lit, .string))
                i = j
                continue
            }

            if c.isLetter || c == "_" || c == "$" || c.isNumber {
                buffer.append(c)
                i = line.index(after: i)
                continue
            }

            flush()
            out.append((String(c), c.isWhitespace ? .plain : .punctuation))
            i = line.index(after: i)
        }
        flush()
        return out
    }

    private func classify(_ word: String, next: Character) -> Syntax {
        if language.keywords.contains(word) { return .keyword }
        if let f = word.first, f.isNumber { return .number }
        if next == "(" { return .function }
        if let f = word.first, f.isUppercase { return .type }
        return .plain
    }

    private func insideString(_ line: String, upTo idx: String.Index) -> Bool {
        var quotes = 0
        var i = line.startIndex
        while i < idx {
            let c = line[i]
            if c == "\"" || c == "'" || c == "`" { quotes += 1 }
            i = line.index(after: i)
        }
        return quotes % 2 == 1
    }
}

extension CodeTheme {
    func color(_ t: Syntax) -> Color {
        switch t {
        case .plain:       plain
        case .keyword:     keyword
        case .type:        type
        case .string:      string
        case .number:      number
        case .comment:     comment
        case .function:    function
        case .punctuation: punctuation
        }
    }
}
