import Foundation

/// What the "+" picker asked for.
enum NewSessionTarget: Hashable {
    case repo(Repo)
    case folder(URL)
    case scratch

    /// The session kind for an existing folder: repos go to the agent's
    /// worktree mode when it has one, everything else runs in place.
    static func kind(forFolder url: URL, agent: Agent, isRepo: (URL) -> Bool = RepoScanner.isGitRepo) -> SessionKind {
        isRepo(url) && agent.supportsWorktree ? .worktree : .folder
    }
}
