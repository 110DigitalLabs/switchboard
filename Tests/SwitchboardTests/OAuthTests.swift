import Foundation
import Testing
@testable import Switchboard

struct PKCETests {
    @Test func challengeIsBase64URLSHA256() {
        // Expected value computed independently with Python's hashlib.
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mJ92K9TGsLsg7AuHFGdeqGc38pdhuo")
        #expect(pkce.challenge == "x3GPsLyTQLBpTbTvaoPLQdqRYS3xlijqMzA38jhhDqs")
        #expect(pkce.method == "S256")
    }

    @Test func generatedVerifiersAreValidAndUnique() {
        let a = PKCE.generate(), b = PKCE.generate()
        #expect(a.verifier != b.verifier)
        #expect(a.verifier.count == 43)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        #expect(a.verifier.unicodeScalars.allSatisfy(allowed.contains))
        #expect(a.challenge == PKCE.challenge(for: a.verifier))
    }
}

struct OAuthModelTests {
    /// Captured from https://mcp.linear.app/.well-known/oauth-authorization-server.
    static let serverMetadata = #"""
    {"issuer":"https://mcp.linear.app","authorization_endpoint":"https://mcp.linear.app/authorize","token_endpoint":"https://mcp.linear.app/token","registration_endpoint":"https://mcp.linear.app/register","scopes_supported":["read","write","openid","email"],"response_types_supported":["code"],"response_modes_supported":["query"],"grant_types_supported":["authorization_code","refresh_token","urn:ietf:params:oauth:grant-type:jwt-bearer"],"token_endpoint_auth_methods_supported":["client_secret_basic","client_secret_post","none"],"revocation_endpoint":"https://mcp.linear.app/token","code_challenge_methods_supported":["S256"],"authorization_response_iss_parameter_supported":true,"client_id_metadata_document_supported":true,"resource":"https://mcp.linear.app/mcp"}
    """#

    static var metadata: AuthorizationServerMetadata {
        try! JSONDecoder().decode(AuthorizationServerMetadata.self, from: Data(serverMetadata.utf8))
    }

    @Test func decodesLinearMetadata() throws {
        let protected = try JSONDecoder().decode(ProtectedResourceMetadata.self, from: Data(#"""
        {"resource":"https://mcp.linear.app/mcp","authorization_servers":["https://mcp.linear.app"],"scopes_supported":["read","write"],"bearer_methods_supported":["header"]}
        """#.utf8))
        #expect(protected.authorizationServers == [URL(string: "https://mcp.linear.app")!])
        #expect(protected.scopesSupported == ["read", "write"])

        let server = Self.metadata
        #expect(server.tokenEndpoint.absoluteString == "https://mcp.linear.app/token")
        #expect(server.registrationEndpoint?.absoluteString == "https://mcp.linear.app/register")
        #expect(server.codeChallengeMethodsSupported == ["S256"])
    }

    @Test func decodesRegistrationResponse() throws {
        // Shape returned by Linear's /register for a custom-scheme client.
        let json = #"{"client_id":"n3IfvlqxG--QFEEd","redirect_uris":["switchboard://oauth/callback"],"client_name":"Switchboard","grant_types":["authorization_code","refresh_token"],"response_types":["code"],"token_endpoint_auth_method":"none","client_id_issued_at":1794973431}"#
        let registration = try JSONDecoder().decode(ClientRegistration.self, from: Data(json.utf8))
        #expect(registration.clientID == "n3IfvlqxG--QFEEd")
        #expect(registration.clientSecret == nil)
        #expect(registration.redirectURIs == ["switchboard://oauth/callback"])
    }

    @Test func encodesRegistrationRequest() throws {
        let body = try JSONValue(data: JSONEncoder().encode(
            ClientRegistrationRequest(clientName: "Switchboard", redirectURIs: ["switchboard://oauth/callback"])))
        #expect(body["token_endpoint_auth_method"] == "none")
        #expect(body["grant_types"] == ["authorization_code", "refresh_token"])
        #expect(body["redirect_uris"] == ["switchboard://oauth/callback"])
    }

    @Test func wellKnownURLsInsertPathFirst() {
        let urls = OAuthDiscovery.wellKnownURLs(for: URL(string: "https://mcp.linear.app/mcp")!,
                                                suffix: "oauth-protected-resource")
        #expect(urls.map(\.absoluteString) == [
            "https://mcp.linear.app/.well-known/oauth-protected-resource/mcp",
            "https://mcp.linear.app/.well-known/oauth-protected-resource",
        ])
        #expect(OAuthDiscovery.wellKnownURLs(for: URL(string: "https://mcp.linear.app")!, suffix: "x")
            .map(\.absoluteString) == ["https://mcp.linear.app/.well-known/x"])
    }

    @Test func authorizationURLCarriesPKCEAndResource() throws {
        let client = OAuthClient(metadata: Self.metadata, resource: URL(string: "https://mcp.linear.app/mcp")!)
        let registration = ClientRegistration(clientID: "abc", clientSecret: nil,
                                              redirectURIs: ["switchboard://oauth/callback"])
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mJ92K9TGsLsg7AuHFGdeqGc38pdhuo")
        let url = client.authorizationURL(client: registration, redirectURI: "switchboard://oauth/callback",
                                          pkce: pkce, state: "s1", scopes: ["read", "write"])
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.path == "/authorize")
        #expect(query["client_id"] == "abc")
        #expect(query["code_challenge"] == pkce.challenge)
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["redirect_uri"] == "switchboard://oauth/callback")
        #expect(query["resource"] == "https://mcp.linear.app/mcp")
        #expect(query["scope"] == "read write")
        #expect(query["state"] == "s1")
    }

    @Test func callbackParsing() throws {
        let ok = URL(string: "switchboard://oauth/callback?code=xyz&state=s1&iss=https%3A%2F%2Fmcp.linear.app")!
        #expect(try OAuthClient.authorizationCode(from: ok, expectedState: "s1") == "xyz")
        #expect(throws: OAuthError.stateMismatch) {
            try OAuthClient.authorizationCode(from: ok, expectedState: "other")
        }
        #expect(throws: OAuthError.cancelled) {
            try OAuthClient.authorizationCode(from: URL(string: "switchboard://oauth/callback?error=access_denied&state=s1")!,
                                              expectedState: "s1")
        }
    }

    @Test func tokenResponseKeepsRefreshTokenWhenOmitted() throws {
        let response = try JSONDecoder().decode(TokenResponse.self, from: Data(
            #"{"access_token":"new","token_type":"Bearer","expires_in":3600}"#.utf8))
        let now = Date(timeIntervalSince1970: 1000)
        let tokens = OAuthTokens(response, previousRefreshToken: "r1", now: now)
        #expect(tokens.refreshToken == "r1")
        #expect(tokens.expiresAt == now.addingTimeInterval(3600))
        #expect(!tokens.isExpired(now: now))
        #expect(tokens.isExpired(now: now.addingTimeInterval(3590)))
    }

    @Test func formEncodingEscapesReservedCharacters() throws {
        let request = OAuthClient.formRequest(URL(string: "https://x/token")!, ["b": "a+b c", "a": "x/y"])
        #expect(String(decoding: try #require(request.httpBody), as: UTF8.self) == "a=x%2Fy&b=a%2Bb%20c")
    }

    @Test func credentialStoreRoundTrips() throws {
        let store = InMemoryCredentialStore()
        let tokens = OAuthTokens(accessToken: "a", refreshToken: "r", expiresAt: nil)
        try store.setValue(tokens, for: "tokens")
        #expect(store.value(OAuthTokens.self, for: "tokens") == tokens)
        try store.remove("tokens")
        #expect(store.value(OAuthTokens.self, for: "tokens") == nil)
    }
}
