import Foundation

enum SessionKind: String, Codable, Sendable {
    /// A git repo where the agent starts in its own worktree mode.
    case worktree
    /// Any folder, agent started directly in it.
    case folder
    /// A throwaway folder under `<home>/scratch`.
    case scratch
    /// A ticket planning folder under `<home>/tickets` (stage 4).
    case temp

    /// Scratch and temp sessions live in their own groups at the bottom.
    var isBottomGrouped: Bool { self == .scratch || self == .temp }
}
