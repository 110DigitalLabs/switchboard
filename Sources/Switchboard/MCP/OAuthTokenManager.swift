import Foundation

/// Holds the current tokens, refreshes them (one refresh at a time), and
/// persists every change. Serves as the MCP client's authorizer.
actor OAuthTokenManager: MCPAuthorizing {
    static let tokensAccount = "tokens"

    private let client: OAuthClient
    private let registration: ClientRegistration
    private let store: CredentialStore
    private var tokens: OAuthTokens
    private var refreshing: Task<OAuthTokens, Error>?

    init(client: OAuthClient, registration: ClientRegistration, tokens: OAuthTokens, store: CredentialStore) {
        self.client = client
        self.registration = registration
        self.tokens = tokens
        self.store = store
    }

    func accessToken() async throws -> String {
        if tokens.isExpired(), tokens.refreshToken != nil {
            return try await refresh().accessToken
        }
        return tokens.accessToken
    }

    func refreshAccessToken(rejected: String) async throws -> String {
        // Another caller already refreshed past the rejected token.
        if tokens.accessToken != rejected { return tokens.accessToken }
        return try await refresh().accessToken
    }

    /// Revokes the refresh token (best effort) and forgets the tokens.
    func revoke() async {
        if let refreshToken = tokens.refreshToken {
            await client.revoke(token: refreshToken, client: registration)
        }
        try? store.remove(Self.tokensAccount)
    }

    private func refresh() async throws -> OAuthTokens {
        if let refreshing { return try await refreshing.value }
        guard let refreshToken = tokens.refreshToken else { throw MCPError.unauthorized }
        let task = Task { [client, registration] in
            let response = try await client.refresh(refreshToken: refreshToken, client: registration)
            return OAuthTokens(response, previousRefreshToken: refreshToken)
        }
        refreshing = task
        defer { refreshing = nil }
        do {
            tokens = try await task.value
            try? store.setValue(tokens, for: Self.tokensAccount)
            return tokens
        } catch let error as OAuthError where error.requiresSignIn || error.isClientError {
            try? store.remove(Self.tokensAccount)
            throw MCPError.unauthorized
        }
    }
}

private extension OAuthError {
    var isClientError: Bool {
        if case .server(let status, _, _) = self { return (400..<500).contains(status) }
        return false
    }
}
