import Foundation

/// O que você escolheu. Mora junto do estado, em Application Support.
struct Config: Codable, Sendable, Equatable {
    /// Quais eventos viram banner. O que fica de fora continua entrando na
    /// fila — só não interrompe.
    var avisa: [String: Bool] = [:]
    /// Som por tipo de evento. Vazio = entra sem som.
    var sons: [String: String] = [:]
    var silencioLigado = true
    var silencioDe = 19
    var silencioAte = 9
    var silencioNoFimDeSemana = true
    /// Repositórios que não geram aviso nenhum.
    var silenciados: Set<String> = []
    var intervalo: TimeInterval = 60
    /// Modelo do SEU plano. O Diple não paga token nenhum.
    var modeloIA = "opus"
    /// repo -> pasta local. Vazio = o Diple procura sozinho.
    var caminhos: [String: String] = [:]

    static let sonsDisponiveis = [
        "Glass", "Pop", "Tink", "Basso", "Hero", "Blow", "Bottle",
        "Frog", "Funk", "Morse", "Ping", "Purr", "Sosumi", "Submarine",
    ]

    func avisa(_ t: TipoEvento) -> Bool {
        avisa[t.rawValue] ?? t.interrompe
    }

    func som(_ t: TipoEvento) -> String? {
        guard let s = sons[t.rawValue] else { return t.som }
        return s.isEmpty ? nil : s
    }

    /// Só quem responde você diretamente fura o silêncio.
    func deixaPassar(_ t: TipoEvento, agora: Date = Date()) -> Bool {
        guard avisa(t) else { return false }
        guard silencioLigado else { return true }
        if t == .responderamVoce { return true }

        let cal = Calendar.current
        if silencioNoFimDeSemana, cal.isDateInWeekend(agora) { return false }

        let h = cal.component(.hour, from: agora)
        // Janela que cruza a meia-noite: 19h às 9h é "fora do horário".
        let calado = silencioDe > silencioAte
            ? (h >= silencioDe || h < silencioAte)
            : (h >= silencioDe && h < silencioAte)
        return !calado
    }
}
