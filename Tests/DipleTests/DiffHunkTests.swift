import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct DiffHunkTests {
    func rows(_ lines: Int) -> [DiffHunkView.Row] {
        let hunk = (["@@ -0,0 +1,\(lines) @@"] + (1...lines).map { "+let line\($0) = \($0)" }).joined(separator: "\n")
        return DiffHunkView.parse(hunk, highlighter: Highlighter(language: .of(path: "a.swift")))
    }

    @Test func aOneLineCommentShowsItsLineAndThreeAbove() {
        let shown = DiffHunkView.visible(rows(300), expanded: false, line: 300)
        #expect(shown.rows.compactMap(\.number) == [297, 298, 299, 300])
        #expect(shown.hidden == 296)
    }

    @Test func aMultiLineCommentShowsExactlyItsRange() {
        let shown = DiffHunkView.visible(rows(300), expanded: false, line: 290, startLine: 280)
        #expect(shown.rows.compactMap(\.number) == Array(280...290))
    }

    @Test func withoutALineItShowsTheLastFour() {
        let shown = DiffHunkView.visible(rows(50), expanded: false)
        #expect(shown.rows.compactMap(\.number) == [47, 48, 49, 50])
    }

    @Test func expandingShowsEverything() {
        let all = rows(300)
        let shown = DiffHunkView.visible(all, expanded: true, line: 300)
        #expect(shown.hidden == 0)
        #expect(shown.rows.count == all.count)
    }

    @Test func aShortHunkIsShownWhole() {
        let all = rows(4)
        let shown = DiffHunkView.visible(all, expanded: false, line: 4)
        #expect(shown.hidden == 0)
        #expect(shown.rows.count == all.count)
    }

    @Test func aHunkIsParsedOnceHoweverOftenItIsDrawn() {
        let h = "@@ -0,0 +1,2 @@\n+let a = 1\n+let unique = \(Int.random(in: 0...Int.max))"
        let before = HunkCache.parses
        for _ in 0..<50 { _ = HunkCache.rows(for: h, path: "a.swift") }
        #expect(HunkCache.parses == before + 1)
    }

    @Test func aThreadFromBeforeStartLineStillDecodes() throws {
        let old = #"{"id":"T","path":"a.swift","line":3,"diffHunk":"@@","outdated":false,"comments":[]}"#
        let t = try JSONDecoder().decode(PR.ReviewThread.self, from: Data(old.utf8))
        #expect(t.startLine == nil)
        #expect(t.line == 3)
    }
}
