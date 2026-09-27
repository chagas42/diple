import Foundation

struct Modulo: Identifiable, Codable, Sendable, Equatable {
    var id: String { nome }
    let nome: String
    let caminho: String

    let detalhe: String
    var mais: Int = 0
    var menos: Int = 0

    var diff: String? { (mais + menos) > 0 ? "+\(mais) −\(menos)" : nil }
}

struct Contexto: Identifiable, Codable, Sendable, Equatable {
    var id: String { titulo }
    let titulo: String
    let porque: String
    let onde: String?
}

struct Mapa: Codable, Sendable, Equatable {
    var proposta: String = ""

    var deltas: [String] = []

    var alterados: [Modulo] = []

    var impactados: [Modulo] = []

    var contexto: [Contexto] = []
}

extension GitHubClient {
    func baseEModulos(repo: String, pr: Int) async throws -> (base: String, modulos: [Modulo]) {
        let partes = repo.split(separator: "/")
        guard partes.count == 2 else { return ("", []) }

        let json = try await bruto("""
        { repository(owner: "\(partes[0])", name: "\(partes[1])") {
            pullRequest(number: \(pr)) {
              baseRefOid
              baseRefName
              files(first: 100) { nodes { path additions deletions } }
            }
        } }
        """)

        let dados = json["data"] as? [String: Any]
        let repositorio = dados?["repository"] as? [String: Any]
        let pull = repositorio?["pullRequest"] as? [String: Any]
        let arquivos = pull?["files"] as? [String: Any]
        let nos = arquivos?["nodes"] as? [[String: Any]] ?? []
        let base = (pull?["baseRefOid"] as? String) ?? ""

        var porModulo: [String: (mais: Int, menos: Int, arquivos: Int)] = [:]
        for f in nos {
            guard let caminho = f["path"] as? String else { continue }
            let chave = Self.moduloDe(caminho)
            var atual = porModulo[chave] ?? (0, 0, 0)
            atual.mais += (f["additions"] as? Int) ?? 0
            atual.menos += (f["deletions"] as? Int) ?? 0
            atual.arquivos += 1
            porModulo[chave] = atual
        }

        let modulos = porModulo
            .map { chave, v in
                Modulo(
                    nome: chave.split(separator: "/").last.map(String.init) ?? chave,
                    caminho: chave,
                    detalhe: "\(v.arquivos) arquivo\(v.arquivos == 1 ? "" : "s")",
                    mais: v.mais, menos: v.menos
                )
            }
            .sorted { ($0.mais + $0.menos) > ($1.mais + $1.menos) }
            .prefix(4)
            .map { $0 }
        return (base, modulos)
    }

    private static func moduloDe(_ caminho: String) -> String {
        let p = caminho.split(separator: "/").dropLast()
        guard !p.isEmpty else { return "raiz" }
        return p.prefix(3).joined(separator: "/")
    }
}
