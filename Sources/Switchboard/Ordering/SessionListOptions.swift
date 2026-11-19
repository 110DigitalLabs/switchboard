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

/// The sidebar's Tickets | Folders switch.
enum SessionGrouping: String, CaseIterable, Identifiable, Sendable {
    case ticket
    case folder

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ticket: "Tickets"
        case .folder: "Folders"
        }
    }
}

/// The session list's share of the window width when the window opens.
enum SidebarWidth: String, CaseIterable, Identifiable, Sendable {
    case quarter
    case third
    case half

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quarter: "One quarter"
        case .third: "One third"
        case .half: "One half"
        }
    }

    var fraction: Double {
        switch self {
        case .quarter: 1.0 / 4
        case .third: 1.0 / 3
        case .half: 1.0 / 2
        }
    }
}

/// Text size of the session list rows. Small is the system sidebar size.
enum SessionListTextSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// Point size of a row's title.
    var titleSize: Double {
        switch self {
        case .small: 13
        case .medium: 15
        case .large: 17
        }
    }

    /// Point size of a row's secondary lines.
    var detailSize: Double {
        switch self {
        case .small: 10
        case .medium: 12
        case .large: 14
        }
    }
}
