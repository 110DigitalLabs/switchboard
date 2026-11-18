import Foundation

/// Produces a signed-in LinearService: from stored credentials, or by
/// running the browser sign-in.
@MainActor
protocol LinearConnecting {
    /// A service from stored credentials, or nil when there are none.
    func restore() async -> LinearService?
    func signIn() async throws -> LinearService
    /// Revokes and deletes stored tokens.
    func signOut() async
    /// Abandons a sign-in in progress.
    func cancelSignIn()
}

/// Connector for tests and previews.
@MainActor
final class FakeLinearConnector: LinearConnecting {
    var service: LinearService
    var storedSignIn: Bool
    var signInError: Error?
    private(set) var signOutCount = 0

    init(service: LinearService = FakeLinearService.sample(), signedIn: Bool = false) {
        self.service = service
        self.storedSignIn = signedIn
    }

    func restore() async -> LinearService? { storedSignIn ? service : nil }

    func signIn() async throws -> LinearService {
        if let signInError { throw signInError }
        storedSignIn = true
        return service
    }

    func signOut() async {
        storedSignIn = false
        signOutCount += 1
    }

    func cancelSignIn() {}
}
