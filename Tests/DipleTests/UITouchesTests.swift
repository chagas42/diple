import AppKit
import Foundation
import Testing
@testable import Diple

@Suite struct HighlighterTests {
    static func kinds(_ line: String, _ lang: Highlighter.Language) -> [String: Syntax] {
        var out: [String: Syntax] = [:]
        for (text, kind) in Highlighter(language: lang).spans(line) where !text.trimmingCharacters(in: .whitespaces).isEmpty {
            out[text] = kind
        }
        return out
    }

    @Test func swiftLineIsClassifiedAsBefore() {
        let k = Self.kinds("let total = Order.sum(items) // cached", .swift)
        #expect(k["let"] == .keyword)
        #expect(k["Order"] == .type)
        #expect(k["sum"] == .function)
        #expect(k["// cached"] == .comment)
    }

    @Test func typescriptStringsAndNumbers() {
        let k = Self.kinds("const retries = 3; log(\"a // b\")", .typescript)
        #expect(k["const"] == .keyword)
        #expect(k["3"] == .number)
        #expect(k["\"a // b\""] == .string)
        #expect(k["log"] == .function)
    }

    @Test func everyLanguageHasItsKeywords() {
        #expect(Highlighter.Language.python.keywords.contains("def"))
        #expect(Highlighter.Language.go.keywords.contains("func"))
        #expect(Highlighter.Language.sql.keywords.contains("select"))
        #expect(Highlighter.Language.none.keywords.isEmpty)
    }
}

@MainActor
@Suite struct DiffHunkParsingTests {
    @Test func rowsAreNumberedAndStable() {
        let hunk = "@@ -1,3 +10,4 @@\n const a = 1\n-const b = 2\n+const b = 3"
        let first = DiffHunkView.parse(hunk, highlighter: Highlighter(language: .typescript))
        let second = DiffHunkView.parse(hunk, highlighter: Highlighter(language: .typescript))
        #expect(first.map(\.id) == [0, 1, 2, 3])
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.map(\.number) == [nil, 10, nil, 11])
        #expect(first.map(\.mark) == ["@", " ", "-", "+"])
        #expect(first[3].spans.contains { $0.0 == "const" && $0.1 == .keyword })
    }
}

@MainActor
@Suite struct AvatarCacheTests {
    static func png() -> Data {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }

    @Test func anAvatarIsDownloadedOnceNoMatterHowOftenItIsDrawn() async {
        let data = Self.png()
        let cache = AvatarCache { _ in
            try? await Task.sleep(for: .milliseconds(30))
            return data
        }
        let url = URL(string: "https://example.invalid/a.png")!
        let first = Task { @MainActor in await cache.image(for: url) != nil }
        let second = Task { @MainActor in await cache.image(for: url) != nil }
        let x = await first.value
        let y = await second.value
        #expect(x && y)
        let value1 = await cache.image(for: url)
        #expect(value1 != nil)
        #expect(cache.cached(url) != nil)
        #expect(cache.loads == 1)
    }

    @Test func aFailedDownloadIsNotCached() async {
        let cache = AvatarCache { _ in nil }
        let url = URL(string: "https://example.invalid/b.png")!
        let value2 = await cache.image(for: url)
        #expect(value2 == nil)
        let value3 = await cache.image(for: url)
        #expect(value3 == nil)
        #expect(cache.loads == 2)
    }
}
