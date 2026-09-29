import Foundation

struct StickerSheet: Identifiable, Sendable {
    let id: String
    let title: String
    let stickers: [Artifact]

    static let classics = StickerSheet(id: "classics", title: "Classics", stickers: Artifact.catalog)

    static let aiSeason = StickerSheet(id: "ai-season", title: "AI Season", stickers: [
        Artifact(
            id: "strawberry", name: "Strawberry",
            flavor: "How many r's? The model is still counting.",
            rarity: .common,
            pixels: [
                "................",
                "......G..G......",
                ".....GGGGGG.....",
                "......GGGG......",
                "....RRRRRRRR....",
                "...RRYRRRRYRR...",
                "...RRRRRYRRRR...",
                "...RYRRRRRRYR...",
                "....RRRYRRRR....",
                "....RRRRRRYR....",
                ".....RYRRRR.....",
                ".....RRRRRR.....",
                "......RRYR......",
                ".......RR.......",
                "................",
                "................",
            ],
            palette: ["G": 0x3FA34D, "R": 0xE5484D, "Y": 0xFFE58A]
        ),
        Artifact(
            id: "absolutely-right", name: "\u{201C}You're absolutely right!\u{201D}",
            flavor: "Every assistant's favourite line, right before it changes its mind.",
            rarity: .common,
            pixels: [
                "................",
                "..KKKKKKKKKKKK..",
                ".KWWWWWWWWWWWWK.",
                ".KWWWWBWWBWWWWK.",
                ".KWWWWBWWBWWWWK.",
                ".KWWWWBWWBWWWWK.",
                ".KWWWWBWWBWWWWK.",
                ".KWWWWWWWWWWWWK.",
                ".KWWWWBWWBWWWWK.",
                ".KWWWWWWWWWWWWK.",
                "..KKKKWWKKKKKK..",
                "......KWK.......",
                ".......KK.......",
                "................",
                "................",
                "................",
            ],
            palette: ["K": 0x2A2D34, "W": 0xF4F4F0, "B": 0xD97757]
        ),
        Artifact(
            id: "context-window-full", name: "Context Window Full",
            flavor: "It forgot the first half of the PR. So did you.",
            rarity: .uncommon,
            pixels: [
                "................",
                ".KKKKKKKKKKKKKK.",
                ".KRKYKGKDDDDDDK.",
                ".KKKKKKKKKKKKKK.",
                ".KLLLLLLLLLLLSK.",
                ".KDDDDDDDDDDDSK.",
                ".KLLLLLLLLLDDSK.",
                ".KDDDDDDDDDDDSK.",
                ".KLLLLLLLLLLLSK.",
                ".KDDDDDDDDDDDSK.",
                ".KLLLLLLLLDDDSK.",
                ".KKKKKKKKKKKKKK.",
                "..LLLLLLLLLLL...",
                "...LLLLLLLL.....",
                "....LLLLL.......",
                "................",
            ],
            palette: ["K": 0x3A3F4B, "D": 0x1E2230, "L": 0x9AA3B5, "S": 0xE5484D,
                      "R": 0xFF5F57, "Y": 0xFEBC2E, "G": 0x28C840]
        ),
        Artifact(
            id: "vibe-coded", name: "Vibe-Coded to Prod",
            flavor: "Nobody read it. It works. Nobody knows why.",
            rarity: .rare,
            pixels: [
                "................",
                ".....KKKKKK.....",
                "....K......K....",
                "...K........K...",
                "..K..........K..",
                "..K..........K..",
                ".PPP........PPP.",
                ".PPPP......PPPP.",
                ".PPPP..N...PPPP.",
                ".PPPP..NN..PPPP.",
                ".PPPP..N.N.PPPP.",
                ".PPP..NN...PPP..",
                "......NN........",
                "................",
                "................",
                "................",
            ],
            palette: ["K": 0x4A4F5C, "P": 0xB67CFF, "N": 0xFFD34D]
        ),
        Artifact(
            id: "agi-next-year", name: "AGI Next Year",
            flavor: "The slide says 2027. Last year it said 2026.",
            rarity: .epic,
            pixels: [
                "................",
                ".FFFFFFFFFFFFFF.",
                ".FWWWWWWWWWWWWF.",
                ".FWBBBWBBBWBWWF.",
                ".FWBWBWBWWWBWWF.",
                ".FWBBBWBWBWBWWF.",
                ".FWBWBWBBBWBWWF.",
                ".FWWWWWWWWWWWWF.",
                ".FWRRRRRRRRWWWF.",
                ".FWWGGGGGGWWWWF.",
                ".FFFFFFFFFFFFFF.",
                "..KK...FF.......",
                "..KK...FF.......",
                "......FFFF......",
                ".KKKK...........",
                "KKKKKK..........",
            ],
            palette: ["F": 0x3A3F4B, "W": 0xF4F4F0, "B": 0x2A2D34, "R": 0xE5484D, "G": 0x3FB950, "K": 0x111316]
        ),
        Artifact(
            id: "last-human-reviewer", name: "The Last Human Reviewer",
            flavor: "Still reading the diff yourself. Respect.",
            rarity: .legendary,
            pixels: [
                "................",
                "....KKKKK.......",
                "...KWWWWWK......",
                "..KWGGGWWWK.....",
                "..KWWWWWWWK.....",
                "..KWRRRWWWK.....",
                "..KWWWWWWWK.....",
                "..KWGGGGWWK.....",
                "...KWWWWWK......",
                "....KKKKKHH.....",
                ".........HHH....",
                "..........HHH...",
                "...........HHH..",
                "............HH..",
                "................",
                "................",
            ],
            palette: ["K": 0xE7B84A, "W": 0xDCEBFF, "G": 0x3FB950, "R": 0xF85149, "H": 0x8A5A34]
        ),
    ])

