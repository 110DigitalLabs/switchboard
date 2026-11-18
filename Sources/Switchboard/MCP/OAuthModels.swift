import Foundation

/// RFC 9728 protected resource metadata.
struct ProtectedResourceMetadata: Decodable, Equatable, Sendable {
    let resource: String
    let authorizationServers: [URL]
    let scopesSupported: [String]?

    enum CodingKeys: String, CodingKey {
        case resource
        case authorizationServers = "authorization_servers"
        case scopesSupported = "scopes_supported"
    }
}

/// RFC 8414 authorization server metadata (the fields we use).
struct AuthorizationServerMetadata: Codable, Equatable, Sendable {
    let issuer: String
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let registrationEndpoint: URL?
    let revocationEndpoint: URL?
    let scopesSupported: [String]?
    let codeChallengeMethodsSupported: [String]?

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case registrationEndpoint = "registration_endpoint"
        case revocationEndpoint = "revocation_endpoint"
        case scopesSupported = "scopes_supported"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
    }
}

/// RFC 7591 dynamic client registration request.
struct ClientRegistrationRequest: Encodable, Equatable, Sendable {
    let clientName: String
    let redirectURIs: [String]
    let grantTypes = ["authorization_code", "refresh_token"]
    let responseTypes = ["code"]
    let tokenEndpointAuthMethod = "none"

    enum CodingKeys: String, CodingKey {
        case clientName = "client_name"
        case redirectURIs = "redirect_uris"
        case grantTypes = "grant_types"
        case responseTypes = "response_types"
        case tokenEndpointAuthMethod = "token_endpoint_auth_method"
    }
}

/// RFC 7591 registration response, stored in the Keychain.
struct ClientRegistration: Codable, Equatable, Sendable {
    let clientID: String
    let clientSecret: String?
    let redirectURIs: [String]
    /// The registration endpoint that issued it, so a changed server
    /// triggers a fresh registration.
    var registrationEndpoint: URL?

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case clientSecret = "client_secret"
        case redirectURIs = "redirect_uris"
        case registrationEndpoint = "registration_endpoint"
    }
}

/// A token endpoint response.
struct TokenResponse: Decodable, Equatable, Sendable {
    let accessToken: String
    let tokenType: String?
    let expiresIn: Double?
    let refreshToken: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

/// Tokens as stored in the Keychain.
struct OAuthTokens: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?

    init(accessToken: String, refreshToken: String?, expiresAt: Date?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// Applies a token response; a refresh that omits the refresh token
    /// keeps the previous one.
    init(_ response: TokenResponse, previousRefreshToken: String? = nil, now: Date = Date()) {
        accessToken = response.accessToken
        refreshToken = response.refreshToken ?? previousRefreshToken
        expiresAt = response.expiresIn.map { now.addingTimeInterval($0) }
    }

    /// True when the token expires within `margin` seconds.
    func isExpired(now: Date = Date(), margin: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) < margin
    }
}

/// An OAuth error body (RFC 6749 §5.2).
struct OAuthErrorResponse: Decodable, Equatable, Sendable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

enum OAuthError: Error, Equatable, LocalizedError {
    case discoveryFailed(String)
    case registrationUnsupported
    case server(status: Int, error: String?, description: String?)
    case invalidCallback(String)
    case stateMismatch
    case cancelled

    var errorDescription: String? {
        switch self {
        case .discoveryFailed(let detail): "Could not find Linear's sign-in server (\(detail))"
        case .registrationUnsupported: "The server does not support client registration"
        case .server(let status, let error, let description):
            description ?? error ?? "Sign-in server returned HTTP \(status)"
        case .invalidCallback(let detail): "Sign-in returned an unexpected response (\(detail))"
        case .stateMismatch: "Sign-in response did not match the request"
        case .cancelled: "Sign-in was cancelled"
        }
    }

    /// The grant or client is no longer valid, so the user must sign in again.
    var requiresSignIn: Bool {
        if case .server(_, let error, _) = self {
            return error == "invalid_grant" || error == "invalid_client" || error == "unauthorized_client"
        }
        return false
    }
}

extension JSONDecoder {
    static let oauth = JSONDecoder()
}
