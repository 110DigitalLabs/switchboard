import Foundation

enum MCPError: Error, Equatable, LocalizedError {
    /// The server rejected the credentials even after a refresh.
    case unauthorized
    case http(status: Int)
    case rpc(code: Int, message: String)
    /// The response finished without a reply to our request.
    case noResponse
    case malformedResponse(String)
    /// The session expired (HTTP 404 with a session ID).
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Not signed in"
        case .http(let status): "Server returned HTTP \(status)"
        case .rpc(_, let message): message
        case .noResponse: "The server sent no response"
        case .malformedResponse(let detail): "Unexpected server response: \(detail)"
        case .sessionExpired: "The server session expired"
        }
    }
}
