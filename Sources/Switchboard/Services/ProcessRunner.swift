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
        var env = environment ?? ProcessInfo.processInfo.environment
        env.removeValue(forKey: ShellEnvironment.rowIDKey)
        process.environment = env
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

        // Drain stderr concurrently so a chatty command cannot fill the pipe.
        let errorData = LockedValue(Data())
        let errorRead = DispatchGroup()
        DispatchQueue.global().async(group: errorRead) {
            errorData.set(errors.fileHandleForReading.readDataToEndOfFile())
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        errorRead.wait()

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
