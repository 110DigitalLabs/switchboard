import Foundation

/// Where a row's shell starts and what is typed into it.
struct SessionLaunch: Equatable, Sendable {
    var directory: String
    /// Typed at the prompt; nil leaves a bare shell.
    var command: String?
    /// Typed into the agent once it is up, without pressing Return, so the
    /// user finishes the prompt.
    var draft: String?

    /// A brand-new row: the agent starts fresh in the row's folder.
    static func fresh(_ session: Session, hooks: HookInstallation?,
                      options: AgentLaunchOptions = AgentLaunchOptions(), draft: String? = nil) -> SessionLaunch {
        SessionLaunch(directory: session.folderPath,
                      command: session.launchCommand(hooks: hooks, options: options), draft: draft)
    }

    /// Reopening an existing row after a relaunch or a restarted shell.
    /// With a known conversation, resume it where the agent last ran (the
    /// worktree for worktree sessions). If that directory or the agent's
    /// record of the conversation is gone, or there is no conversation yet,
    /// start the agent fresh in the row's folder. If even the folder is gone,
    /// open a plain shell in the home directory.
    static func reopen(_ session: Session, hooks: HookInstallation?,
                       home: String = NSHomeDirectory(),
                       directoryExists: (String) -> Bool = SessionLaunch.directoryExists,
                       conversationExists: (Agent, String) -> Bool = ConversationHistory.exists(agent:conversationID:))
        -> SessionLaunch {
        if let id = session.agentConversationID {
            let directory = session.workingDirectory ?? session.folderPath
            if directoryExists(directory), conversationExists(session.agent, id) {
                return SessionLaunch(directory: directory,
                                     command: session.agent.resumeCommand(conversationID: id, hooks: hooks))
            }
        }
        guard directoryExists(session.folderPath) else {
            return SessionLaunch(directory: home, command: nil)
        }
        return fresh(session, hooks: hooks)
    }

    static func directoryExists(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
