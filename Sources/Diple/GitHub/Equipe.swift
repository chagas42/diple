import Foundation

struct Pessoa: Identifiable, Sendable, Equatable, Codable {
    let login: String
    let nome: String
    let avatar: URL
    var id: String { login }

    var iniciais: String {
        let partes = nome.split(separator: " ").prefix(2)
        let s = partes.compactMap { $0.first }.map(String.init).joined()
        return s.isEmpty ? String(login.prefix(2)).uppercased() : s.uppercased()
    }
}

struct LinhaRank: Identifiable, Sendable, Equatable {
    let pessoa: Pessoa
    let reviews: Int
    var id: String { pessoa.login }
}

struct DiaRitmo: Identifiable, Sendable, Equatable {
    let data: Date
    let reviews: Int
    var id: TimeInterval { data.timeIntervalSince1970 }
}

extension GitHubClient {
    func buscarEquipe(org: String) async throws -> [Pessoa] {
        let json = try await bruto("""
        { organization(login: "\(org)") {
            membersWithRole(first: 50) {
              nodes { login name avatarUrl(size: 96) }
            }
        } }
        """)
        let nos = ((json["data"] as? [String: Any])?["organization"] as? [String: Any])
            .flatMap { ($0["membersWithRole"] as? [String: Any])?["nodes"] as? [[String: Any]] } ?? []
        return nos.compactMap { n in
            guard let login = n["login"] as? String,
                  let url = (n["avatarUrl"] as? String).flatMap(URL.init) else { return nil }
            return Pessoa(login: login, nome: (n["name"] as? String) ?? login, avatar: url)
        }
    }

    func buscarRank(org: String, pessoas: [Pessoa], desde: Date) async throws -> [LinhaRank] {
        guard !pessoas.isEmpty else { return [] }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        let corte = fmt.string(from: desde)

        let alvos = Array(pessoas.prefix(30))
        let buscas = alvos.enumerated().map { i, p in
            """
              u\(i): search(query: "is:pr org:\(org) reviewed-by:\(p.login) created:>\(corte)", \
            type: ISSUE, first: 1) { issueCount }
            """
        }.joined(separator: "\n")

        let json = try await bruto("{\n\(buscas)\n}")
        let dados = json["data"] as? [String: Any] ?? [:]
        return alvos.enumerated().compactMap { i, p in
            guard let n = (dados["u\(i)"] as? [String: Any])?["issueCount"] as? Int else { return nil }
            return LinhaRank(pessoa: p, reviews: n)
        }
        .sorted { $0.reviews > $1.reviews }
    }

    func buscarRitmo(org: String, login: String, dias: Int = 182) async throws -> [DiaRitmo] {
        let json = try await bruto("""
        { search(query: "is:pr org:\(org) reviewed-by:\(login) sort:updated", type: ISSUE, first: 100) {
            nodes { ... on PullRequest {
              reviews(first: 20, author: "\(login)") { nodes { submittedAt } }
            } }
        } }
        """)
        let nos = ((json["data"] as? [String: Any])?["search"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []

        let iso = ISO8601DateFormatter()
        var porDia: [String: Int] = [:]
        for pr in nos {
            let rs = (pr["reviews"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
            for r in rs {
                guard let s = r["submittedAt"] as? String, iso.date(from: s) != nil else { continue }
                porDia[String(s.prefix(10)), default: 0] += 1
            }
        }

        let cal = Calendar.current
        let hoje = cal.startOfDay(for: Date())
        let dia = DateFormatter()
        dia.dateFormat = "yyyy-MM-dd"
        dia.timeZone = .current

        return (0..<dias).reversed().compactMap { atras in
            guard let d = cal.date(byAdding: .day, value: -atras, to: hoje) else { return nil }
            return DiaRitmo(data: d, reviews: porDia[dia.string(from: d)] ?? 0)
        }
    }

    func bruto(_ query: String) async throws -> [String: Any] {
        let token = try await Task.detached(priority: .utility) { try Token.atual() }.value
        var req = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        req.httpMethod = "POST"
        req.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Diple/0.1", forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONEncoder().encode(["query": query])
        req.timeoutInterval = 20

        let (dados, resposta) = try await URLSession.shared.data(for: req)
        if let http = resposta as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClienteErro.http(http.statusCode)
        }
        let obj = try JSONSerialization.jsonObject(with: dados) as? [String: Any] ?? [:]
        if let erros = obj["errors"] as? [[String: Any]], !erros.isEmpty {
            throw ClienteErro.graphql(erros.compactMap { $0["message"] as? String })
        }
        return obj
    }
}
