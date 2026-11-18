import Foundation
import Testing
@testable import Switchboard

struct TypedTextTests {
    @Test func lineBreaksCannotSubmit() {
        let text = TypedText.sanitize("x\r rm -rf ~\nls")
        #expect(text == "x rm -rf ~ ls")
        #expect(!text.contains("\r") && !text.contains("\n"))
    }

    @Test func bracketedPasteEndIsRemoved() {
        #expect(TypedText.sanitize("title\u{1B}[201~\rwhoami") == "title whoami")
    }

    @Test func eightBitCSIAndC1ControlsAreRemoved() {
        let text = TypedText.sanitize("a\u{9B}31mred\u{9B}0m b\u{85}c\u{9C}")
        #expect(text == "ared bc")
        #expect(!text.unicodeScalars.contains { $0.value >= 0x80 && $0.value <= 0x9F })
    }

    @Test func formatCharactersAreRemoved() {
        #expect(TypedText.sanitize("abc\u{202E}fed\u{200B}\u{2066}x") == "abcfedx")
    }

    @Test func oscAndBareEscapesAreRemoved() {
        #expect(TypedText.sanitize("a\u{1B}]0;title\u{07}b\u{1B}c\u{1B}") == "ab")
        #expect(TypedText.sanitize("a\u{1B}]8;;https://x\u{1B}\\link") == "alink")
    }

    @Test func whitespaceCollapsesKeepingOneTrailingSpace() {
        #expect(TypedText.sanitize("  Review \t https://github.com/a/b/pull/1   ") == "Review https://github.com/a/b/pull/1 ")
        #expect(TypedText.sanitize("Ünïcödé ✓ 日本") == "Ünïcödé ✓ 日本")
    }

    @Test func ticketTitlesInPromptsAreSanitized() {
        let prompt = TicketPrompts.work(ticketID: "ENG-1", title: "x\r rm -rf ~\u{1B}[201~")
        #expect(prompt == "Let's work on ENG-1 (x rm -rf ~). ")
    }

    @Test func draftsNeedAForegroundJobOtherThanTheShell() {
        #expect(ForegroundProcess.isOtherThanShell(foregroundGroup: 200, shellPID: 100))
        #expect(!ForegroundProcess.isOtherThanShell(foregroundGroup: 100, shellPID: 100))
        #expect(!ForegroundProcess.isOtherThanShell(foregroundGroup: -1, shellPID: 100))
        #expect(!ForegroundProcess.isOtherThanShell(foregroundGroup: 200, shellPID: 0))
    }
}
