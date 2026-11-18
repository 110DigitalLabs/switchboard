import Foundation

/// Planning folders for tickets started without a repo: `<home>/tickets/<ID>`
/// holding the ticket as TICKET.md.
enum TicketFolder {
    static let ticketFileName = "TICKET.md"

    static func url(for identifier: String, in home: URL) -> URL {
        home.appendingPathComponent("tickets", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
    }

    /// Creates (or reuses) the folder and writes the ticket into it.
    @discardableResult
    static func create(for issue: LinearIssue, in home: URL) throws -> URL {
        let folder = url(for: issue.identifier, in: home)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try markdown(for: issue).write(to: folder.appendingPathComponent(ticketFileName),
                                       atomically: true, encoding: .utf8)
        return folder
    }

    static func markdown(for issue: LinearIssue) -> String {
        var lines = ["# \(issue.identifier): \(issue.title)", ""]
        if let url = issue.url { lines.append("Linear: \(url.absoluteString)") }
        if let project = issue.projectName { lines.append("Project: \(project)") }
        if let state = issue.state?.name { lines.append("Status: \(state)") }
        lines.append("")
        let description = issue.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        lines.append(description.isEmpty ? "_No description._" : description)
        return lines.joined(separator: "\n") + "\n"
    }
}
