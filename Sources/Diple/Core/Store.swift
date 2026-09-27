import Foundation

/// O que a gente lembra de cada PR entre uma sincronização e outra.
/// É a diferença entre dois instantâneos que vira evento.
struct Instantaneo: Codable, Sendable, Equatable {
    var atualizadoEm: Date
    var ci: String
    var aprovado: Bool
    var ultimoComentarioEm: Date?
    var emRevisar: Bool
}

struct EstadoSalvo: Codable, Sendable {
    var prs: [String: Instantaneo] = [:]
    var naoLidos: Set<String> = []
    /// Primeira execução não notifica nada: senão a estreia dispara 38 banners.
    var jaRodouUmaVez: Bool = false
}

@MainActor
final class Store {
    private(set) var estado = EstadoSalvo()

    private let arquivo: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Diple", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("estado.json")
    }()

    init() { carregar() }

    private func carregar() {
        guard let d = try? Data(contentsOf: arquivo),
              let e = try? JSONDecoder().decode(EstadoSalvo.self, from: d) else { return }
        estado = e
    }

    private func salvar() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(estado).write(to: arquivo, options: .atomic)
    }

    func marcarLido(_ chave: String) {
        estado.naoLidos.remove(chave)
        salvar()
    }

    func marcarTudoLido() {
        estado.naoLidos.removeAll()
        salvar()
    }

    /// Compara a fila nova com o que estava salvo e devolve o que mudou.
    func diferenca(_ fila: Fila, meuLogin: String) -> [Evento] {
        var eventos: [Evento] = []
        var novos: [String: Instantaneo] = [:]
        let estreia = !estado.jaRodouUmaVez

        let emRevisar = Set(fila.revisar.map(\.chave))

        for pr in fila.todos {
            let agora = Instantaneo(
                atualizadoEm: pr.atualizadoEm,
                ci: pr.ci.rawValue,
                aprovado: pr.aprovado,
                ultimoComentarioEm: pr.ultimoComentario?.quando,
                emRevisar: emRevisar.contains(pr.chave)
            )
            novos[pr.chave] = agora

            guard !estreia else { continue }
            let antes = estado.prs[pr.chave]

            // Pediram sua review: entrou na fila de revisar agora.
            if agora.emRevisar, antes?.emRevisar != true {
                eventos.append(Evento(
                    id: "\(pr.chave)/review/\(pr.atualizadoEm.timeIntervalSince1970)",
                    tipo: .pediramReview, chave: pr.chave, url: pr.url,
                    titulo: "\(pr.autor) pediu sua review",
                    corpo: "\(pr.chave) · \(pr.titulo)"
                ))
            }

            // Check quebrou: só na transição pra falho, não a cada retentativa.
            if pr.souEuOAutor, agora.ci == EstadoCI.falhou.rawValue,
               let a = antes, a.ci != EstadoCI.falhou.rawValue {
                eventos.append(Evento(
                    id: "\(pr.chave)/ci/\(pr.atualizadoEm.timeIntervalSince1970)",
                    tipo: .checkFalhou, chave: pr.chave, url: pr.url,
                    titulo: "Um check falhou no seu PR",
                    corpo: "\(pr.chave) · \(pr.titulo)"
                ))
            }

            // Comentário humano novo. Se te cita, é resposta: som mais forte.
            if let c = pr.ultimoComentario,
               antes?.ultimoComentarioEm != c.quando,
               antes != nil {
                let citou = c.trecho.localizedCaseInsensitiveContains("@\(meuLogin)")
                eventos.append(Evento(
                    id: "\(pr.chave)/msg/\(c.quando.timeIntervalSince1970)",
                    tipo: citou ? .responderamVoce : .comentaram,
                    chave: pr.chave, url: pr.url,
                    titulo: citou ? "\(c.autor) respondeu você" : "\(c.autor) comentou no seu PR",
                    corpo: c.onde.map { "\($0) — \(c.trecho)" } ?? c.trecho,
                    threadId: c.threadId
                ))
            }

            // Aprovaram: entra na fila, sem som.
            if pr.souEuOAutor, agora.aprovado, antes?.aprovado == false {
                eventos.append(Evento(
                    id: "\(pr.chave)/ok/\(pr.atualizadoEm.timeIntervalSince1970)",
                    tipo: .aprovaram, chave: pr.chave, url: pr.url,
                    titulo: "Seu PR foi aprovado",
                    corpo: "\(pr.chave) · \(pr.titulo)"
                ))
            }
        }

        estado.prs = novos
        estado.jaRodouUmaVez = true
        for e in eventos { estado.naoLidos.insert(e.chave) }
        salvar()
        return eventos
    }
}
