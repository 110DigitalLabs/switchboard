import Foundation
import Testing
@testable import Switchboard

@MainActor
struct LinearAccountTests {
    func makeAccount(signedIn: Bool = true) -> (LinearAccount, FakeLinearConnector, FakeLinearService) {
        let service = FakeLinearService.sample()
        let connector = FakeLinearConnector(service: service, signedIn: signedIn)
        let account = LinearAccount(connector: connector, pollInterval: .seconds(3600), monitorNetwork: false)
        return (account, connector, service)
    }

    @Test func restoresStoredSignInAndLoadsOpenAssignedIssues() async {
        let (account, _, _) = makeAccount()
        await account.start()
        #expect(account.status == .signedIn(userName: "Ada Lovelace"))
        #expect(account.isConnected)
        #expect(account.assignedIssues.map(\.identifier) == ["ENG-101", "ENG-102"])
        #expect(account.teamKeys == ["ENG"])
        #expect(account.lastRefreshed != nil)
    }

    @Test func staysSignedOutWithoutCredentials() async {
        let (account, _, _) = makeAccount(signedIn: false)
        await account.start()
        #expect(account.status == .signedOut)
        #expect(account.service == nil)
    }

    @Test func signInAndSignOut() async {
        let (account, connector, _) = makeAccount(signedIn: false)
        await account.signIn()
        #expect(account.status == .signedIn(userName: "Ada Lovelace"))
        await account.signOut()
        #expect(account.status == .signedOut)
        #expect(account.assignedIssues.isEmpty)
        #expect(connector.signOutCount == 1)
    }

    @Test func signInFailureAndCancellation() async {
        let (account, connector, _) = makeAccount(signedIn: false)
        connector.signInError = OAuthError.cancelled
        await account.signIn()
        #expect(account.status == .signedOut)
        connector.signInError = OAuthError.discoveryFailed("x")
        await account.signIn()
        guard case .error = account.status else { Issue.record("expected error"); return }
    }

    @Test func pollErrorsKeepSignedInButAuthFailureSignsOut() async {
        let (account, _, service) = makeAccount()
        await account.start()
        await service.fail(next: .tool("boom"))
        await account.refreshNow()
        #expect(account.isConnected)
        #expect(account.pollError == "boom")
        await account.refreshNow()
        #expect(account.pollError == nil)

        await service.fail(next: .signedOut)
        await account.refreshNow()
        #expect(account.status == .signedOut)
        #expect(account.service == nil)
    }

    @Test func offlinePausesAndNetworkRecoveryResumes() async {
        let (account, _, service) = makeAccount()
        await account.start()
        await service.fail(next: .offline)
        await account.refreshNow()
        #expect(account.status == .offline)
        #expect(account.userName == "Ada Lovelace")
        await account.refreshNow()
        #expect(account.status == .signedIn(userName: "Ada Lovelace"))
    }

    @Test func backoffDoublesUpToCap() {
        let delays = (0...6).map {
            LinearAccount.backoffDelay(failures: $0, interval: .seconds(60), max: .seconds(600))
        }
        #expect(delays == [.seconds(60), .seconds(120), .seconds(240), .seconds(480),
                           .seconds(600), .seconds(600), .seconds(600)])
    }
}
