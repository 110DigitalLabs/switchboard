import Darwin
import Foundation

/// Which folders Switchboard may delete: only paths strictly inside
/// `<home>/tickets`, `<home>/reviews` or `<home>/scratch`, after resolving
/// symlinks, and never those roots themselves.
enum TempFolderSafety {
    static let rootNames = ["tickets", ReviewSessions.folderName, "scratch"]

    enum Verdict: Equatable {
        /// Safe to trash; the canonical, symlink-free location.
        case deletable(URL)
        /// Nothing there; nothing to delete.
        case missing
        case refused(String)
    }

    static func check(_ path: String, home: URL) -> Verdict {
        guard path.hasPrefix("/") else { return .refused("not an absolute path") }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.contains(where: { $0 == ".." || $0 == "." }) else {
            return .refused("path contains . or ..")
        }
        // The folder itself must be a real directory, not a link to elsewhere
        // (trashing a resolved link target is never what the row meant).
        var info = stat()
        guard lstat(path, &info) == 0 else { return .missing }
        guard info.st_mode & S_IFMT == S_IFDIR else { return .refused("not a directory") }
        guard let resolved = realPath(path) else { return .missing }

        let roots = rootNames.compactMap { root(named: $0, home: home) }
        for root in roots where resolved.hasPrefix(root + "/") {
            let rest = resolved.dropFirst(root.count + 1)
            if !rest.isEmpty { return .deletable(URL(fileURLWithPath: resolved, isDirectory: true)) }
        }
        return .refused("not inside \(rootNames.map { home.appendingPathComponent($0).path }.joined(separator: ", "))")
    }

    /// `<resolved home>/<name>`, when that is a real directory. The home may
    /// sit behind a symlink; the root itself may not, so a link such as
    /// `tickets -> /Users` cannot widen what is deletable.
    private static func root(named name: String, home: URL) -> String? {
        guard let home = realPath(home.path) else { return nil }
        let path = home + "/" + name
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return nil }
        return path
    }

    /// `realpath(3)`: unlike `URL.resolvingSymlinksInPath`, it does not strip
    /// `/private` and so compares consistently. Nil when the path is missing.
    static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