    static let devFolklore = StickerSheet(id: "dev-folklore", title: "Dev Folklore", stickers: [
        Artifact(
            id: "it-was-dns", name: "It Was DNS",
            flavor: "It's not DNS. There's no way it's DNS. It was DNS.",
            rarity: .common,
            pixels: [
                "................",
                ".....BBBBBB.....",
                "...BBGGBBBBBB...",
                "..BBGGGGBBBBBB..",
                "..BGGGGBBBGGBB..",
                ".BBBGGBBBBGGGBB.",
                ".BBBBBBBBBGGGBB.",
                ".BBBBBBBBBBGBBB.",
                ".BBGGBBBBBBBBBB.",
                "..BGGGBBBBBRRB..",
                "..BBGGBBBBRWWR..",
                "...BBBBBBRWRRWR.",
                ".....BBBBRWWWWR.",
                ".........RRRRRR.",
                "................",
                "................",
            ],
            palette: ["B": 0x3B82F6, "G": 0x34C47A, "R": 0xE5484D, "W": 0xFFFFFF]
        ),
        Artifact(
            id: "nit", name: "Nit:",
            flavor: "The most feared prefix in review. Nit: everything.",
            rarity: .common,
            pixels: [
                "................",
                "..YYYYYYYYYYYY..",
                "..YYYYYYYYYYYY..",
                "..YLLLYLYLLLYY..",
                "..YYYYYYYYYYYY..",
                "..YLLLLLLLLLYY..",
                "..YYYYYYYYYYYY..",
                "..YLLLLLLLYYYY..",
                "..YYYYYYYYYYYY..",
                "..YLLLLLRRYYYY..",
                "..YYYYYYRRYYYY..",
                "..YYYYYYYYYYY...",
                "..YYYYYYYYYY....",
                "................",
                "................",
                "................",
            ],
            palette: ["Y": 0xFFE066, "L": 0x9C8B3E, "R": 0xE5484D]
        ),
        Artifact(
            id: "temporary-fix", name: "Temporary Fix (2019)",
            flavor: "Temporary since 2019. Still holding.",
            rarity: .uncommon,
            pixels: [
                "................",
                ".....SSSSSS.....",
                "...SSSSSSSSSS...",
                "..SSSSCCCCSSSS..",
                "..SSSC....CSSS..",
                ".SSSC......CSSS.",
                ".SSSC......CSSS.",
                ".SSSC......CSSS.",
                ".SSSC......CSSS.",
                "..SSSC....CSSS..",
                "..SSSSCCCCSSSSTT",
                "...SSSSSSSSSSTTT",
                ".....SSSSSS.TTT.",
                "................",
                "................",
                "................",
            ],
            palette: ["S": 0xB9C0CA, "C": 0xC8A36A, "T": 0x9AA1AC]
        ),
        Artifact(
            id: "heisenbug", name: "Heisenbug",
            flavor: "Stops happening the moment you look.",
            rarity: .rare,
            pixels: [
                "................",
                "....K......K....",
                ".....K....K.....",
                "......GGGG......",
                ".....GGGGGG.....",
                "..K.GGWGGWGG.K..",
                "...KGGGGGGGGK...",
                "....GG.GG.GG....",
                "..K.G.GG.GG.GK..",
                "...KGG.GG.GGK...",
                "....G.GG.GG.G...",
                "..K..GG.GG.G.K..",
                "......G.GG......",
                "................",
                "................",
                "................",
            ],
            palette: ["G": 0x3FB950, "K": 0x6B7280, "W": 0xFFFFFF]
        ),
        Artifact(
            id: "bus-factor-one", name: "Bus Factor: 1",
            flavor: "Only one person knows how it works. They're on vacation.",
            rarity: .epic,
            pixels: [
                "................",
                "................",
                "..YYYYYYYYYYYY..",
                ".YYWWYWWYWWYWWY.",
                ".YYWWYWWYWWYWWY.",
                ".YYYYYYYYYYYYYY.",
                ".YYYYYYYYKKYYYY.",
                ".YYYYYYYYYKYYYY.",
                ".YYYYYYYYYKYYYY.",
                ".YYYYYYYYKKKYYY.",
                ".DDDDDDDDDDDDDD.",
                "..KK......KK....",
                "..KK......KK....",
                "................",
                "................",
                "................",
            ],
            palette: ["Y": 0xF5C542, "W": 0xBFE3FF, "K": 0x1A1A1A, "D": 0x8A8F99]
        ),
        Artifact(
            id: "load-bearing-todo", name: "Load-Bearing TODO",
            flavor: "Remove it and prod goes down. Nobody knows why.",
            rarity: .legendary,
            pixels: [
                "................",
                "..CCCCCCCCCCCC..",
                "...CCCCCCCCCC...",
                "....SSSSSSSS....",
                "....SCSCSCSC....",
                "....SCSCSCSC....",
                "....SYYYYYYC....",
                "....SYKKKKYC....",
                "....SYYYYYYC....",
                "....SCSCSCSC....",
                "....SCSCSCSC....",
                "....SSSSSSSS....",
                "...CCCCCCCCCC...",
                "..CCCCCCCCCCCC..",
                "................",
                "................",
            ],
            palette: ["C": 0xC9BB98, "S": 0x9C8F6E, "Y": 0xFFD84A, "K": 0x5A4A1A]
        ),
    ])

    static let all = [aiSeason, devFolklore, classics]

    static func of(season: String) -> StickerSheet {
        switch season {
        case "2026-Q3": return aiSeason
        case "2026-Q4": return devFolklore
        default:
            let q = Int(season.split(separator: "Q").last ?? "") ?? 1
            return [aiSeason, devFolklore, classics][q % 3]
        }
    }

    static var everySticker: [Artifact] { all.flatMap(\.stickers) }

    static var current: StickerSheet { of(season: Trail.season(of: Date())) }

    var others: [StickerSheet] { Self.all.filter { $0.id != id } }
}
