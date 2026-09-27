import Foundation

enum Categoria: String, Codable, Sendable {
    case correcao, simplificacao, eficiencia, teste, outro

    var rotulo: String {
        switch self {
        case .correcao:      "correção"
        case .simplificacao: "simplificação"
        case .eficiencia:    "eficiência"
        case .teste:         "teste"
        case .outro:         "observação"
        }
    }
}

enum Veredito: String, Codable, Sendable {
    case confirmado, plausivel
    var rotulo: String { self == .confirmado ? "confirmado" : "plausível" }
}

struct Achado: Identifiable, Codable, Sendable, Equatable {
    var id = UUID()
    let arquivo: String
    let linha: Int?
    let categoria: Categoria
    let veredito: Veredito
    let resumo: String
    let detalhe: String

    let cenario: String?

    var onde: String {
        let nome = arquivo.split(separator: "/").last.map(String.init) ?? arquivo
        return linha.map { "\(nome):\($0)" } ?? nome
    }

    var markdown: String {
        var t = "**\(resumo)**\n\n\(detalhe)"
        if let c = cenario, !c.isEmpty { t += "\n\n> Cenário: \(c)" }
        return t
    }

    enum CodingKeys: String, CodingKey {
        case arquivo, linha, categoria, veredito, resumo, detalhe, cenario
    }
}

struct LinhaProgresso: Identifiable, Sendable, Equatable {
    let id = UUID()
    var texto: String
    var concluido: Bool

    var repeticoes: Int = 1
}

enum PassoIA: Sendable, Equatable {
    case preparando(String)
    case pensando
    case ferramenta(String)
    case pronto([Achado])
    case falhou(String)
}
