import SwiftUI
import Testing
@testable import Switchboard

struct ANSITextTests {
    private let palette = TerminalPalette(theme: .system)

    /// (text, color) per run.
    private func runs(_ text: String) -> [(String, Color?)] {
        let attributed = ANSIText.attributed(text, palette: palette)
        return attributed.runs.map { (String(attributed[$0.range].characters), $0.foregroundColor) }
    }

    @Test func colorsTheStatusLineFromThePalette() {
        // The shape of a typical status line script's output.
        let line = "\u{1B}[36mOpus 5.5\u{1B}[0m\u{1B}[90m · \u{1B}[0m\u{1B}[32m164K ctx\u{1B}[0m"
        let found = runs(line)
        #expect(found.map(\.0) == ["Opus 5.5", " · ", "164K ctx"])
        #expect(found.map(\.1) == [palette.cyan, palette.dim, palette.green])
    }

    @Test func resetAndDefaultColorLeaveTextUncolored() {
        let found = runs("\u{1B}[31mred\u{1B}[39m plain \u{1B}[33my\u{1B}[m end")
        #expect(found.map(\.0) == ["red", " plain ", "y", " end"])
        #expect(found.map(\.1) == [palette.red, nil, palette.yellow, nil])
    }

    @Test func readsExtendedColors() {
        let red = Color(.sRGB, red: 1, green: 0, blue: 0)
        let found = runs("\u{1B}[38;5;2mg\u{1B}[38;2;255;0;0mr\u{1B}[48;5;4mstill r")
        // A background color changes nothing, so the red text stays one run.
        #expect(found.map(\.0) == ["g", "rstill r"])
        #expect(found.map(\.1) == [palette.green, red])
    }

    @Test func dropsOtherEscapesButKeepsLinkText() {
        let link = "\u{1B}]8;;https://example.com\u{07}PR #12\u{1B}]8;;\u{07}"
        #expect(ANSIText.strip("\u{1B}[2K\u{1B}[1G\(link) done") == "PR #12 done")
    }

    @Test func firstLineSkipsBlankLines() {
        let output = "\u{1B}[0m\n\u{1B}[32mrepo/main\u{1B}[0m\nsecond"
        let line = ANSIText.firstLine(of: output, palette: palette)
        #expect(line.map { String($0.characters) } == "repo/main")
        #expect(ANSIText.firstLine(of: "\n  \n", palette: palette) == nil)
    }
}
