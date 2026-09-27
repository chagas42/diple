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
}
