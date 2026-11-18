import Foundation

/// A row's working state as driven by agent events.
struct RowActivity: Codable, Hashable, Sendable {
    var state: WorkingState = .idle
    var runningSubagents = 0

    /// Applies an event and returns true when the row newly needs the user's
    /// attention (finished, or needs input), which is when to notify.
    @discardableResult
    mutating func apply(_ kind: AgentEvent.Kind) -> Bool {
        let wasAttention = state.wantsAttention
        switch kind {
        case .sessionStarted, .sessionEnded:
            runningSubagents = 0
            state = .idle
        case .promptSubmitted, .toolActivity:
            state = busyState
        case .subagentStarted:
            runningSubagents += 1
            state = .subagentsRunning
        case .subagentStopped:
            runningSubagents = max(0, runningSubagents - 1)
            // Background sub-agents can outlive the turn; don't undo "finished".
            if state == .subagentsRunning { state = busyState }
        case .needsInput:
            state = .needsInput
        case .idleReminder:
            // Only a turn the user hasn't looked at yet escalates.
            if state == .finished { state = .needsInput }
        case .turnFinished:
            state = .finished
        case .statusLine, .info:
            break
        }
        return state.wantsAttention && !wasAttention
    }

    /// Called when the user looks at the row.
    mutating func markViewed() {
        if state == .finished { state = .idle }
    }

    private var busyState: WorkingState {
        runningSubagents > 0 ? .subagentsRunning : .working
    }
}

extension WorkingState {
    var wantsAttention: Bool { self == .finished || self == .needsInput }
}
