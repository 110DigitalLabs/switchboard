import Foundation
import Testing
@testable import Switchboard

@MainActor
struct TicketFolderTests {
    @Test func createsFolderWithTicketMarkdown() throws {
        let home = TicketTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let issue = TicketTestSupport.issue("ENG-42", title: "Make it fast", description: "Profile first.\n\nThen fix.")
        let folder = try TicketFolder.create(for: issue, in: home)
        #expect(folder.path == home.appendingPathComponent("tickets/ENG-42").path)
        let text = try String(contentsOf: folder.appendingPathComponent("TICKET.md"), encoding: .utf8)
        #expect(text.hasPrefix("# ENG-42: Make it fast\n"))
        #expect(text.contains("Linear: https://linear.app/acme/issue/ENG-42"))
        #expect(text.contains("Project: Switchboard"))
        #expect(text.contains("Status: Todo"))
        #expect(text.contains("Profile first.\n\nThen fix."))
    }

    @Test func missingDescriptionIsSaid() {
        let text = TicketFolder.markdown(for: TicketTestSupport.issue("ENG-1", description: "  "))
        #expect(text.contains("_No description._"))
    }

    @Test func recreatingRewritesTheTicket() throws {
        let home = TicketTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        try TicketFolder.create(for: TicketTestSupport.issue("ENG-1", title: "Old"), in: home)
        let folder = try TicketFolder.create(for: TicketTestSupport.issue("ENG-1", title: "New"), in: home)
        let text = try String(contentsOf: folder.appendingPathComponent("TICKET.md"), encoding: .utf8)
        #expect(text.hasPrefix("# ENG-1: New"))
    }

    @Test func storeStartsTempPlanningSession() throws {
        let home = TicketTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let store = TicketTestSupport.store(home: home)
        store.startTicketSession(TicketTestSupport.issue("ENG-7", title: "Plan me"), destination: .tempFolder,
                                 agent: .claudeCode, startTerminal: false)
        let session = try #require(store.sessions.first)
        #expect(session.kind == .temp)
        #expect(session.folderPath == home.appendingPathComponent("tickets/ENG-7").path)
        #expect(session.ticketID == "ENG-7" && session.ticketTitle == "Plan me")
        #expect(FileManager.default.fileExists(atPath: session.folderPath + "/TICKET.md"))

        store.addSibling(of: session.id, startTerminal: false)
        #expect(store.sessions.count == 2)
        #expect(store.sessions[1].kind == .temp && store.sessions[1].folderPath == session.folderPath)
    }

    @Test func planningLaunchUsesPlanModeAndDraft() {
        var session = TicketTestSupport.session(.temp, path: "/home/tickets/ENG-7", ticket: "ENG-7")
        session.ticketTitle = "Plan me"
        let launch = SessionLaunch.fresh(session, hooks: nil, options: AgentLaunchOptions(planMode: true),
                                         draft: TicketPrompts.draft(for: session))
        #expect(launch.command == "claude --permission-mode plan")
        #expect(launch.draft == "Let's plan ENG-7 (Plan me). The ticket is in TICKET.md. ")
        #expect(launch.directory == "/home/tickets/ENG-7")
    }
}
