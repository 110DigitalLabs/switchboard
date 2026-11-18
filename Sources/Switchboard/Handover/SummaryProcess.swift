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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-i", "-c", "printf '\\n%s\\n' '\(marker)'; \(line)"]
        process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: ShellEnvironment.rowIDKey)
        process.environment = environment
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice

        try process.run()
        let timedOut = TimeoutFlag()
        let killer = DispatchWorkItem { [process] in
            guard process.isRunning else { return }
            timedOut.set()
            process.terminate()
        }
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: killer)

        // Drain stderr concurrently so a chatty agent cannot fill the pipe.
        let errorData = ErrorBuffer()
        let errorRead = DispatchGroup()
        DispatchQueue.global().async(group: errorRead) {
            errorData.set(errors.fileHandleForReading.readDataToEndOfFile())
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        errorRead.wait()

        if timedOut.isSet { throw Failure(message: "The summary timed out.") }
        let text = afterMarker(String(decoding: data, as: UTF8.self))
        guard process.terminationStatus == 0, !text.isEmpty else {
            let detail = String(decoding: errorData.get(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(message: detail.isEmpty
                          ? "The agent exited with status \(process.terminationStatus)."
                          : String(detail.suffix(300)))
        }
        return text
    }

    static func afterMarker(_ output: String) -> String {
        let tail = output.range(of: marker).map { String(output[$0.upperBound...]) } ?? output
        return tail.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}

private final class ErrorBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func set(_ new: Data) { lock.withLock { data = new } }
    func get() -> Data { lock.withLock { data } }
}
