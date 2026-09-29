import SwiftUI

enum Rarity: String, Codable, Sendable, CaseIterable, Comparable {
    case common, uncommon, rare, epic, legendary

    var title: String { rawValue.capitalized }

    var weight: Double {
        switch self {
        case .common:    55
        case .uncommon:  25
        case .rare:      12
        case .epic:      6
        case .legendary: 2
        }
    }

    var color: Color {
        switch self {
        case .common:    Color(red: 0.72, green: 0.74, blue: 0.78)
        case .uncommon:  Color(red: 0.36, green: 0.82, blue: 0.55)
        case .rare:      Color(red: 0.35, green: 0.65, blue: 1.0)
        case .epic:      Color(red: 0.71, green: 0.49, blue: 1.0)
        case .legendary: Color(red: 1.0, green: 0.71, blue: 0.28)
        }
    }

    var shimmers: Bool { self >= .rare }
    var shines: Bool { self >= .epic }
    var sparks: Bool { self == .legendary }

    static func < (a: Rarity, b: Rarity) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

struct Artifact: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let flavor: String
    let rarity: Rarity
    let pixels: [String]
    let palette: [Character: UInt32]

    static func == (a: Artifact, b: Artifact) -> Bool { a.id == b.id }

    static func named(_ id: String) -> Artifact? { catalog.first { $0.id == id } }

    static func pick(_ rarity: Rarity, dice: () -> Double = { .random(in: 0..<1) }) -> Artifact {
        let pool = catalog.filter { $0.rarity == rarity }
        return pool[min(pool.count - 1, Int(dice() * Double(pool.count)))]
    }

    static func sample(_ rarity: Rarity) -> Artifact {
        catalog.last { $0.rarity == rarity } ?? catalog[0]
    }

    static let catalog: [Artifact] = [
        Artifact(
            id: "rubber-duck", name: "Rubber Duck",
            flavor: "You explained the bug out loud and found it halfway through.",
            rarity: .common,
            pixels: [
                "................",
                "................",
                ".....YYYY.......",
                "....YYYYYY......",
                "....YYKYYYOO....",
                "....YYYYYYOOO...",
                ".....YYYYY......",
                "..YY..YYYY......",
                ".YYYYYYYYYYY....",
                "YYWYYYYYYYYYY...",
                "YYWWYYYYYYYYY...",
                "YYYYYYYYYYYYY...",
                ".YYYYYYYYYYY....",
                "..YYYYYYYYY.....",
                "....YYYYY.......",
                "................",
            ],
            palette: ["Y": 0xFFD84A, "O": 0xFF8A2A, "K": 0x1A1A1A, "W": 0xFFF6C8]
        ),
        Artifact(
            id: "three-am-coffee", name: "3 a.m. Coffee",
            flavor: "Cold since the deploy. Still yours.",
            rarity: .common,
            pixels: [
                "................",
                "....S...S.......",
                ".....S...S......",
                "....S...S.......",
                "................",
                "..GGGGGGGGG.....",
                "..GBBBBBBBG.....",
                "..GGGGGGGGGGG...",
                "..GGGGGGGGG.GG..",
                "..GGGGGGGGG..G..",
                "..GGGGGGGGG.GG..",
                "..GGGGGGGGGGG...",
                "..GGGGGGGGG.....",
                "...GGGGGGG......",
                "....GGGGG.......",
                "................",
            ],
            palette: ["S": 0xC9D1DC, "G": 0xE9EDF2, "B": 0x6B3F22]
        ),
        Artifact(
            id: "lgtm-stamp", name: "LGTM Stamp",
            flavor: "Handle with care. It has ended careers.",
            rarity: .common,
            pixels: [
                "......HHHH......",
                "......HHHH......",
                ".......HH.......",
                ".......HH.......",
                "....RRRRRRRR....",
                "...RRRRRRRRRR...",
                "...RRRRRRRRRR...",
                "................",
                "............R...",
                "...........RR...",
                "..R.......RR....",
                "..RR.....RR.....",
                "...RR...RR......",
                "....RR.RR.......",
                ".....RRR........",
                "......R.........",
            ],
            palette: ["H": 0x8A5A34, "R": 0xE5484D]
        ),
        Artifact(
            id: "floppy", name: "1.44 MB Floppy",
            flavor: "The whole codebase fit on one of these, once.",
            rarity: .uncommon,
            pixels: [
                "................",
                ".FFFFFFFFFFFFF..",
                ".FFMMMMMMMMFFFF.",
                ".FFMMMMM.MMFFFF.",
                ".FFMMMMM.MMFFFF.",
                ".FFMMMMMMMMFFFF.",
                ".FFFFFFFFFFFFFF.",
                ".FFFFFFFFFFFFFF.",
                ".FFLLLLLLLLLLFF.",
                ".FFLLLLLLLLLLFF.",
                ".FFLKKKKKKKKLFF.",
                ".FFLLLLLLLLLLFF.",
                ".FFLKKKKKKLLLFF.",
                ".FFLLLLLLLLLLFF.",
                ".FFFFFFFFFFFFFF.",
                "................",
            ],
            palette: ["F": 0x2F5FD0, "M": 0xB9C2CF, "L": 0xF4F4F0, "K": 0x8C94A3]
        ),
        Artifact(
            id: "map-out-of-vim", name: "Map Out of Vim",
            flavor: "The exit is marked in red. Few have used it.",
            rarity: .rare,
            pixels: [
                "................",
                "..PPPPPPPPPPPP..",
                ".PPPPPPPPPPPPPP.",
                ".PPRRPPPPPPPPPP.",
                ".PPPRPPPPPPPPPP.",
                ".PPPPRRPPPPPPPP.",
                ".PPPPPPRPPPPPPP.",
                ".PPPPPPPRRPPPPP.",
                ".PPPPPPPPPRPPPP.",
                ".PPPPPPPPPPRPPP.",
                ".PPPPPPPPPRRPPP.",
                ".PPPPPPPPXPPXPP.",
                ".PPPPPPPPPXXPPP.",
                ".PPPPPPPPXPPXPP.",
                "..PPPPPPPPPPPP..",
                "................",
            ],
            palette: ["P": 0xE8D3A2, "R": 0xD2453C, "X": 0x7A1E1A]
        ),
        Artifact(
            id: "rm-rf-amulet", name: "Amulet of rm -rf",
            flavor: "Grants the power to end everything. Never used. Never.",
            rarity: .epic,
            pixels: [
                "................",
                "...G........G...",
                "....G......G....",
                ".....G....G.....",
                "......G..G......",
                ".......GG.......",
                "......GGGG......",
                ".....GVVVVG.....",
                "....GVVWVVVG....",
                "....GVWVVVVG....",
                "....GVVVVVVG....",
                "....GVVVVVVG....",
                ".....GVVVVG.....",
                "......GVVG......",
                ".......GG.......",
                "................",
            ],
            palette: ["G": 0xE7B84A, "V": 0x8B4DFF, "W": 0xE9D9FF]
        ),
        Artifact(
            id: "lost-10x-keyboard", name: "Lost Keyboard of the 10x Engineer",
            flavor: "Nobody has ever met its owner. Everybody knows someone who has.",
            rarity: .legendary,
            pixels: [
                "................",
                "................",
                "................",
                "DDDDDDDDDDDDDDDD",
                "DCCDCCDCCDCCDCCD",
                "DDDDDDDDDDDDDDDD",
                "DCCDCCDOODCCDCCD",
                "DDDDDDDDDDDDDDDD",
                "DCCCDCCDCCDCCCCD",
                "DDDDDDDDDDDDDDDD",
                "DCCDCCCCCCCCDCCD",
                "DDDDDDDDDDDDDDDD",
                "................",
                "................",
                "................",
                "................",
            ],
            palette: ["D": 0x2A2D34, "C": 0xD9DEE6, "O": 0xFFB547]
        ),
    ]
}

