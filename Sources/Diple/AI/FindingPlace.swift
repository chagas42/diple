import Foundation

enum FindingPlace: Equatable {
    case line(path: String, line: Int)
    case file(path: String)
    case conversation

    static func choose(path: String, line: Int?, inline: Bool?, changed: [String]) -> FindingPlace {
        guard inline != false, let resolved = resolve(path, in: changed) else { return .conversation }
        return line.map { .line(path: resolved, line: $0) } ?? .file(path: resolved)
    }

    static func resolve(_ path: String, in changed: [String]) -> String? {
        let p = path.hasPrefix("./") ? String(path.dropFirst(2)) : path
        guard !p.isEmpty else { return nil }
        if changed.isEmpty || changed.contains(p) { return p }
        let hits = changed.filter { $0.hasSuffix("/" + p) }
        return hits.count == 1 ? hits[0] : nil
    }
}
