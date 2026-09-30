import Foundation

struct Settings: Codable, Sendable, Equatable {
    var alerts: [String: Bool] = [:]

    var sounds: [String: String] = [:]
    var quietHoursOn = true
    var quietFrom = 19
    var quietUntil = 9
    var quietOnWeekends = true
    var stackPerPR = false

    var mutedRepos: Set<String> = []
    var interval: TimeInterval = 60

    var aiModel = "opus"
    var reviewLanguage = "Brazilian Portuguese"

    var repoPaths: [String: String] = [:]

    var editor: String? = nil
    var codeTheme: String = "diple-dark"
    var attribution: String = Attribution.onMyOwn.rawValue
    var mapModel: String? = nil
    var shareUsage = true
    var reviewFilter = ReviewFilter.everyone
    var showsEye = true
    var eyeBlinks = true
    var countSide = CountSide.right
    var liquidNotch = true
    var fitsMenuBar = false
    var showsReviews = true

    var openIn: Editor { editor.flatMap(Editor.init(rawValue:)) ?? .vscode }
    var mapAIModel: String { mapModel ?? "sonnet" }

    static let reviewLanguages = ["Brazilian Portuguese", "English", "Spanish"]

    static let availableSounds = [
        "Glass", "Pop", "Tink", "Basso", "Hero", "Blow", "Bottle",
        "Frog", "Funk", "Morse", "Ping", "Purr", "Sosumi", "Submarine",
    ]

    func alerts(_ t: EventKind) -> Bool {
        alerts[t.rawValue] ?? t.interrupts
    }

    func sound(_ t: EventKind) -> String? {
        guard let s = sounds[t.rawValue] else { return t.sound }
        return s.isEmpty ? nil : s
    }

    enum AlertSound: Equatable {
        case plays(String)
        case silent
        case quietHours
        case muted
    }

    func alertSound(_ e: Event, now: Date = Date()) -> AlertSound {
        if e.isTest {
            let name = sounds[e.kind.rawValue] ?? e.kind.sound
            return name.flatMap { $0.isEmpty ? nil : AlertSound.plays($0) } ?? .silent
        }
        guard alerts(e.kind) else { return .muted }
        guard shouldInterrupt(e.kind, now: now) else { return .quietHours }
        return sound(e.kind).map(AlertSound.plays) ?? .silent
    }

    func shouldInterrupt(_ t: EventKind, now: Date = Date()) -> Bool {
        guard alerts(t) else { return false }
        guard quietHoursOn else { return true }
        if t == .repliedToYou { return true }

        let cal = Calendar.current
        if quietOnWeekends, cal.isDateInWeekend(now) { return false }

        let h = cal.component(.hour, from: now)

        let calado = quietFrom > quietUntil
            ? (h >= quietFrom || h < quietUntil)
            : (h >= quietFrom && h < quietUntil)
        return !calado
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var d = Settings()
        d.alerts = try c.decodeIfPresent([String: Bool].self, forKey: .alerts) ?? d.alerts
        d.sounds = try c.decodeIfPresent([String: String].self, forKey: .sounds) ?? d.sounds
        d.quietHoursOn = try c.decodeIfPresent(Bool.self, forKey: .quietHoursOn) ?? d.quietHoursOn
        d.quietFrom = try c.decodeIfPresent(Int.self, forKey: .quietFrom) ?? d.quietFrom
        d.quietUntil = try c.decodeIfPresent(Int.self, forKey: .quietUntil) ?? d.quietUntil
        d.quietOnWeekends = try c.decodeIfPresent(Bool.self, forKey: .quietOnWeekends) ?? d.quietOnWeekends
        d.stackPerPR = try c.decodeIfPresent(Bool.self, forKey: .stackPerPR) ?? d.stackPerPR
        d.mutedRepos = try c.decodeIfPresent(Set<String>.self, forKey: .mutedRepos) ?? d.mutedRepos
        d.interval = try c.decodeIfPresent(TimeInterval.self, forKey: .interval) ?? d.interval
        d.aiModel = try c.decodeIfPresent(String.self, forKey: .aiModel) ?? d.aiModel
        d.reviewLanguage = try c.decodeIfPresent(String.self, forKey: .reviewLanguage) ?? d.reviewLanguage
        d.repoPaths = try c.decodeIfPresent([String: String].self, forKey: .repoPaths) ?? d.repoPaths
        d.editor = try c.decodeIfPresent(String.self, forKey: .editor) ?? d.editor
        d.codeTheme = try c.decodeIfPresent(String.self, forKey: .codeTheme) ?? d.codeTheme
        d.attribution = try c.decodeIfPresent(String.self, forKey: .attribution) ?? d.attribution
        d.mapModel = try c.decodeIfPresent(String.self, forKey: .mapModel) ?? d.mapModel
        d.shareUsage = try c.decodeIfPresent(Bool.self, forKey: .shareUsage) ?? d.shareUsage
        d.reviewFilter = (try? c.decodeIfPresent(ReviewFilter.self, forKey: .reviewFilter)) ?? d.reviewFilter
        d.showsEye = try c.decodeIfPresent(Bool.self, forKey: .showsEye) ?? d.showsEye
        d.eyeBlinks = try c.decodeIfPresent(Bool.self, forKey: .eyeBlinks) ?? d.eyeBlinks
        d.countSide = (try? c.decodeIfPresent(CountSide.self, forKey: .countSide)) ?? d.countSide
        d.liquidNotch = try c.decodeIfPresent(Bool.self, forKey: .liquidNotch) ?? d.liquidNotch
        d.fitsMenuBar = try c.decodeIfPresent(Bool.self, forKey: .fitsMenuBar) ?? d.fitsMenuBar
        d.showsReviews = try c.decodeIfPresent(Bool.self, forKey: .showsReviews) ?? d.showsReviews
        self = d
    }

}