enum ReviewVerdict: String, Codable, Sendable, CaseIterable {
    case commented, approved, changesRequested

    init(github state: String?) {
        switch state {
        case "APPROVED":          self = .approved
        case "CHANGES_REQUESTED": self = .changesRequested
        default:                  self = .commented
        }
    }

    var word: String {
        switch self {
        case .commented:        "commented"
        case .approved:         "approved"
        case .changesRequested: "changes requested"
        }
    }

    var short: String { self == .changesRequested ? "changes" : word }

    var color: Color {
        switch self {
        case .commented:        Color(red: 0.93, green: 0.94, blue: 0.96)
        case .approved:         Color(red: 0.36, green: 0.84, blue: 0.52)
        case .changesRequested: Color(red: 1.0, green: 0.62, blue: 0.3)
        }
    }
}

struct Reward: Identifiable, Sendable, Equatable {
    let id: String
    let artifact: Artifact
    let pr: String?
    var verdict = ReviewVerdict.commented
}

struct EarnedArtifact: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let artifact: String
    let pr: String?
    let verdict: ReviewVerdict
    let at: Date
    var claimedAt: Date?
}

struct RewardsProfile: Codable, Sendable, Equatable {
    enum Role: String, Codable, Sendable, CaseIterable, Identifiable {
        case developer, lead, manager, other
        var id: String { rawValue }
        var title: String {
            switch self {
            case .developer: "I write code most of the day"
            case .lead:      "I lead a team and still review a lot"
            case .manager:   "I manage people, and review when I can"
            case .other:     "Something else"
            }
        }
    }

    enum Reason: String, Codable, Sendable, CaseIterable, Identifiable {
        case unblock, learn, grow, goal
        var id: String { rawValue }
        var title: String {
            switch self {
            case .unblock: "My teammates wait on my reviews"
            case .learn:   "I want to know the codebase better"
            case .grow:    "Reviewing well is part of growing"
            case .goal:    "I have a review target to hit"
            }
        }
    }

    var role: Role = .developer
    var reason: Reason = .unblock
}
