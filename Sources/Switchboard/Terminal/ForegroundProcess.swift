import Foundation

enum ForegroundProcess {
    /// True when a valid foreground group exists and it is not the login
    /// shell's (an interactive shell leads its own group), meaning a job
    /// such as the agent owns the terminal.
    static func isOtherThanShell(foregroundGroup: pid_t, shellPID: pid_t) -> Bool {
        foregroundGroup > 0 && shellPID > 0 && foregroundGroup != shellPID
    }
}
