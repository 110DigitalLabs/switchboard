import AppKit

/// Shows an authorization page and returns the redirect URL.
@MainActor
protocol WebAuthenticating {
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
    func cancel()
}

/// Opens the authorization page in the user's default browser and waits for
/// the custom-scheme redirect, which macOS delivers to the app as a URL event
/// (the scheme is declared in Info.plist).
///
/// ASWebAuthenticationSession is not used: on macOS it shows Safari unless the
/// default browser implements Apple's web-authentication API, which Chrome and
/// Firefox do not. A redirect anyone could forge is harmless here, because the
/// caller checks the OAuth `state` and the code is useless without the PKCE
/// verifier.
@MainActor
final class BrowserWebAuthenticator: NSObject, WebAuthenticating {
    private struct Pending {
        let scheme: String
        let continuation: CheckedContinuation<URL, Error>
    }

    private var pending: Pending?
    private var handlerInstalled = false
    private let openURL: (URL) -> Bool

    init(openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.openURL = openURL
    }

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        cancel()
        installURLHandler()
        return try await withCheckedThrowingContinuation { continuation in
            pending = Pending(scheme: callbackScheme.lowercased(), continuation: continuation)
            if !openURL(url) {
                finish(.failure(OAuthError.invalidCallback("could not open the sign-in page")))
            }
        }
    }

    func cancel() {
        finish(.failure(OAuthError.cancelled))
    }

    /// Completes a waiting sign-in with `url` when it uses the expected
    /// scheme. Returns whether it was taken.
    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard let pending, url.scheme?.lowercased() == pending.scheme else { return false }
        finish(.success(url))
        NSApp?.activate()
        return true
    }

    private func finish(_ result: Result<URL, Error>) {
        guard let pending else { return }
        self.pending = nil
        pending.continuation.resume(with: result)
    }

    /// Installed on first use rather than at launch so it replaces SwiftUI's
    /// own URL handler, which would otherwise swallow the event.
    private func installURLHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string) else { return }
        receive(url)
    }
}
