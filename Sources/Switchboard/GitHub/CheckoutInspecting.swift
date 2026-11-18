import Foundation

/// What PR discovery needs to know about a worktree checkout.
protocol CheckoutInspecting: Sendable {
    func branch(in directory: String) async -> String?
    func originRepo(in directory: String) async -> GitHubRepoRef?
    func defaultBranch(in directory: String) async -> String?
}

extension GitInfo: CheckoutInspecting {}

enum BranchRules {
    /// Branches that are never a PR's head worth looking up.
    static func isLookupWorthy(_ branch: String, defaultBranch: String?) -> Bool {
        let lowered = branch.lowercased()
        return lowered != defaultBranch?.lowercased() && !["main", "master", "trunk", "develop", "head"].contains(lowered)
    }
}
