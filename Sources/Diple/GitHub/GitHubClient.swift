import Foundation

enum ClienteErro: LocalizedError {
    case http(Int)
    case graphql([String])
    case vazio

    var errorDescription: String? {
        switch self {
        case .http(let c):      "GitHub respondeu HTTP \(c)"
        case .graphql(let m):   m.joined(separator: " · ")
        case .vazio:            "GitHub respondeu sem dados"
        }
    }
}

struct GitHubClient: Sendable {
    private let endpoint = URL(string: "https://api.github.com/graphql")!

    func buscarFila() async throws -> Fila {
        let token = try await Task.detached(priority: .utility) {
            try Token.atual()
        }.value

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Diple/0.1", forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONEncoder().encode(["query": Query.fila])
        req.timeoutInterval = 20

        let (dados, resposta) = try await URLSession.shared.data(for: req)

        if let http = resposta as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClienteErro.http(http.statusCode)
        }

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let corpo = try dec.decode(Resposta.self, from: dados)

        if let erros = corpo.errors, !erros.isEmpty {
            throw ClienteErro.graphql(erros.map(\.message))
        }
        guard let d = corpo.data else { throw ClienteErro.vazio }

        let eu = d.viewer.login
        return Fila(
            eu: eu,
            meus: d.meus.nodes.compactMap { PR($0, meuLogin: eu) },
            revisar: d.revisar.nodes.compactMap { PR($0, meuLogin: eu) },
            envolvido: d.envolvido.nodes.compactMap { PR($0, meuLogin: eu) },
            cotaRestante: d.rateLimit?.remaining ?? 0
        )
    }
}
