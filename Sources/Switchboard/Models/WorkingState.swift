import Foundation

enum WorkingState: String, Codable, Sendable {
    case idle
    case working
    case subagentsRunning
    case needsInput
    case finished
    /// The session's shell process has exited.
    case exited

    var label: String {
        switch self {
        case .idle: "Idle"
        case .working: "Working"
        case .subagentsRunning: "Sub-agents running"
        case .needsInput: "Needs input"
        case .finished: "Finished"
        case .exited: "Exited"
        }
    }
}
