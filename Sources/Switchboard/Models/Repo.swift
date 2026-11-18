import Foundation

/// A git repository discovered under the home folder.
struct Repo: Identifiable, Hashable, Sendable {
    let url: URL
    /// Path relative to the home folder, e.g. `work/api`.
    let relativePath: String

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}
