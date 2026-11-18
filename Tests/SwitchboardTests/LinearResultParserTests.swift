import Foundation
import Testing
@testable import Switchboard

struct LinearResultParserTests {
    @Test func parsesFlattenedIssueList() throws {
        let issues = LinearResultParser.issues(LinearFixtures.json(LinearFixtures.listIssues))
        #expect(issues.map(\.identifier) == ["ENG-123", "ENG-99"])
        let issue = issues[0]
        #expect(issue.id == "9c1e-1")
        #expect(issue.title == "Fix login")
        #expect(issue.description == "Steps…")
        #expect(issue.url?.absoluteString == "https://linear.app/acme/issue/ENG-123/fix-login")
        #expect(issue.state == LinearWorkflowState(id: nil, name: "In Progress", type: .unknown))
        #expect(issue.team == LinearTeamRef(id: "t1", key: "ENG", name: "Engineering"))
        #expect(issue.projectName == "Switchboard")
        #expect(issue.assignee == LinearUser(id: "u1", name: "Ada Lovelace", email: nil))
        #expect(issues[1].description == nil)
        #expect(issues[1].projectName == nil)
    }

    @Test func parsesNestedIssue() throws {
        let issue = try #require(LinearResultParser.singleIssue(LinearFixtures.json(LinearFixtures.getIssue)))
        #expect(issue.identifier == "OPS-7")
        #expect(issue.state == LinearWorkflowState(id: "o2", name: "Todo", type: .unstarted))
        #expect(issue.team == LinearTeamRef(id: "t2", key: "OPS", name: "Operations"))
        #expect(issue.projectName == "Security")
        #expect(issue.assignee?.email == "grace@example.com")
        #expect(issue.description == nil)
    }

    @Test func acceptsBareArraysAndGraphQLStyleWrappers() {
        let bare = LinearFixtures.json(#"[{"id":"a","identifier":"eng-1","title":"x"}]"#)
        #expect(LinearResultParser.issues(bare).map(\.identifier) == ["ENG-1"])
        let nested = LinearFixtures.json(#"{"data":{"issues":{"nodes":[{"id":"a","identifier":"ENG-2"}]}}}"#)
        #expect(LinearResultParser.issues(nested).map(\.identifier) == ["ENG-2"])
        let urlOnly = LinearFixtures.json(#"[{"id":"a","url":"https://linear.app/x/issue/ENG-3/y"}]"#)
        #expect(LinearResultParser.issues(urlOnly).map(\.identifier) == ["ENG-3"])
        #expect(LinearResultParser.issues(LinearFixtures.json(#"[{"title":"no id"}]"#)).isEmpty)
    }

    @Test func sortsStatesByCategory() {
        let states = LinearResultParser.workflowStates(LinearFixtures.json(LinearFixtures.statuses))
        #expect(states.map(\.name) == ["Backlog", "Todo", "In Progress", "Done", "Canceled"])
        #expect(states[2] == LinearWorkflowState(id: "s3", name: "In Progress", type: .started))
    }

    @Test func parsesTeamsAndUser() {
        let teams = LinearResultParser.teams(LinearFixtures.json(LinearFixtures.teams))
        #expect(teams == [LinearTeam(id: "t1", key: "ENG", name: "Engineering"),
                          LinearTeam(id: "t2", key: "OPS", name: "Operations")])
        #expect(LinearResultParser.user(LinearFixtures.json(LinearFixtures.user))
            == LinearUser(id: "u1", name: "Ada Lovelace", email: "ada@example.com"))
    }
}
