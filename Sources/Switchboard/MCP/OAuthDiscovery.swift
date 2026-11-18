import Foundation

/// Finds the authorization server for an MCP endpoint, per the MCP
/// authorization spec: protected resource metadata (RFC 9728), then
/// authorization server metadata (RFC 8414, falling back to OIDC).
struct OAuthDiscovery: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func discover(resource: URL) async throws -> AuthorizationServerMetadata {
        let protected = try await protectedResourceMetadata(for: resource)
        guard let server = protected.authorizationServers.first else {
            throw OAuthError.discoveryFailed("no authorization server listed")
        }
        return try await authorizationServerMetadata(issuer: server)
    }

    func protectedResourceMetadata(for resource: URL) async throws -> ProtectedResourceMetadata {
        for url in Self.wellKnownURLs(for: resource, suffix: "oauth-protected-resource") {
            if let metadata: ProtectedResourceMetadata = try await fetch(url) { return metadata }
        }
        throw OAuthError.discoveryFailed("no protected resource metadata")
    }

    func authorizationServerMetadata(issuer: URL) async throws -> AuthorizationServerMetadata {
        let candidates = Self.wellKnownURLs(for: issuer, suffix: "oauth-authorization-server")
            + Self.wellKnownURLs(for: issuer, suffix: "openid-configuration")
        for url in candidates {
            if let metadata: AuthorizationServerMetadata = try await fetch(url) { return metadata }
        }
        throw OAuthError.discoveryFailed("no authorization server metadata")
    }

    /// Path-inserted well-known URL first, then the root one:
    /// https://host/mcp → https://host/.well-known/<suffix>/mcp, https://host/.well-known/<suffix>
    static func wellKnownURLs(for url: URL, suffix: String) -> [URL] {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [] }
        components.query = nil
        components.fragment = nil
        let path = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        var urls: [URL] = []
        if !path.isEmpty {
            components.path = "/.well-known/\(suffix)\(path)"
            if let url = components.url { urls.append(url) }
        }
        components.path = "/.well-known/\(suffix)"
        if let url = components.url { urls.append(url) }
        return urls
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T? {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder.oauth.decode(T.self, from: data)
    }
}
