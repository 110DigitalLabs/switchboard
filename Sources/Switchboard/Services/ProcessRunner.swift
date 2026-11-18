import Foundation

/// Runs a command to completion off the main thread, with a timeout.
enum ProcessRunner {
    struct Output: Sendable {
        var status: Int32
        var stdout: Data
        var stderr: String

        var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    }

    enum Failure: Error, Equatable {
        case timedOut
        case couldNotLaunch(String)
        case outputHeldOpen
    }

    /// Runs `executable` with `arguments`; never throws for a non-zero exit.
    static func run(_ executable: String, _ arguments: [String], directory: String? = nil,
                    environment: [String: String]? = nil, timeout: Duration) async throws -> Output {
        try await Task.detached(priority: .utility) {
            try runBlocking(executable, arguments, directory: directory, environment: environment, timeout: timeout)
        }.value
    }

    static func runBlocking(_ executable: String, _ arguments: [String], directory: String?,
                            environment: [String: String]?, timeout: Duration) throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true) }
        process.environment = ShellEnvironment.scrubbed(environment ?? ProcessInfo.processInfo.environment)
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw Failure.couldNotLaunch(error.localizedDescription)
        }
        let timedOut = LockedValue(false)
        let killer = DispatchWorkItem { [process] in
            guard process.isRunning else { return }
            timedOut.set(true)
            process.terminate()
        }
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: killer)

        // Drain both pipes on background threads. A process started by a shell
        // rc file can inherit the pipes and hold them open after the command
        // exits or is killed, so the reads are bounded rather than awaited.
        let outputData = LockedValue(Data())
        let errorData = LockedValue(Data())
        let reads = DispatchGroup()
        DispatchQueue.global().async(group: reads) {
            outputData.set(output.fileHandleForReading.readDataToEndOfFile())
        }
        DispatchQueue.global().async(group: reads) {
            errorData.set(errors.fileHandleForReading.readDataToEndOfFile())
        }
        process.waitUntilExit()
        killer.cancel()
        if reads.wait(timeout: .now() + 2) == .timedOut {
            // The pipes are held by a stray descendant: give up on the output.
            throw timedOut.get() ? Failure.timedOut : Failure.outputHeldOpen
        }
        let data = outputData.get()

        if timedOut.get() { throw Failure.timedOut }
        return Output(status: process.terminationStatus, stdout: data,
                      stderr: String(decoding: errorData.get(), as: UTF8.self))
    }
}

final class LockedValue<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func set(_ new: Value) { lock.withLock { value = new } }
    func get() -> Value { lock.withLock { value } }
}
