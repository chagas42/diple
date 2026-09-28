import Foundation

enum TelemetryValue: Sendable, Equatable, Encodable {
    case int(Int)
    case bool(Bool)
    case text(String)
    indirect case list([TelemetryValue])
    indirect case object([String: TelemetryValue])

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let v):    try c.encode(v)
        case .bool(let v):   try c.encode(v)
        case .text(let v):   try c.encode(v)
        case .list(let v):   try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

enum TelemetryEvent: Sendable, Equatable {
    enum Outcome: String, Sendable { case done, failed }
    enum Source: String, Sendable { case notch, window, notification, menuBar = "menu_bar" }
    enum Rating: String, Sendable { case up, down }

    enum DurationBucket: String, Sendable {
        case under30s = "lt_30s"
        case under2m = "lt_2m"
        case under5m = "lt_5m"
        case longer = "gte_5m"

        init(seconds: TimeInterval) {
            switch seconds {
            case ..<30:  self = .under30s
            case ..<120: self = .under2m
            case ..<300: self = .under5m
            default:     self = .longer
            }
        }
    }

    case appActive(needsYou: Int, mine: Int, toReview: Int)
    case aiReviewStarted(deep: Bool)
    case aiReviewFinished(outcome: Outcome, findings: Int, threadsJudged: Int, deep: Bool, duration: DurationBucket)
    case mapBuilt(outcome: Outcome, prsInStack: Int, duration: DurationBucket)
    case replySent(source: Source)
    case threadResolved(source: Source)
    case findingPosted
    case prOpened(source: Source)
    case notificationShown(kind: EventKind)
    case feedbackSubmitted(feature: FeedbackFeature, rating: Rating?, text: String)
    case error(ErrorReport)

    var name: String {
        switch self {
        case .appActive:         "app_active"
        case .aiReviewStarted:   "ai_review_started"
        case .aiReviewFinished:  "ai_review_finished"
        case .mapBuilt:          "map_built"
        case .replySent:         "reply_sent"
        case .threadResolved:    "thread_resolved"
        case .findingPosted:     "finding_posted"
        case .prOpened:          "pr_opened"
        case .notificationShown: "notification_shown"
        case .feedbackSubmitted: "feedback_submitted"
        case .error:             "$exception"
        }
    }

    var properties: [String: TelemetryValue] {
        var p: [String: TelemetryValue] = [:]
        switch self {
        case .appActive(let needsYou, let mine, let toReview):
            p["needs_you"] = .int(needsYou)
            p["mine"] = .int(mine)
            p["to_review"] = .int(toReview)
        case .aiReviewStarted(let deep):
            p["deep"] = .bool(deep)
        case .aiReviewFinished(let outcome, let findings, let threadsJudged, let deep, let duration):
            p["outcome"] = .text(outcome.rawValue)
            p["findings"] = .int(findings)
            p["threads_judged"] = .int(threadsJudged)
            p["deep"] = .bool(deep)
            p["duration"] = .text(duration.rawValue)
        case .mapBuilt(let outcome, let prsInStack, let duration):
            p["outcome"] = .text(outcome.rawValue)
            p["prs_in_stack"] = .int(prsInStack)
            p["duration"] = .text(duration.rawValue)
        case .replySent(let source):
            p["source"] = .text(source.rawValue)
        case .threadResolved(let source):
            p["source"] = .text(source.rawValue)
        case .prOpened(let source):
            p["source"] = .text(source.rawValue)
        case .findingPosted:
            break
        case .notificationShown(let kind):
            p["kind"] = .text(kind.rawValue)
        case .feedbackSubmitted(let feature, let rating, let text):
            p["feature"] = .text(feature.rawValue)
            p["rating"] = .text(rating?.rawValue ?? "none")
            p["text"] = .text(FeedbackText.clean(text))
        case .error(let r):
            p["$exception_list"] = .list([.object([
                "type": .text(r.type),
                "value": .text("\(r.operation.rawValue): \(r.domain) \(r.code)"),
                "mechanism": .object(["handled": .bool(true), "synthetic": .bool(false)]),
            ])])
            p["$exception_level"] = .text("error")
            p["$exception_fingerprint"] = .text(r.fingerprint)
            p["operation"] = .text(r.operation.rawValue)
            p["error_domain"] = .text(r.domain)
            p["error_code"] = .int(r.code)
        }
        return p
    }
}
