import Foundation

enum Category: String, Codable, Sendable {
    case correctness, simplification, efficiency, test, note

    var label: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self))?.lowercased() ?? ""
        self = Category(rawValue: raw) ?? .note
    }
}

enum Verdict: String, Codable, Sendable {
    case confirmed, plausible

    var label: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self))?.lowercased() ?? ""
        self = raw == "confirmed" ? .confirmed : .plausible
    }
}

enum Severity: String, Codable, Sendable, CaseIterable {
    case high, medium, low, request

    var label: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self))?.lowercased() ?? ""
        self = Severity(rawValue: raw) ?? .low
    }
}

struct Finding: Identifiable, Codable, Sendable, Equatable {
    var id = UUID()
    let path: String
    let line: Int?
    let category: Category
    let verdict: Verdict
    let summary: String
    let detail: String
    let scenario: String?

    var pr: Int? = nil
    var severity: Severity? = nil
    var axis: String? = nil
    var inline: Bool? = nil
    var comment: String? = nil
    var raised: String? = nil

    var location: String {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return line.map { "\(name):\($0)" } ?? name
    }

    var markdown: String {
        if let c = comment, !c.isEmpty { return c }
        var t = "**\(summary)**\n\n\(detail)"
        if let c = scenario, !c.isEmpty { t += "\n\n> Scenario: \(c)" }
        return t
    }

    enum CodingKeys: String, CodingKey {
        case path, line, category, verdict, summary, detail, scenario
        case pr, severity, axis, inline, comment, raised, why
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? c.decode(String.self, forKey: .path)) ?? ""
        line = try? c.decodeIfPresent(Int.self, forKey: .line)
        category = (try? c.decode(Category.self, forKey: .category)) ?? .note
        verdict = (try? c.decode(Verdict.self, forKey: .verdict)) ?? .plausible
        summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        detail = (try? c.decodeIfPresent(String.self, forKey: .detail))
            ?? (try? c.decodeIfPresent(String.self, forKey: .why)) ?? ""
        scenario = try? c.decodeIfPresent(String.self, forKey: .scenario)
        pr = try? c.decodeIfPresent(Int.self, forKey: .pr)
        severity = try? c.decodeIfPresent(Severity.self, forKey: .severity)
        axis = try? c.decodeIfPresent(String.self, forKey: .axis)
        inline = try? c.decodeIfPresent(Bool.self, forKey: .inline)
        comment = try? c.decodeIfPresent(String.self, forKey: .comment)
        raised = (try? c.decodeIfPresent(String.self, forKey: .raised)).flatMap { $0.isEmpty ? nil : $0 }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(path, forKey: .path)
        try c.encodeIfPresent(line, forKey: .line)
        try c.encode(category, forKey: .category)
        try c.encode(verdict, forKey: .verdict)
        try c.encode(summary, forKey: .summary)
        try c.encode(detail, forKey: .detail)
        try c.encodeIfPresent(scenario, forKey: .scenario)
        try c.encodeIfPresent(pr, forKey: .pr)
        try c.encodeIfPresent(severity, forKey: .severity)
        try c.encodeIfPresent(axis, forKey: .axis)
        try c.encodeIfPresent(inline, forKey: .inline)
        try c.encodeIfPresent(comment, forKey: .comment)
        try c.encodeIfPresent(raised, forKey: .raised)
    }
}

struct ThreadVerdict: Codable, Sendable, Equatable, Identifiable {
    enum Kind: String, Sendable, CaseIterable {
        case holds, doesNotHold = "does-not-hold", partly, solved, outdated

        var label: String {
            switch self {
            case .holds:       "holds"
            case .doesNotHold: "does not hold"
            case .partly:      "partly holds"
            case .solved:      "already solved"
            case .outdated:    "outdated"
            }
        }
    }

    let id: String
    let verdict: String
    let reason: String
    let reply: String?

    var kind: Kind {
        Kind(rawValue: verdict.lowercased().replacingOccurrences(of: " ", with: "-")) ?? .partly
    }
}

struct ReviewResult: Sendable, Equatable {
    var summary = ""
    var findings: [Finding] = []
    var threads: [ThreadVerdict] = []
    var clean: [String] = []
    var dropped: [String] = []
    var deep = false

    var novel: [Finding] { findings.filter { $0.raised == nil } }
    var alreadyRaised: [Finding] { findings.filter { $0.raised != nil } }
}

struct ProgressLine: Identifiable, Sendable, Equatable {
    let id = UUID()
    var text: String
    var done: Bool

    var repeats: Int = 1
}

enum ReviewStep: Sendable, Equatable {
    case preparing(String)
    case thinking
    case tool(String)
    case done(ReviewResult)
    case failed(String)
}
