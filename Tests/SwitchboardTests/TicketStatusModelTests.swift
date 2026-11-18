import Foundation
import Testing
@testable import Switchboard

@MainActor
struct TicketStatusModelTests {
    private func service() -> FakeLinearService { FakeLinearService.sample() }

    @Test func loadsIssueAndTeamStates() async {
        let model = TicketStatusModel()
        await model.load("eng-101", service: service())
        #expect(model.issue("ENG-101")?.state?.name == "In Progress")
        #expect(model.states(for: "ENG-101").map(\.name) == ["Todo", "In Progress", "Done"])
        let current = model.states(for: "ENG-101").filter { model.isCurrent($0, for: "ENG-101") }
        #expect(current.map(\.name) == ["In Progress"])
    }

    @Test func pickingAStateSetsItThenRefreshes() async throws {
        let linear = service()
        let model = TicketStatusModel()
        await model.load("ENG-101", service: linear)
        let done = try #require(model.states(for: "ENG-101").first { $0.name == "Done" })
        await model.setState(done, for: "ENG-101", service: linear)
        #expect(model.issue("ENG-101")?.state?.name == "Done")
        #expect(try await linear.issue(identifier: "ENG-101").state?.id == done.id)
        #expect(model.updating == nil && model.errorMessage == nil)
    }

    @Test func statesAreCachedPerTeam() async {
        let linear = service()
        let model = TicketStatusModel()
        await model.load("ENG-101", service: linear)
        await model.load("ENG-102", service: linear)
        await model.load("ENG-101", service: linear)
        #expect(model.states(for: "ENG-102").count == 3)
        #expect(await linear.stateFetches == 1)
    }

    @Test func failuresAreReportedNotThrown() async throws {
        let linear = service()
        let model = TicketStatusModel()
        await model.load("ENG-101", service: linear)
        let todo = try #require(model.states(for: "ENG-101").first)
        await linear.fail(next: .offline)
        await model.setState(todo, for: "ENG-101", service: linear)
        #expect(model.errorMessage == LinearError.offline.localizedDescription)
        #expect(model.issue("ENG-101")?.state?.name == "In Progress")
    }
}
