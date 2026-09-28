import Foundation

enum FeedbackFeature: String, CaseIterable, Sendable, Identifiable {
    case queue, team, ranking, activity, pullRequest = "pull_request", aiReview = "ai_review", map, settings, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .queue:       "Queue"
        case .team:        "Team"
        case .ranking:     "Ranking"
        case .activity:    "Activity"
        case .pullRequest: "Pull request details"
        case .aiReview:    "AI review"
        case .map:         "PR map"
        case .settings:    "Settings"
        case .general:     "Diple in general"
        }
    }
}

enum FeedbackText {
    static let limit = 2000
    static let maxURLLength = 7000
    static let repository = "chagas42/diple"

    private static let redactions: [(NSRegularExpression, String)] = [
        (#"\b(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"#, "[redacted token]"),
        (#"\bsk-[A-Za-z0-9_\-]{16,}"#, "[redacted key]"),
        (#"\bphx_[A-Za-z0-9]{20,}"#, "[redacted key]"),
        (#"\bAKIA[0-9A-Z]{16}\b"#, "[redacted key]"),
        (#"(?i)\bbearer\s+[A-Za-z0-9._\-]{16,}"#, "Bearer [redacted]"),
        (#"(?i)[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#, "[email]"),
        (#"/Users/[^/\s]+"#, "~"),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    private static let blankRun = try! NSRegularExpression(pattern: #"\n{4,}"#)

    static func clean(_ raw: String, limit: Int = limit) -> String {
        var s = raw.precomposedStringWithCanonicalMapping
        s = String(String.UnicodeScalarView(s.unicodeScalars.filter(isAllowed)))
        s = redact(s)
        s = replace(blankRun, in: s, with: "\n\n\n")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count > limit { s = String(s.prefix(limit)) }
        return s
    }

    static func redact(_ s: String) -> String {
        redactions.reduce(s) { acc, rule in replace(rule.0, in: acc, with: rule.1) }
    }

    private static func isAllowed(_ u: Unicode.Scalar) -> Bool {
        if u == "\n" || u == "\t" { return true }
        switch u.properties.generalCategory {
        case .control, .format, .surrogate, .privateUse, .unassigned: return false
        default: return true
        }
    }

    private static func replace(_ r: NSRegularExpression, in s: String, with template: String) -> String {
        r.stringByReplacingMatches(
            in: s, range: NSRange(s.startIndex..., in: s),
            withTemplate: NSRegularExpression.escapedTemplate(for: template)
        )
    }

    static func diagnostics(feature: FeedbackFeature, version: String, os: String, machine: String) -> String {
        """
        | | |
        |---|---|
        | Diple | \(version) |
        | macOS | \(os) |
        | Mac | \(machine) |
        | Feature | \(feature.title) |
        """
    }

    static func issueURL(title: String, description: String, feature: FeedbackFeature, diagnostics: String?) -> URL {
        let cleanTitle = clean(title, limit: 120)
        let heading = cleanTitle.isEmpty ? "\(feature.title): " : cleanTitle
        var text = clean(description)
        func build(_ body: String) -> URL {
            var parts = [body.isEmpty ? "_Describe what happened, and what you expected._" : body]
            parts.append("_Screenshots help: paste or drag them into this box._")
            if let diagnostics { parts.append("---\n\(diagnostics)") }
            var c = URLComponents(string: "https://github.com/\(repository)/issues/new")!
            c.queryItems = [
                URLQueryItem(name: "title", value: heading),
                URLQueryItem(name: "body", value: parts.joined(separator: "\n\n")),
                URLQueryItem(name: "labels", value: "from-app"),
            ]
            return c.url!
        }
        var url = build(text)
        while url.absoluteString.count > maxURLLength, !text.isEmpty {
            text = String(text.prefix(max(0, text.count - max(50, (url.absoluteString.count - maxURLLength) / 3))))
            url = build(text + "\n\n…(cut to fit; continue here)")
        }
        return url
    }
}
