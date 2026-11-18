import Foundation

/// The real connector: Linear's hosted MCP server, OAuth via dynamic
/// client registration + PKCE in the default browser, and the
/// Keychain for the client registration and tokens.
@MainActor
final class LinearConnection: LinearConnecting {
    static let endpoint = URL(string: "https://mcp.linear.app/mcp")!
    nonisolated static let keychainService = "dev.switchboard.linear"
    /// Linear's DCR accepts custom schemes (checked against the live
    /// server). The scheme is declared in Info.plist so the browser's
    /// redirect reaches the app; see BrowserWebAuthenticator.
    static let callbackScheme = "switchboard"
    static let redirectURI = "switchboard://oauth/callback"
    static let registrationAccount = "client"
    static let metadataAccount = "server"

    private let store: CredentialStore
    private let urlSession: URLSession
    private let authenticator: WebAuthenticating
    private var manager: OAuthTokenManager?

    init(store: CredentialStore = KeychainCredentialStore(service: keychainService),
         urlSession: URLSession = .shared,
         authenticator: WebAuthenticating? = nil) {
        self.store = store
        self.urlSession = urlSession
        self.authenticator = authenticator ?? BrowserWebAuthenticator()
    }

    func restore() async -> LinearService? {
        guard let metadata = store.value(AuthorizationServerMetadata.self, for: Self.metadataAccount),
              let registration = store.value(ClientRegistration.self, for: Self.registrationAccount),
              let tokens = store.value(OAuthTokens.self, for: OAuthTokenManager.tokensAccount)
        else { return nil }
        return makeService(metadata: metadata, registration: registration, tokens: tokens)
    }

    func signIn() async throws -> LinearService {
        let metadata = try await OAuthDiscovery(session: urlSession).discover(resource: Self.endpoint)
        guard metadata.codeChallengeMethodsSupported?.contains("S256") ?? true else {
            throw OAuthError.discoveryFailed("server lacks S256 PKCE")
        }
        try store.setValue(metadata, for: Self.metadataAccount)
        let client = OAuthClient(metadata: metadata, resource: Self.endpoint, session: urlSession)
        let registration = try await registration(client: client, metadata: metadata)

        let pkce = PKCE.generate()
        let state = PKCE.randomURLSafeString(byteCount: 16)
        let scopes = ["read", "write"].filter { metadata.scopesSupported?.contains($0) ?? true }
        let url = client.authorizationURL(client: registration, redirectURI: Self.redirectURI,
                                          pkce: pkce, state: state, scopes: scopes)
        let callback = try await authenticator.authenticate(url: url, callbackScheme: Self.callbackScheme)
        let code = try OAuthClient.authorizationCode(from: callback, expectedState: state)

        let response: TokenResponse
        do {
            response = try await client.exchange(code: code, pkce: pkce, client: registration,
                                                 redirectURI: Self.redirectURI)
        } catch let error as OAuthError where error.requiresSignIn {
            // The stored registration is no longer known; register afresh next time.
            try? store.remove(Self.registrationAccount)
            throw error
        }
        let tokens = OAuthTokens(response)
        try store.setValue(tokens, for: OAuthTokenManager.tokensAccount)
        return makeService(metadata: metadata, registration: registration, tokens: tokens)
    }

    func signOut() async {
        await manager?.revoke()
        manager = nil
        try? store.remove(OAuthTokenManager.tokensAccount)
    }

    func cancelSignIn() {
        authenticator.cancel()
    }

    /// The stored registration when it matches this server and redirect,
    /// otherwise a new one.
    private func registration(client: OAuthClient, metadata: AuthorizationServerMetadata) async throws -> ClientRegistration {
        if let stored = store.value(ClientRegistration.self, for: Self.registrationAccount),
           stored.redirectURIs.contains(Self.redirectURI),
           stored.registrationEndpoint == metadata.registrationEndpoint {
            return stored
        }
        let registration = try await client.register(clientName: "Switchboard", redirectURI: Self.redirectURI)
        try store.setValue(registration, for: Self.registrationAccount)
        return registration
    }

    private func makeService(metadata: AuthorizationServerMetadata, registration: ClientRegistration,
                             tokens: OAuthTokens) -> LinearService {
        let client = OAuthClient(metadata: metadata, resource: Self.endpoint, session: urlSession)
        let manager = OAuthTokenManager(client: client, registration: registration, tokens: tokens, store: store)
        self.manager = manager
        let mcp = MCPClient(endpoint: Self.endpoint, authorizer: manager, session: urlSession)
        return MCPLinearService(caller: mcp)
    }
}
