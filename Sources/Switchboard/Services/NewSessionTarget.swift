import Foundation

/// What the "+" picker asked for.
enum NewSessionTarget: Hashable {
    case repo(Repo)
    case folder(URL)
    case scratch

    /// The session kind when moving into a repo on request: the agent's
    /// worktree mode when it has one, otherwise in place. New sessions start
    /// in the folder itself and never use this.
    static func kind(forFolder url: URL, agent: Agent, isRepo: (URL) -> Bool = RepoScanner.isGitRepo) -> SessionKind {
        isRepo(url) && agent.supportsWorktree ? .worktree : .folder
    }
}
