import Foundation

enum TokenError: LocalizedError {
    case ghAusente
    case ghFalhou(String)

    var errorDescription: String? {
        switch self {
        case .ghAusente:
            "O gh não está instalado. Instale com: brew install gh"
        case .ghFalhou(let saida):
            "gh auth token falhou: \(saida)"
        }
    }
}

enum Token {
    static func atual() throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["gh", "auth", "token"]

        let saida = Pipe()
        let erro = Pipe()
        p.standardOutput = saida
        p.standardError = erro

        do { try p.run() } catch { throw TokenError.ghAusente }
        p.waitUntilExit()

        let texto = String(
            data: saida.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard p.terminationStatus == 0, !texto.isEmpty else {
            let e = String(
                data: erro.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw TokenError.ghFalhou(e.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return texto
    }
}
