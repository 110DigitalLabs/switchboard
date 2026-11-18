import Foundation
import Observation

/// The search box's text and its Linear lookup.
@MainActor
@Observable
final class TicketSearchModel {
    enum Results: Equatable {
        case idle
        case loading
        case issue(LinearIssue)
        case issues([LinearIssue])
        case failed(String)
    }

    var query = ""
    private(set) var results: Results = .idle

    var input: SearchInput { SearchInput.classify(query) }

    /// Looks up the current input, after a short pause for typing. Called
    /// from a view task keyed on the query, so a newer query cancels it.
    func search(using service: LinearService?) async {
        let input = input
        guard let service else {
            results = .idle
            return
        }
        switch input {
        case .empty, .pullRequest:
            results = .idle
            return
        case .ticket, .text:
            break
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        results = .loading
        let outcome: Results
        do {
            outcome = switch input {
            case .ticket(let id): .issue(try await service.issue(identifier: id))
            case .text(let text): .issues(try await service.searchIssues(query: text))
            case .empty, .pullRequest: .idle
            }
        } catch {
            outcome = .failed(LinearError(error).localizedDescription)
        }
        guard !Task.isCancelled, self.input == input else { return }
        results = outcome
    }

    /// The fetched issue for a ticket input, if it has arrived.
    func fetchedIssue(_ identifier: String) -> LinearIssue? {
        if case .issue(let issue) = results, issue.identifier == identifier { return issue }
        return nil
    }

    func clear() {
        query = ""
        results = .idle
    }
}
