import Foundation
import Testing
@testable import Switchboard

/// Runs the real installed sh helper against the real socket server.
struct HookHelperTests {
    final class Inbox: @unchecked Sendable {
        private let lock = NSLock()
        private var messages: [HookMessage] = []
        func add(_ message: HookMessage) { lock.withLock { messages.append(message) } }
        var all: [HookMessage] { lock.withLock { messages } }
    }

    private static func makeDirectory() throws -> URL {
        // A space in the path, like "Application Support".
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sb \(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func run(_ helper: String, _ args: [String], stdin: String, env: [String: String]) throws -> (String, Double) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: helper)
        process.arguments = args
        process.environment = env
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        let start = Date()
        try process.run()
        input.fileHandleForWriting.write(Data(stdin.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        let elapsed = Date().timeIntervalSince(start)
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 0)
        return (text, elapsed)
    }

    @Test func helperDeliversEventsAndWrapsUserStatusLine() async throws {
        let dir = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let home = dir.appendingPathComponent("home")
        let claudeDir = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try #"{"statusLine":{"type":"command","command":"printf 'user:'; cat; printf '\\n'","padding":1}}"#
            .write(to: claudeDir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)

        let installation = try HookInstaller.install(into: dir.appendingPathComponent("support"), home: home,
                                                     environment: [:])
        let settings = try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: installation.claudeSettingsPath))) as? [String: Any]
        #expect((settings?["statusLine"] as? [String: Any])?["padding"] as? Int == 1)

        let socket = "/tmp/sb-test-\(UUID().uuidString.prefix(8)).sock"
        let inbox = Inbox()
        let server = HookSocketServer(path: socket) { data in
            if let message = HookMessage(data: data) { inbox.add(message) }
        }
        try server.start()
        defer { unlink(socket) }

        let row = UUID()
        let env = ["SWITCHBOARD_ROW_ID": row.uuidString, "SWITCHBOARD_SOCKET": socket, "HOME": home.path,
                   "PATH": "/usr/bin:/bin"]
        let (silent, _) = try Self.run(installation.helperPath, ["claude", "SessionStart"],
                                       stdin: #"{"session_id":"c-1"}"#, env: env)
        #expect(silent.isEmpty)
        let status = #"{"session_id":"c-1","cwd":"/nonexistent"}"#
        let (printed, _) = try Self.run(installation.helperPath, ["claude", "statusline"], stdin: status, env: env)
        #expect(printed == "user:\(status)\n")

        for _ in 0..<50 where inbox.all.count < 2 { try await Task.sleep(for: .milliseconds(50)) }
        let messages = inbox.all
        try #require(messages.count == 2)
        #expect(messages[0].event == "SessionStart")
        #expect(messages[0].rowID == row)
        #expect(String(decoding: messages[0].payload, as: UTF8.self) == #"{"session_id":"c-1"}"#)
        #expect(messages[1].event == "statusline")
        #expect(messages[1].trailingText == "user:\(status)\n")
    }

    @Test func helperExitsQuietlyWithoutApp() throws {
        let dir = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let installation = try HookInstaller.install(into: dir, home: dir, environment: [:])
        let env = ["SWITCHBOARD_ROW_ID": UUID().uuidString, "SWITCHBOARD_SOCKET": "/tmp/sb-missing.sock",
                   "HOME": dir.path, "PATH": "/usr/bin:/bin"]
        let (out, elapsed) = try Self.run(installation.helperPath, ["claude", "Stop"], stdin: "{}", env: env)
        #expect(out.isEmpty)
        #expect(elapsed < 1)
        let (statusOut, _) = try Self.run(installation.helperPath, ["claude", "statusline"], stdin: "{}", env: env)
        #expect(statusOut.isEmpty) // no user status line configured
    }

    @Test func detectsUserCodexNotify() throws {
        let dir = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = dir.appendingPathComponent("config.toml")
        try "model = \"o3\"\n\n[notice]\nnotify = true\n".write(to: config, atomically: true, encoding: .utf8)
        #expect(!CodexHookConfig.userHasNotify(codexHome: dir))
        try "model = \"o3\"\nnotify = [\"say\"]\n".write(to: config, atomically: true, encoding: .utf8)
        #expect(CodexHookConfig.userHasNotify(codexHome: dir))
    }
}
