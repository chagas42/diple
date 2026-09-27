import Foundation

/// Um worktree descartável por review. O seu checkout não é tocado, e dá pra
/// revisar um PR enquanto você programa em outro.
enum Worktree {
    struct Erro: LocalizedError {
        let msg: String
        var errorDescription: String? { msg }
    }

    static var raiz: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".diple/worktrees", isDirectory: true)
    }

    /// Onde o repositório está na sua máquina. Procura nos lugares óbvios
    /// antes de pedir configuração.
    static func localDe(_ repo: String, configurados: [String: String]) -> URL? {
        if let p = configurados[repo] {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        }
        let nome = repo.split(separator: "/").last.map(String.init) ?? repo
        let casa = FileManager.default.homeDirectoryForCurrentUser
        let candidatos = ["@studies", "@work", "dev", "work", "Developer", "code", "src"]
            .map { casa.appendingPathComponent($0).appendingPathComponent(nome) }
            + [casa.appendingPathComponent(nome)]

        return candidatos.first { url in
            var pasta: ObjCBool = false
            let existe = FileManager.default.fileExists(
                atPath: url.appendingPathComponent(".git").path, isDirectory: &pasta
            )
            return existe
        }
    }

    /// Cria o worktree na ref do PR. Usa refs/pull/N/head, que existe mesmo
    /// quando o PR vem de fork.
    @discardableResult
    static func preparar(origem: URL, repo: String, pr: Int, base: String = "") async throws -> URL {
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        let nome = "\(repo.replacingOccurrences(of: "/", with: "-"))-\(pr)"
        let destino = raiz.appendingPathComponent(nome)

        // Reaproveita se já está no commit certo: refazer custa ~3s de fetch
        // e checkout de milhares de arquivos, e conferir custa 10ms.
        if FileManager.default.fileExists(atPath: destino.path) {
            let atual = try? await git(["rev-parse", "HEAD"], em: destino)
            let alvo = try? await git(["rev-parse", "refs/diple/pr-\(pr)"], em: origem)
            let mesmo = atual?.trimmingCharacters(in: .whitespacesAndNewlines)
                == alvo?.trimmingCharacters(in: .whitespacesAndNewlines)
            if mesmo, atual?.isEmpty == false { return destino }
            try? await git(["worktree", "remove", "--force", destino.path], em: origem)
        }
        var refs = ["+refs/pull/\(pr)/head:refs/diple/pr-\(pr)"]
        // Sem trazer a base, ela pode não existir localmente e o diff sai
        // contra um origin/HEAD velho — o que devolve o repositório inteiro.
        if !base.isEmpty { refs.append(base) }
        _ = try await git(["fetch", "origin"] + refs + ["--force"], em: origem)
        _ = try await git(["worktree", "add", "--detach", destino.path, "refs/diple/pr-\(pr)"], em: origem)
        return destino
    }

    /// Varre o que sobrou de execuções que morreram no meio. Sem isso cada
    /// app fechado durante um review deixa um checkout inteiro no disco.
    static func limparOrfaos() async {
        let fm = FileManager.default
        guard let pastas = try? fm.contentsOfDirectory(
            at: raiz, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        for p in pastas {
            let data = (try? p.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            // Uma hora é folga de sobra: nenhum review honesto dura tanto.
            guard Date().timeIntervalSince(data) > 3600 else { continue }
            // `git worktree remove` roda de dentro do próprio worktree.
            _ = try? await git(["worktree", "remove", "--force", p.path], em: p)
            try? fm.removeItem(at: p)
        }
    }

    static func descartar(origem: URL, destino: URL) async {
        _ = try? await git(["worktree", "remove", "--force", destino.path], em: origem)
    }

    @discardableResult
    static func git(_ args: [String], em pasta: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["git"] + args
            p.currentDirectoryURL = pasta
            let saida = Pipe(), erro = Pipe()
            p.standardOutput = saida
            p.standardError = erro
            try p.run()
            let texto = String(decoding: saida.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let falha = String(decoding: erro.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                throw Erro(msg: "git \(args.first ?? ""): \(falha.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            return texto
        }.value
    }
}
