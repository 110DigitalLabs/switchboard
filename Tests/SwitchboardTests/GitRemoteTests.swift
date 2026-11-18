import Testing
@testable import Switchboard

struct GitRemoteTests {
    @Test(arguments: [
        "https://github.com/acme/api.git",
        "https://github.com/acme/api",
        "https://user@github.com/acme/api.git",
        "git@github.com:acme/api.git",
        "git@github.com:acme/api",
        "ssh://git@github.com/acme/api.git",
        "ssh://git@ssh.github.com:443/acme/api.git",
        "  https://www.github.com/acme/api.git\n",
    ])
    func parsesGitHubRemotes(_ remote: String) {
        #expect(GitRemote.gitHubRepo(fromRemoteURL: remote) == GitHubRepoRef(owner: "acme", name: "api"))
    }

    @Test func keepsDotsInRepoNames() {
        #expect(GitRemote.gitHubRepo(fromRemoteURL: "git@github.com:acme/site.github.io.git")
                == GitHubRepoRef(owner: "acme", name: "site.github.io"))
    }

    @Test(arguments: [
        "https://gitlab.com/acme/api.git",
        "git@bitbucket.org:acme/api.git",
        "/Users/me/repos/api",
        "https://github.com/acme",
        "https://github.com/acme/api/tree/main",
        "",
    ])
    func rejectsOtherRemotes(_ remote: String) {
        #expect(GitRemote.gitHubRepo(fromRemoteURL: remote) == nil)
    }

    @Test func repoMatchingIgnoresCase() {
        #expect(GitHubRepoRef(owner: "Acme", name: "API").matches(GitHubRepoRef(owner: "acme", name: "api")))
    }
}
