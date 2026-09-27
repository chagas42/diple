import Foundation

struct MapaIA: Sendable {
    func desenhar(pr: PR, base: String, alterados: [Modulo], em pasta: URL, modelo: String) async -> Mapa? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [
            "claude", "-p", prompt(pr: pr, base: base, alterados: alterados),
            "--output-format", "json",
            "--permission-mode", "dontAsk",
            "--allowed-tools", "Read Grep Glob Bash(git diff:*) Bash(git log:*)",
            "--disallowed-tools", "Write Edit Bash(gh:*) Bash(git push:*) WebFetch",
            "--model", modelo,
        ]
        p.currentDirectoryURL = pasta
        let saida = Pipe()
        p.standardOutput = saida
        p.standardError = Pipe()

        do { try p.run() } catch { return nil }
        let dados = saida.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        guard let env = try? JSONSerialization.jsonObject(with: dados) as? [String: Any],
              let texto = env["result"] as? String else { return nil }

        guard let inicio = texto.firstIndex(of: "{"),
              let fim = texto.lastIndex(of: "}"),
              let corpo = String(texto[inicio...fim]).data(using: .utf8) else { return nil }

        struct Resposta: Decodable {
            let proposta: String
            let deltas: [String]
            let impactados: [Modulo]
            let contexto: [Contexto]
        }
        guard let r = try? JSONDecoder().decode(Resposta.self, from: corpo) else { return nil }

        return Mapa(
            proposta: r.proposta,
            deltas: Array(r.deltas.prefix(3)),
            alterados: alterados,
            impactados: Array(r.impactados.prefix(4)),
            contexto: Array(r.contexto.prefix(3))
        )
    }

    private func prompt(pr: PR, base: String, alterados: [Modulo]) -> String {
        let lista = alterados.map { "- \($0.caminho) (\($0.diff ?? ""))" }.joined(separator: "\n")
        return """
        Você está num worktree com o PR #\(pr.numero) de \(pr.repo) em checkout.

        Título: \(pr.titulo)

        Os módulos alterados eu já sei, saíram do diff:
        \(lista)

        Preciso de três coisas que o diff sozinho não me dá.

        1. A proposta: uma frase dizendo o que este PR está tentando fazer, em \
        português, na voz de quem explica pra um colega. Não descreva o diff, \
        diga a intenção.

        2. O que NÃO muda mas SENTE a mudança: no máximo 4 módulos que este PR \
        não altera, mas que dependem do que mudou. Para cada um diga em poucas \
        palavras POR QUE ele sente. "Herda o novo throw sem tratar" vale;
        "usa esse módulo" não vale.

        3. O que alguém precisa CONHECER pra julgar este PR e que não está no \
        diff: no máximo 3 assuntos. Regra de negócio implícita, contrato com \
        fornecedor, invariante que o código assume sem escrever, máquina de \
        estados. Para cada um diga por que sem isso a review fica fraca, e onde \
        ler, se existir arquivo ou doc no repositório.

        O diff é `git diff \(base.isEmpty ? "origin/HEAD" : base)...HEAD` — use essa base.\n        Explore o repositório o quanto precisar. Responda SOMENTE com este JSON, \
        sem cerca de código:

        {"proposta":"...",
         "deltas":["muda comportamento em 1 caminho","contrato de API intacto"],
         "impactados":[{"nome":"fila de workers","caminho":"src/workers",\
        "detalhe":"herda o novo throw sem tratar"}],
         "contexto":[{"titulo":"Máquina de estados da portabilidade",\
        "porque":"o PR assume que EXPIRADO volta pra PENDENTE, e isso não está escrito",\
        "onde":"docs/portability/states.md"}]}
        """
    }
}
