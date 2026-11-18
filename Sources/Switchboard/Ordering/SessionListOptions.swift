import Foundation

enum SessionSort: String, CaseIterable, Identifiable, Sendable {
    case ticket
    case folder

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ticket: "Ticket"
        case .folder: "Folder"
        }
    }
}

enum SessionGrouping: String, CaseIterable, Identifiable, Sendable {
    case none
    case project
    case folder
    case ticket

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "None"
        case .project: "Linear Project"
        case .folder: "Folder"
        case .ticket: "Ticket"
        }
    }
}
