import Foundation

/// The OAuth 2.1 calls a public native client makes: dynamic client
/// registration, authorization URL, code exchange, refresh, revocation.
struct OAuthClient: Sendable {
    let metadata: AuthorizationServerMetadata
    /// The protected resource (RFC 8707), sent with authorization and token requests.
    let resource: URL
    let session: URLSession

    init(metadata: AuthorizationServerMetadata, resource: URL, session: URLSession = .shared) {
        self.metadata = metadata
        self.resource = resource
        self.session = session
    }

    func register(clientName: String, redirectURI: String) async throws -> ClientRegistration {
        guard let endpoint = metadata.registrationEndpoint else { throw OAuthError.registrationUnsupported }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            ClientRegistrationRequest(clientName: clientName, redirectURIs: [redirectURI]))
        let data = try await perform(request)
        var registration = try JSONDecoder.oauth.decode(ClientRegistration.self, from: data)
        registration.registrationEndpoint = endpoint
        return registration
    }

    func authorizationURL(client: ClientRegistration, redirectURI: String, pkce: PKCE,
                          state: String, scopes: [String]) -> URL {
        var components = URLComponents(url: metadata.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        var items = components.queryItems ?? []
        items += [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: client.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "resource", value: resource.absoluteString),
        ]
        if !scopes.isEmpty { items.append(URLQueryItem(name: "scope", value: scopes.joined(separator: " "))) }
        components.queryItems = items
        return components.url!
    }

    /// Extracts the code from the redirect, checking state and errors.
    static func authorizationCode(from callback: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            if error == "access_denied" { throw OAuthError.cancelled }
            throw OAuthError.server(status: 0, error: error, description: value("error_description"))
        }
        guard value("state") == expectedState else { throw OAuthError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw OAuthError.invalidCallback("no code") }
        return code
    }

    func exchange(code: String, pkce: PKCE, client: ClientRegistration, redirectURI: String) async throws -> TokenResponse {
        try await tokenRequest(client: client, [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": pkce.verifier,
        ])
    }

    func refresh(refreshToken: String, client: ClientRegistration) async throws -> TokenResponse {
        try await tokenRequest(client: client, ["grant_type": "refresh_token", "refresh_token": refreshToken])
    }

    /// Best effort (RFC 7009); failures are ignored.
    func revoke(token: String, client: ClientRegistration) async {
        guard let endpoint = metadata.revocationEndpoint else { return }
        var form = ["token": token, "client_id": client.clientID]
        if let secret = client.clientSecret { form["client_secret"] = secret }
        _ = try? await session.data(for: Self.formRequest(endpoint, form))
    }

    private func tokenRequest(client: ClientRegistration, _ fields: [String: String]) async throws -> TokenResponse {
        var form = fields
        form["client_id"] = client.clientID
        form["resource"] = resource.absoluteString
        if let secret = client.clientSecret { form["client_secret"] = secret }
        let data = try await perform(Self.formRequest(metadata.tokenEndpoint, form))
        return try JSONDecoder.oauth.decode(TokenResponse.self, from: data)
    }

    static func formRequest(_ url: URL, _ form: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = Data(form.sorted { $0.key < $1.key }.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&").utf8)
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = try? JSONDecoder.oauth.decode(OAuthErrorResponse.self, from: data)
            throw OAuthError.server(status: status, error: body?.error, description: body?.errorDescription)
        }
        return data
    }
}
