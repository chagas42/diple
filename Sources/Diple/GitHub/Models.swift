import Foundation

// MARK: - Resposta crua

struct Resposta: Decodable, Sendable {
    let data: Dados?
    let errors: [ErroGraphQL]?

    struct Dados: Decodable, Sendable {
        let viewer: Viewer
        let meus: Busca
        let revisar: Busca
        let envolvido: Busca
        let rateLimit: Cota?
    }

    struct Viewer: Decodable, Sendable { let login: String }

    struct Busca: Decodable, Sendable {
        let nodes: [PRCru?]
    }

    struct Cota: Decodable, Sendable {
        let remaining: Int
        let resetAt: Date
    }
}

struct ErroGraphQL: Decodable, Sendable {
    let message: String
}

struct Ator: Decodable, Sendable {
    let login: String
    let __typename: String

    var ehBot: Bool {
        __typename == "Bot" || login.hasSuffix("[bot]") || Ator.conhecidos.contains(login)
    }

    /// Bots que se apresentam como User e mesmo assim são ruído.
    private static let conhecidos: Set<String> = [
        "github-actions", "coderabbitai", "dependabot", "renovate",
        "codecov", "sonarcloud", "vercel", "sentry-io",
    ]
}

struct PRCru: Decodable, Sendable {
    let id: String
    let number: Int
    let title: String
    let url: URL
    let updatedAt: Date
    let isDraft: Bool
    let repository: Repo
    let author: Ator?
    let reviewDecision: String?
    let comments: Comentarios
    let reviewThreads: Threads
    let commits: Commits

    struct Repo: Decodable, Sendable { let nameWithOwner: String }
    struct Comentarios: Decodable, Sendable { let nodes: [Comentario?] }
    struct Comentario: Decodable, Sendable {
        let author: Ator?
        let createdAt: Date
        let bodyText: String
    }
    struct Threads: Decodable, Sendable { let nodes: [Thread?] }
    struct Thread: Decodable, Sendable {
        let id: String
        let isResolved: Bool
        let path: String?
        let line: Int?
        let comments: Comentarios
    }
    struct Commits: Decodable, Sendable { let nodes: [CommitNode?] }
    struct CommitNode: Decodable, Sendable { let commit: Commit }
    struct Commit: Decodable, Sendable { let statusCheckRollup: Rollup? }
    struct Rollup: Decodable, Sendable { let state: String }
}

// MARK: - Modelo do app

enum EstadoCI: String, Sendable {
    case passou, falhou, rodando, nenhum

    init(_ bruto: String?) {
        switch bruto {
        case "SUCCESS":  self = .passou
        case "FAILURE", "ERROR": self = .falhou
        case "PENDING", "EXPECTED": self = .rodando
        default: self = .nenhum
        }
    }
}

struct PR: Identifiable, Sendable, Equatable {
    let id: String
    let repo: String
    let numero: Int
    let titulo: String
    let url: URL
    let atualizadoEm: Date
    let rascunho: Bool
    let autor: String
    let souEuOAutor: Bool
    let ci: EstadoCI
    let aprovado: Bool
    /// Último comentário de gente, já sem bot.
    let ultimoComentario: ComentarioHumano?

    struct ComentarioHumano: Sendable, Equatable {
        let autor: String
        let quando: Date
        let trecho: String
        /// Preenchido quando veio de uma thread inline: "resend.ts:214".
        let onde: String?
        /// Só existe em comentário inline — é o que permite responder de dentro do app.
        let threadId: String?
    }

    var chave: String { "\(repo)#\(numero)" }

    init?(_ c: PRCru?, meuLogin: String) {
        guard let c else { return nil }
        id = c.id
        repo = c.repository.nameWithOwner
        numero = c.number
        titulo = c.title
        url = c.url
        atualizadoEm = c.updatedAt
        rascunho = c.isDraft
        autor = c.author?.login ?? "?"
        souEuOAutor = c.author?.login == meuLogin
        ci = EstadoCI(c.commits.nodes.compactMap { $0 }.first?.commit.statusCheckRollup?.state)
        aprovado = c.reviewDecision == "APPROVED"

        // Duas fontes distintas: a conversa do PR e as threads inline no código.
        // Quase toda resposta de verdade é inline — sem as duas, o app fica cego.
        func humano(_ com: PRCru.Comentario) -> Bool {
            guard let a = com.author else { return false }
            return !a.ehBot && a.login != meuLogin
        }
        func limpar(_ t: String) -> String {
            String(t.prefix(180)).replacingOccurrences(of: "\n", with: " ")
        }

        var candidatos: [ComentarioHumano] = c.comments.nodes
            .compactMap { $0 }
            .filter(humano)
            .map { .init(autor: $0.author?.login ?? "?", quando: $0.createdAt,
                         trecho: limpar($0.bodyText), onde: nil, threadId: nil) }

        for t in c.reviewThreads.nodes.compactMap({ $0 }) where !t.isResolved {
            let onde = t.path.map { p in
                let arquivo = p.split(separator: "/").last.map(String.init) ?? p
                return t.line.map { "\(arquivo):\($0)" } ?? arquivo
            }
            candidatos += t.comments.nodes
                .compactMap { $0 }
                .filter(humano)
                .map { .init(autor: $0.author?.login ?? "?", quando: $0.createdAt,
                             trecho: limpar($0.bodyText), onde: onde, threadId: t.id) }
        }

        ultimoComentario = candidatos.max { $0.quando < $1.quando }
    }
}

struct Fila: Sendable, Equatable {
    var eu: String = ""
    var meus: [PR] = []
    var revisar: [PR] = []
    var envolvido: [PR] = []
    var cotaRestante: Int = 0

    var todos: [PR] { meus + revisar + envolvido }
}
