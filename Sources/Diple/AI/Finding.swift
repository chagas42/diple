import Foundation

enum Category: String, Codable, Sendable {
    case correcao, simplificacao, eficiencia, teste, outro

    var label: String {
        switch self {
        case .correcao:      "correctness"
        case .simplificacao: "simplification"
        case .eficiencia:    "efficiency"
        case .teste:         "test"
        case .outro:         "note"
        }
    }
}

enum Verdict: String, Codable, Sendable {
    case confirmado, plausivel
    var label: String { self == .confirmado ? "confirmed" : "plausible" }
}

struct Finding: Identifiable, Codable, Sendable, Equatable {
    var id = UUID()
    let path: String
    let line: Int?
    let category: Category
    let verdict: Verdict
    let summary: String
    let detail: String

    let scenario: String?

    var location: String {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return line.map { "\(name):\($0)" } ?? name
    }

    var markdown: String {
        var t = "**\(summary)**\n\n\(detail)"
        if let c = scenario, !c.isEmpty { t += "\n\n> Scenario: \(c)" }
        return t
    }

    enum CodingKeys: String, CodingKey {
        case path, line, category, verdict, summary, detail, scenario
    }
}

struct ProgressLine: Identifiable, Sendable, Equatable {
    let id = UUID()
    var text: String
    var done: Bool

    var repeats: Int = 1
}

enum ReviewStep: Sendable, Equatable {
    case preparando(String)
    case pensando
    case ferramenta(String)
    case pronto([Finding])
    case failing(String)
}
