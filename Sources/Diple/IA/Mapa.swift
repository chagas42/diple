import Foundation

struct Modulo: Identifiable, Codable, Sendable, Equatable {
    var id: String { nome }
    let nome: String
    let caminho: String
    /// Por que este módulo importa aqui. Caixa que só diz o nome não vale o espaço.
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
    /// Uma frase: o que o PR está tentando fazer.
    var proposta: String = ""
    /// O que muda de comportamento, em chips curtos.
    var deltas: [String] = []
    /// Sai do diff, sem IA.
    var alterados: [Modulo] = []
    /// Não muda, mas sente. Sai do julgamento.
    var impactados: [Modulo] = []
    /// O PR não toca, mas sem isto você não consegue julgar.
    var contexto: [Contexto] = []
}

// MARK: - A parte determinística

extension GitHubClient {
    /// Arquivos do PR agrupados por módulo, mais a base do diff.
    ///
    /// A base importa: `origin/HEAD` local costuma estar desatualizado, e
    /// diferenciar contra ele devolve o repositório inteiro em vez do PR.
    /// `baseRefOid` é o commit exato de onde o PR saiu.
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

    /// Agrupa por diretório, ignorando o arquivo. Dois níveis costumam ser o
    /// domínio; um só vira "src" pra tudo.
    private static func moduloDe(_ caminho: String) -> String {
        let p = caminho.split(separator: "/").dropLast()
        guard !p.isEmpty else { return "raiz" }
        return p.prefix(3).joined(separator: "/")
    }
}
