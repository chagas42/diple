import SwiftUI

struct CodeTheme: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let dark: Bool

    let plain: Color
    let keyword: Color
    let type: Color
    let string: Color
    let number: Color
    let comment: Color
    let function: Color
    let punctuation: Color

    let surface: Color
    let gutter: Color
    let addedTint: Color
    let removedTint: Color
    let addedMark: Color
    let removedMark: Color

    static let all: [CodeTheme] = [dipleDark, dipleLight, oxocarbonDark, nord, gruvbox, rosePine, solarized]

    static func named(_ id: String?) -> CodeTheme {
        all.first { $0.id == id } ?? dipleDark
    }

    private static func hex(_ v: UInt32, _ a: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((v >> 16) & 0xFF) / 255,
              green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255,
              opacity: a)
    }

    static let dipleDark = CodeTheme(
        id: "diple-dark", name: "Diple Dark", dark: true,
        plain: hex(0xD6D8DC), keyword: hex(0xE0857B), type: hex(0x7FC8E8),
        string: hex(0x9BCB8A), number: hex(0xE0B876), comment: hex(0x6B7280),
        function: hex(0xC3A0E8), punctuation: hex(0x9AA0A8),
        surface: hex(0x14161A), gutter: hex(0x5A616B),
        addedTint: hex(0x2EA043, 0.13), removedTint: hex(0xF85149, 0.13),
        addedMark: hex(0x3FB950), removedMark: hex(0xF85149)
    )

    static let dipleLight = CodeTheme(
        id: "diple-light", name: "Diple Light", dark: false,
        plain: hex(0x1F2328), keyword: hex(0xA6303C), type: hex(0x0A5A8C),
        string: hex(0x2C6E3E), number: hex(0x8A5A00), comment: hex(0x6E7781),
        function: hex(0x6639BA), punctuation: hex(0x57606A),
        surface: hex(0xF6F8FA), gutter: hex(0x8C959F),
        addedTint: hex(0x2EA043, 0.11), removedTint: hex(0xCF222E, 0.10),
        addedMark: hex(0x1A7F37), removedMark: hex(0xCF222E)
    )

    static let oxocarbonDark = CodeTheme(
        id: "oxocarbon-dark", name: "Oxocarbon Dark", dark: true,
        plain: hex(0xD5D5D5), keyword: hex(0x78A9FF), type: hex(0x78A9FF),
        string: hex(0xBE95FF), number: hex(0x82CFFF), comment: hex(0x5C5C5C),
        function: hex(0x3DDBD9), punctuation: hex(0x3DDBD9),
        surface: hex(0x161616), gutter: hex(0x5C5C5C),
        addedTint: hex(0x122F2F), removedTint: hex(0x361C28),
        addedMark: hex(0x42BE65), removedMark: hex(0xEE5396)
    )

    static let nord = CodeTheme(
        id: "nord", name: "Nord", dark: true,
        plain: hex(0xD8DEE9), keyword: hex(0x81A1C1), type: hex(0x8FBCBB),
        string: hex(0xA3BE8C), number: hex(0xB48EAD), comment: hex(0x616E88),
        function: hex(0x88C0D0), punctuation: hex(0x9BA5B5),
        surface: hex(0x2E3440), gutter: hex(0x667084),
        addedTint: hex(0xA3BE8C, 0.14), removedTint: hex(0xBF616A, 0.14),
        addedMark: hex(0xA3BE8C), removedMark: hex(0xBF616A)
    )

    static let gruvbox = CodeTheme(
        id: "gruvbox", name: "Gruvbox", dark: true,
        plain: hex(0xEBDBB2), keyword: hex(0xFB4934), type: hex(0xFABD2F),
        string: hex(0xB8BB26), number: hex(0xD3869B), comment: hex(0x928374),
        function: hex(0x8EC07C), punctuation: hex(0xBDAE93),
        surface: hex(0x282828), gutter: hex(0x7C6F64),
        addedTint: hex(0xB8BB26, 0.14), removedTint: hex(0xFB4934, 0.13),
        addedMark: hex(0xB8BB26), removedMark: hex(0xFB4934)
    )

    static let rosePine = CodeTheme(
        id: "rose-pine", name: "Rosé Pine", dark: true,
        plain: hex(0xE0DEF4), keyword: hex(0x31748F), type: hex(0x9CCFD8),
        string: hex(0xF6C177), number: hex(0xEBBCBA), comment: hex(0x6E6A86),
        function: hex(0xC4A7E7), punctuation: hex(0x908CAA),
        surface: hex(0x191724), gutter: hex(0x6E6A86),
        addedTint: hex(0x9CCFD8, 0.12), removedTint: hex(0xEB6F92, 0.12),
        addedMark: hex(0x9CCFD8), removedMark: hex(0xEB6F92)
    )

    static let solarized = CodeTheme(
        id: "solarized", name: "Solarized", dark: false,
        plain: hex(0x586E75), keyword: hex(0x859900), type: hex(0xB58900),
        string: hex(0x2AA198), number: hex(0xD33682), comment: hex(0x93A1A1),
        function: hex(0x268BD2), punctuation: hex(0x839496),
        surface: hex(0xFDF6E3), gutter: hex(0x93A1A1),
        addedTint: hex(0x859900, 0.13), removedTint: hex(0xDC322F, 0.11),
        addedMark: hex(0x859900), removedMark: hex(0xDC322F)
    )
}

private struct CodeThemeKey: EnvironmentKey {
    static let defaultValue = CodeTheme.dipleDark
}

extension EnvironmentValues {
    var codeTheme: CodeTheme {
        get { self[CodeThemeKey.self] }
        set { self[CodeThemeKey.self] = newValue }
    }
}
