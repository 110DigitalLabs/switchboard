import Testing
@testable import Switchboard

struct StatusLineTextTests {
    @Test func stripsColorsHyperlinksAndControls() {
        let raw = "\u{1B}[1;36mOpus\u{1B}[0m · \u{1B}]8;;https://x.dev\u{07}link\u{1B}]8;;\u{1B}\\ \u{1B}(B42%\r"
        #expect(StatusLineText.stripANSI(raw) == "Opus · link 42%")
    }

    @Test func joinsLinesIntoOne() {
        let raw = "\u{1B}[32mmain\u{1B}[0m  \n\n  ctx 12%\n"
        #expect(StatusLineText.singleLine(raw) == "main  ctx 12%")
    }

    @Test func emptyStaysEmpty() {
        #expect(StatusLineText.singleLine("\u{1B}[0m\n") == "")
    }
}
