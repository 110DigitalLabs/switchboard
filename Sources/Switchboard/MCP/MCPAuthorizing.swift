import Foundation

/// Supplies bearer tokens to an MCP client.
protocol MCPAuthorizing: Sendable {
    /// A current access token, refreshed first if it is known to be expired.
    func accessToken() async throws -> String
    /// Forces a refresh after the server rejected `rejected`. Throws
    /// `MCPError.unauthorized` when no refresh is possible.
    func refreshAccessToken(rejected: String) async throws -> String
}
