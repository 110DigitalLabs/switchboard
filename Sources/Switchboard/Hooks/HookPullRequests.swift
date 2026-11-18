import Foundation

/// GitHub PRs a session created, read from a finished tool call's hook
/// payload, never from terminal output. Only two kinds of call count: a shell
/// call whose command runs `gh pr create`, and a GitHub MCP tool whose name
/// contains `create_pull_request`. Anything else that merely mentions a PR
/// (`gh pr view <someone else's PR>`, a pasted link) is not linked.
enum HookPullRequests {
    /// Events that carry a finished tool call: Claude's and Codex's
    /// PostToolUse and Gemini's AfterTool.
    static let toolResultEvents: Set<String> = ["PostToolUse", "AfterTool"]

    /// Shell tool names across agents: Claude `Bash`, Codex `shell` /
    /// `exec_command`, Gemini `run_shell_command`.
    static let shellTools: Set<String> = ["bash", "shell", "exec_command", "local_shell", "run_shell_command"]

    /// Canonical PR URLs from the tool's response when the call created a PR.
    static func urls(event: String, json: [String: Any]) -> [String] {
        guard toolResultEvents.contains(event),
              let tool = json["tool_name"] as? String,
              createsPullRequest(tool: tool, input: json["tool_input"]),
              let response = json["tool_response"] else { return [] }
        var text = ""
        collectStrings(response, into: &text)
        return PullRequestReference.find(in: text).map(\.url)
    }

    static func createsPullRequest(tool: String, input: Any?) -> Bool {
        let name = tool.lowercased()
        if name.contains("create_pull_request") { return true }
        guard shellTools.contains(name) else { return false }
        return runsGHPRCreate(command(in: input))
    }

    /// True when `gh pr create` appears as a command, i.e. at the start or
    /// after a shell separator, not inside an argument such as a commit message.
    static func runsGHPRCreate(_ command: String) -> Bool {
        command.range(of: #"(^|[;&|(`\n]|\$\()\s*(\S+/)?gh\s+pr\s+create(\s|$)"#,
                      options: .regularExpression) != nil
    }

    /// The command string: Claude and Gemini send `{"command": "..."}`, Codex
    /// may send an argv array such as `["bash", "-lc", "..."]`.
    private static func command(in input: Any?) -> String {
        guard let input = input as? [String: Any] else { return "" }
        switch input["command"] ?? input["cmd"] {
        case let string as String: return string
        case let argv as [Any]: return argv.compactMap { $0 as? String }.joined(separator: "\n")
        default: return ""
        }
    }

    private static func collectStrings(_ value: Any, into text: inout String, depth: Int = 0) {
        guard depth < 8 else { return }
        switch value {
        case let string as String:
            text += string + "\n"
        case let array as [Any]:
            for item in array { collectStrings(item, into: &text, depth: depth + 1) }
        case let dictionary as [String: Any]:
            for key in dictionary.keys.sorted() {
                collectStrings(dictionary[key]!, into: &text, depth: depth + 1)
            }
        default:
            break
        }
    }
}
