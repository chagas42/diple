import Foundation

enum TokenError: LocalizedError {
    case ghMissing
    case ghFailed(String)

    var errorDescription: String? {
        switch self {
        case .ghMissing:
            "gh was not found. Install it with `brew install gh`, then run `gh auth login`."
        case .ghFailed(let output):
            output.isEmpty
                ? "gh auth token returned nothing. Run `gh auth login` in a terminal."
                : "gh auth token failed: \(output)"
        }
    }
}

enum Token {
    static func current() throws -> String {
        let p: Process
        do { p = try Tools.process("gh", ["auth", "token"]) }
        catch { throw TokenError.ghMissing }

        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err

        do { try p.run() } catch { throw TokenError.ghMissing }
        p.waitUntilExit()

        let text = String(
            decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard p.terminationStatus == 0, !text.isEmpty else {
            let failure = String(
                decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            throw TokenError.ghFailed(failure)
        }
        return text
    }
}
