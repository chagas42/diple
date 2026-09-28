import Foundation

struct Settings: Codable, Sendable, Equatable {
    var alerts: [String: Bool] = [:]

    var sounds: [String: String] = [:]
    var quietHoursOn = true
    var quietFrom = 19
    var quietUntil = 9
    var quietOnWeekends = true

    var mutedRepos: Set<String> = []
    var interval: TimeInterval = 60

    var aiModel = "opus"
    var reviewLanguage = "Brazilian Portuguese"

    var repoPaths: [String: String] = [:]

    var editor: String? = nil
    var codeTheme: String = "diple-dark"
    var mapModel: String? = nil

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
        d.mutedRepos = try c.decodeIfPresent(Set<String>.self, forKey: .mutedRepos) ?? d.mutedRepos
        d.interval = try c.decodeIfPresent(TimeInterval.self, forKey: .interval) ?? d.interval
        d.aiModel = try c.decodeIfPresent(String.self, forKey: .aiModel) ?? d.aiModel
        d.reviewLanguage = try c.decodeIfPresent(String.self, forKey: .reviewLanguage) ?? d.reviewLanguage
        d.repoPaths = try c.decodeIfPresent([String: String].self, forKey: .repoPaths) ?? d.repoPaths
        d.editor = try c.decodeIfPresent(String.self, forKey: .editor) ?? d.editor
        d.codeTheme = try c.decodeIfPresent(String.self, forKey: .codeTheme) ?? d.codeTheme
        d.mapModel = try c.decodeIfPresent(String.self, forKey: .mapModel) ?? d.mapModel
        self = d
    }

}
