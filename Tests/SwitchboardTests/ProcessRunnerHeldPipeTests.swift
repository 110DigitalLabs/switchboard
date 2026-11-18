import Foundation
import Testing
@testable import Switchboard

struct ProcessRunnerHeldPipeTests {
    @Test func strayDescendantHoldingStdoutDoesNotHang() async throws {
        let start = Date()
        await #expect(throws: ProcessRunner.Failure.outputHeldOpen) {
            _ = try await ProcessRunner.run("/bin/sh", ["-c", "sleep 30 & echo done"], timeout: .seconds(10))
        }
        #expect(Date().timeIntervalSince(start) < 8)
    }

    @Test func normalCommandStillReturnsOutput() async throws {
        let output = try await ProcessRunner.run("/bin/sh", ["-c", "echo hi"], timeout: .seconds(10))
        #expect(String(decoding: output.stdout, as: UTF8.self) == "hi\n")
    }
}
