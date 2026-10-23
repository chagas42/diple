import Foundation

enum ReadyForReview {
    static let question = "Mark this pull request ready for review?"
    static let consequence = "GitHub notifies its reviewers right away, code owners included."
    static let confirm = "Mark Ready for Review"

    static func explain(_ error: Error) -> String {
        switch error {
        case ClientError.graphql(let messages):
            let text = messages.joined(separator: " ").lowercased()
            if text.contains("scope") { return missingScope }
            if text.contains("not accessible") { return fineGrained }
            if text.contains("permission") || text.contains("forbidden") { return refused }
            return messages.joined(separator: " · ")
        case ClientError.http(401, _):
            return "GitHub rejected the token Diple borrows from gh. Run gh auth login, then try again."
        case ClientError.http(403, _):
            return refused
        default:
            return error.localizedDescription
        }
    }

    static let missingScope = "The token Diple borrows from gh lacks the repo scope. Run gh auth refresh -s repo, then try again."
    static let fineGrained = "The token Diple borrows from gh cannot write pull requests. It needs Pull requests: write on this repository."
    static let refused = "GitHub refused: your account cannot mark this pull request ready for review."
}
