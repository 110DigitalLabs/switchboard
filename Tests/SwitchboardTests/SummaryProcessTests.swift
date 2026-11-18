import Foundation
import Testing
@testable import Switchboard

struct SummaryProcessTests {
    @Test func startupNoiseBeforeMarkerIsDropped() {
        let output = "welcome banner\n\n\(SummaryProcess.marker)\nThe summary.\n"
        #expect(SummaryProcess.afterMarker(output) == "The summary.")
    }

    @Test func runsInDirectoryThroughLoginShell() async throws {
        let text = try await SummaryProcess.run(line: "exec /bin/pwd", directory: "/private/tmp")
        #expect(text == "/private/tmp")
    }

    @Test func timesOut() async {
        await #expect(throws: SummaryProcess.Failure.self) {
            try await SummaryProcess.run(line: "exec /bin/sleep 20", directory: "/tmp", timeout: .seconds(1))
        }
    }
}
