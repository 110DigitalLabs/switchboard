import Foundation

/// Runs an agent's headless summary command in the background.
enum SummaryProcess {
    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    /// Printed before the command so anything the user's shell startup
    /// files print can be cut off the output.
    static let marker = "--switchboard-summary--"

    /// Runs `line` in an interactive login shell, so the user's PATH from
    /// both .zprofile and .zshrc applies, in `directory`; returns the
    /// trimmed stdout after the marker. Kills it after `timeout`.
    static func run(line: String, directory: String, timeout: Duration = .seconds(180)) async throws -> String {
        let shell = ShellEnvironment.loginShell(from: ProcessInfo.processInfo.environment)
        return try await Task.detached(priority: .userInitiated) {
            try runBlocking(shell: shell, line: line, directory: directory, timeout: timeout)
        }.value
    }

    private static func runBlocking(shell: String, line: String, directory: String,
                                    timeout: Duration) throws -> String {
        let output: ProcessRunner.Output
        do {
            output = try ProcessRunner.runBlocking(
                shell, ["-l", "-i", "-c", "printf '\\n%s\\n' '\(marker)'; \(line)"],
                directory: directory, environment: nil, timeout: timeout)
        } catch ProcessRunner.Failure.timedOut {
            throw Failure(message: "The summary timed out.")
        } catch ProcessRunner.Failure.couldNotLaunch(let message) {
            throw Failure(message: message)
        }
        let text = afterMarker(output.stdoutText)
        guard output.status == 0, !text.isEmpty else {
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(message: detail.isEmpty
                          ? "The agent exited with status \(output.status)."
                          : String(detail.suffix(300)))
        }
        return text
    }

    static func afterMarker(_ output: String) -> String {
        let tail = output.range(of: marker).map { String(output[$0.upperBound...]) } ?? output
        return tail.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
