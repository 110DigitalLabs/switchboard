import Foundation
import Testing
@testable import Switchboard

struct ClaudeTranscriptTests {
    // Entry shapes match real files under ~/.claude/projects (Claude Code 2.1).
    static let fixture = """
        {"type":"user","message":{"role":"user","content":"title the \\"type\\":\\"custom-title\\" thing"},"sessionId":"s"}
        {"type":"ai-title","aiTitle":"Channel security review","sessionId":"s"}
        {"type":"assistant","message":{"role":"assistant","content":[]},"sessionId":"s"}
        {"type":"custom-title","customTitle":"Auth refactor","sessionId":"s"}
        {"type":"ai-title","aiTitle":"Later generated title","sessionId":"s"}
        """

    @Test func customTitleWinsOverGenerated() {
        #expect(ClaudeTranscript.title(from: Data(Self.fixture.utf8)) == "Auth refactor")
    }

    @Test func latestGeneratedTitleWithoutRename() {
        let lines = Self.fixture.split(separator: "\n").filter { !$0.contains("custom-title\",\"customTitle") }
        #expect(ClaudeTranscript.title(from: Data(lines.joined(separator: "\n").utf8)) == "Later generated title")
    }

    @Test func noTitle() {
        #expect(ClaudeTranscript.title(from: Data(#"{"type":"user"}"#.utf8)) == nil)
        #expect(ClaudeTranscript.title(fromTranscriptAt: "/nonexistent/x.jsonl") == nil)
    }
}
