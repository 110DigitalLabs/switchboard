import Foundation

/// GitHub PR URLs in a finished tool call's payload, e.g. the URL `gh pr
/// create` prints. This reads hook data, never terminal output.
enum HookPullRequests {
    /// Events that carry a finished tool call: Claude's and Codex's
    /// PostToolUse and Gemini's AfterTool.
    static let toolResultEvents: Set<String> = ["PostToolUse", "AfterTool"]

    /// Canonical PR URLs found anywhere in `tool_input` or `tool_response`.
    static func urls(event: String, json: [String: Any]) -> [String] {
        guard toolResultEvents.contains(event) else { return [] }
        var text = ""
        for key in ["tool_input", "tool_response"] {
            if let value = json[key] { collectStrings(value, into: &text) }
        }
        return PullRequestReference.find(in: text).map(\.url)
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
