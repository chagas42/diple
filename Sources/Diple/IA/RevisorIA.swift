import Foundation

struct RevisorIA: Sendable {
    private static let liberado = [
        "Read", "Grep", "Glob",
        "Bash(git diff:*)", "Bash(git log:*)", "Bash(git show:*)", "Bash(git status:*)",
    ].joined(separator: " ")

    private static let bloqueado = [
        "Write", "Edit", "MultiEdit", "NotebookEdit",
        "Bash(gh:*)", "Bash(git push:*)", "Bash(git commit:*)",
        "Bash(curl:*)", "WebFetch",
    ].joined(separator: " ")

    func revisar(pr: PR, base: String, em pasta: URL, modelo: String) -> AsyncStream<PassoIA> {
        AsyncStream { cont in
            let tarefa = Task {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                p.arguments = [
                    "claude", "-p", prompt(pr: pr, base: base),
                    "--output-format", "stream-json",
                    "--verbose",
                    "--permission-mode", "dontAsk",
                    "--allowed-tools", Self.liberado,
                    "--disallowed-tools", Self.bloqueado,
                    "--model", modelo,
                ]
                p.currentDirectoryURL = pasta

                let saida = Pipe()
                p.standardOutput = saida
                p.standardError = Pipe()

                do { try p.run() } catch {
                    cont.yield(.falhou("não consegui rodar o claude: \(error.localizedDescription)"))
                    cont.finish()
                    return
                }

                var sobra = Data()
                var resultado: String?

                for try await pedaco in saida.fileHandleForReading.bytes.chunks() {
                    guard !Task.isCancelled else { break }
                    sobra.append(pedaco)
                    while let quebra = sobra.firstIndex(of: 0x0A) {
                        let linha = sobra[..<quebra]
                        sobra = sobra[sobra.index(after: quebra)...]
                        if let passo = interpretar(linha, resultado: &resultado) {
                            cont.yield(passo)
                        }
                    }
                }

                p.waitUntilExit()

                guard let texto = resultado else {
                    cont.yield(.falhou("a sessão terminou sem resposta"))
                    cont.finish()
                    return
                }
                cont.yield(.pronto(Self.extrair(texto)))
                cont.finish()
            }
            cont.onTermination = { _ in tarefa.cancel() }
        }
    }

    private func interpretar(_ linha: Data, resultado: inout String?) -> PassoIA? {
        guard !linha.isEmpty,
              let o = try? JSONSerialization.jsonObject(with: Data(linha)) as? [String: Any],
              let tipo = o["type"] as? String else { return nil }

        switch tipo {
        case "system":
            guard (o["subtype"] as? String) == "init" else { return nil }
            let m = (o["model"] as? String) ?? "?"
            return .preparando("sessão pronta · \(m)")

        case "assistant":
            let partes = ((o["message"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
            for c in partes where (c["type"] as? String) == "tool_use" {
                let nome = (c["name"] as? String) ?? "?"
                let alvo = ((c["input"] as? [String: Any])?["file_path"] as? String)
                    ?? ((c["input"] as? [String: Any])?["pattern"] as? String)
                    ?? ((c["input"] as? [String: Any])?["command"] as? String)
                let curto = alvo.map { String($0.split(separator: "/").last ?? "").prefix(40) }
                return .ferramenta(curto.map { "\(nome) \($0)" } ?? nome)
            }
            return .pensando

        case "result":
            resultado = o["result"] as? String
            return nil

        default:
            return nil
        }
    }

    static func extrair(_ texto: String) -> [Achado] {
        guard let inicio = texto.firstIndex(of: "{"),
              let fim = texto.lastIndex(of: "}") else { return [] }
        let corpo = String(texto[inicio...fim])
        struct Envelope: Decodable { let achados: [Achado] }
        guard let dados = corpo.data(using: .utf8),
              let env = try? JSONDecoder().decode(Envelope.self, from: dados) else { return [] }
        return env.achados
    }

    private func prompt(pr: PR, base: String) -> String {
        """
        Você está num worktree com o PR #\(pr.numero) de \(pr.repo) já em checkout.

        Título do PR: \(pr.titulo)

        Revise as mudanças deste PR. O diff é exatamente \
        `git diff \(base.isEmpty ? "origin/HEAD" : base)...HEAD` — use essa base \
        e nenhuma outra, senão você vai ver o repositório inteiro em vez do PR. \
        Leia os arquivos que precisar para entender o contexto. Siga as convenções deste repositório, incluindo \
        qualquer CLAUDE.md ou skill de review que exista aqui.

        Aponte só o que você conseguiria defender numa conversa: bug de verdade, \
        caso não tratado, regra do repositório quebrada, teste que não discrimina. \
        Não aponte estilo, preferência pessoal nem o que um linter já pega. \
        Se não houver nada que preste, devolva a lista vazia — isso é uma resposta \
        legítima e melhor que inventar.

        Escreva em português do Brasil, na segunda pessoa, direto ao ponto, como \
        alguém comentando na PR de um colega.

        Responda SOMENTE com este JSON, sem cerca de código e sem texto em volta:

        {"achados":[{"arquivo":"caminho/relativo.ts","linha":214,\
        "categoria":"correcao|simplificacao|eficiencia|teste",\
        "veredito":"confirmado|plausivel",\
        "resumo":"uma linha dizendo o que está errado",\
        "detalhe":"dois a quatro períodos explicando por quê",\
        "cenario":"entrada concreta que quebra, e o que acontece"}]}

        Use "confirmado" só quando você verificou lendo o código que o problema \
        existe. Use "plausivel" quando é uma suspeita que depende de contexto que \
        você não conseguiu conferir.
        """
    }
}

private extension FileHandle.AsyncBytes {
    func chunks() -> AsyncStream<Data> {
        AsyncStream { cont in
            Task {
                var buffer = Data()
                do {
                    for try await b in self {
                        buffer.append(b)
                        if buffer.count >= 4096 || b == 0x0A {
                            cont.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                } catch {}
                if !buffer.isEmpty { cont.yield(buffer) }
                cont.finish()
            }
        }
    }
}