enum Attribution: String, CaseIterable, Identifiable, Sendable {
    case always, onMyOwn, never
    var id: String { rawValue }

    var label: String {
        switch self {
        case .always:  "On every pull request"
        case .onMyOwn: "Only on my own"
        case .never:   "Never"
        }
    }

    var blurb: String {
        switch self {
        case .always:  "Everyone sees where the comment came from."
        case .onMyOwn: "Answering yourself reads oddly without it; on someone else's PR the comment is simply yours."
        case .never:   "The comment goes out as your words alone."
        }
    }

    func applies(mine: Bool) -> Bool {
        switch self {
        case .always:  true
        case .onMyOwn: mine
        case .never:   false
        }
    }
}

extension Settings {
    var attributionMode: Attribution { Attribution(rawValue: attribution) ?? .onMyOwn }
}

enum CountSide: String, Codable, Sendable, CaseIterable, Identifiable {
    case left, right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left:  "Left"
        case .right: "Right"
        }
    }
}

enum ReviewFilter: String, Codable, Sendable, CaseIterable, Identifiable {
    case everyone, pickedFirst, onlyPicked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyone:    "Everyone"
        case .pickedFirst: "Picked first"
        case .onlyPicked:  "Only picked"
        }
    }

    var label: String { "Reviews: \(title.lowercased())" }

    var detail: String {
        switch self {
        case .everyone:    "Every review request counts and alerts."
        case .pickedFirst: "Review requests from picked people come first."
        case .onlyPicked:  "Others stay in Reviewing, quietly. Asked by name still alerts."
        }
    }

    static func isPicked(_ pr: PR, picked: Set<String>) -> Bool {
        pr.asksYouByName || picked.contains(pr.author)
    }

    func order(_ prs: [PR], picked: Set<String>) -> [PR] {
        guard self != .everyone, !picked.isEmpty else { return prs }
        return prs.filter { Self.isPicked($0, picked: picked) } + prs.filter { !Self.isPicked($0, picked: picked) }
    }

    func quiets(_ pr: PR, picked: Set<String>) -> Bool {
        self == .onlyPicked && !picked.isEmpty && !Self.isPicked(pr, picked: picked)
    }

    static func staysQuiet(unread: Bool, reason: EventKind?) -> Bool {
        !unread || reason == nil || reason == .reviewRequested
    }
}
