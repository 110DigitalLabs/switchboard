import Testing
@testable import Switchboard

struct VoiceCommandTests {
    @Test func switchboardAndANumberSelects() {
        #expect(VoiceCommand(transcript: "Switchboard 2") == .select(position: 2, then: nil))
        #expect(VoiceCommand(transcript: "switchboard two.") == .select(position: 2, then: nil))
        #expect(VoiceCommand(transcript: "Switch board, 3") == .select(position: 3, then: nil))
        #expect(VoiceCommand(transcript: "Switch-board twelve") == .select(position: 12, then: nil))
    }

    @Test func homophonesCountOnlyAtTheEnd() {
        #expect(VoiceCommand(transcript: "Switchboard to") == .select(position: 2, then: nil))
        #expect(VoiceCommand(transcript: "Switchboard for") == .select(position: 4, then: nil))
        #expect(VoiceCommand(transcript: "Switchboard to run the tests")
            == .dictate("Switchboard to run the tests"))
    }

    @Test func textAfterTheNumberIsTypedIntoTheNewSelection() {
        #expect(VoiceCommand(transcript: "Switchboard 2, run the Tests again")
            == .select(position: 2, then: "run the Tests again"))
        #expect(VoiceCommand(transcript: "switch board three - commit it")
            == .select(position: 3, then: "commit it"))
    }

    @Test func sendPressesReturn() {
        #expect(VoiceCommand(transcript: "Send.") == .submit)
        #expect(VoiceCommand(transcript: "send it") == .submit)
        #expect(VoiceCommand(transcript: "Press enter") == .submit)
    }

    @Test func everythingElseIsDictation() {
        #expect(VoiceCommand(transcript: "  Fix the failing login test ") == .dictate("Fix the failing login test"))
        #expect(VoiceCommand(transcript: "send the PR to review") == .dictate("send the PR to review"))
        #expect(VoiceCommand(transcript: "Switchboard") == .dictate("Switchboard"))
        #expect(VoiceCommand(transcript: "switchboard zero") == .dictate("switchboard zero"))
    }

    @Test func silenceIsNothing() {
        #expect(VoiceCommand(transcript: "") == nil)
        #expect(VoiceCommand(transcript: " . ") == nil)
    }
}
