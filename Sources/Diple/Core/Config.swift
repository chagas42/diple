import Foundation

struct Config: Codable, Sendable, Equatable {
    var avisa: [String: Bool] = [:]

    var sons: [String: String] = [:]
    var silencioLigado = true
    var silencioDe = 19
    var silencioAte = 9
    var silencioNoFimDeSemana = true

    var silenciados: Set<String> = []
    var intervalo: TimeInterval = 60

    var modeloIA = "opus"

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

    func deixaPassar(_ t: TipoEvento, agora: Date = Date()) -> Bool {
        guard avisa(t) else { return false }
        guard silencioLigado else { return true }
        if t == .responderamVoce { return true }

        let cal = Calendar.current
        if silencioNoFimDeSemana, cal.isDateInWeekend(agora) { return false }

        let h = cal.component(.hour, from: agora)

        let calado = silencioDe > silencioAte
            ? (h >= silencioDe || h < silencioAte)
            : (h >= silencioDe && h < silencioAte)
        return !calado
    }
}
