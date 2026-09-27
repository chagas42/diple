import Foundation

/// O que aconteceu que pode merecer te interromper.
enum TipoEvento: String, Codable, Sendable, CaseIterable {
    case responderamVoce
    case comentaram
    case pediramReview
    case checkFalhou
    case aprovaram

    /// Som do sistema, em /System/Library/Sounds. `nil` = entra na lista, sem som.
    /// Basso é o som de erro clássico do macOS: o ouvido já sabe o que significa.
    var som: String? {
        switch self {
        case .responderamVoce: "Glass"
        case .comentaram:      "Pop"
        case .pediramReview:   "Tink"
        case .checkFalhou:     "Basso"
        case .aprovaram:       nil
        }
    }

    /// Falso = só aparece na fila, nunca vira banner.
    var interrompe: Bool { self != .aprovaram }

    var glifo: String {
        switch self {
        case .responderamVoce: "arrowshape.turn.up.left.fill"
        case .comentaram:      "bubble.left.fill"
        case .pediramReview:   "arrow.triangle.branch"
        case .checkFalhou:     "xmark.octagon.fill"
        case .aprovaram:       "checkmark.seal.fill"
        }
    }

    var rotulo: String {
        switch self {
        case .responderamVoce: "respondeu você"
        case .comentaram:      "comentou no seu PR"
        case .pediramReview:   "pediu sua review"
        case .checkFalhou:     "check falhou"
        case .aprovaram:       "aprovou"
        }
    }
}

struct Evento: Identifiable, Sendable {
    let id: String
    let tipo: TipoEvento
    let chave: String
    let url: URL
    let titulo: String
    let corpo: String
    /// Presente quando dá pra responder sem sair do banner.
    var threadId: String? = nil
}
