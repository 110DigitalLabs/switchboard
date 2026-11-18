import Foundation
import Testing
@testable import Switchboard

@MainActor
struct BrowserWebAuthenticatorTests {
    private let page = URL(string: "https://linear.app/oauth/authorize?x=1")!

    @Test func opensThePageAndReturnsTheMatchingRedirect() async throws {
        var opened: [URL] = []
        let authenticator = BrowserWebAuthenticator(openURL: { opened.append($0); return true })
        async let callback = authenticator.authenticate(url: page, callbackScheme: "switchboard")
        await Task.yield()
        #expect(opened == [page])
        #expect(!authenticator.receive(URL(string: "other://oauth/callback?code=no")!))
        #expect(authenticator.receive(URL(string: "Switchboard://oauth/callback?code=c&state=s")!))
        #expect(try await callback.absoluteString == "Switchboard://oauth/callback?code=c&state=s")
        #expect(!authenticator.receive(URL(string: "switchboard://oauth/callback?code=late")!))
    }

    @Test func cancelEndsTheWait() async {
        let authenticator = BrowserWebAuthenticator(openURL: { _ in true })
        let callback = Task { try await authenticator.authenticate(url: page, callbackScheme: "switchboard") }
        await Task.yield()
        authenticator.cancel()
        await #expect(throws: OAuthError.cancelled) { try await callback.value }
    }

    @Test func failsWhenTheBrowserCannotOpen() async {
        let authenticator = BrowserWebAuthenticator(openURL: { _ in false })
        await #expect(throws: OAuthError.self) {
            try await authenticator.authenticate(url: page, callbackScheme: "switchboard")
        }
    }
}
