import Foundation

enum TokenError: LocalizedError {
    case ghAusente
    case ghFalhou(String)

    var errorDescription: String? {
        switch self {
        case .ghAusente:
            "gh is not installed. Install it with: brew install gh"
        case .ghFalhou(let out):
            "gh auth token failing: \(out)"
        }
    }
}

enum Token {
    static func current() throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["gh", "auth", "token"]

        let out = Pipe()
        let error = Pipe()
        p.standardOutput = out
        p.standardError = error

        do { try p.run() } catch { throw TokenError.ghAusente }
        p.waitUntilExit()

        let text = String(
            data: out.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard p.terminationStatus == 0, !text.isEmpty else {
            let e = String(
                data: error.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw TokenError.ghFalhou(e.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return text
    }
}
