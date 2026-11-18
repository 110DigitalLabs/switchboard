import Foundation

enum TicketSuffixes {
    /// Display labels for each session's ticket. A ticket with one session
    /// shows its plain ID; several sessions on one ticket become XYZ-123-A,
    /// -B, -C … in creation order. Sessions without a ticket are absent.
    static func labels(for sessions: [Session]) -> [UUID: String] {
        var labels: [UUID: String] = [:]
        let byTicket = Dictionary(grouping: sessions.filter { $0.ticketID != nil }) { $0.ticketID! }
        for (ticket, group) in byTicket {
            guard group.count > 1 else {
                labels[group[0].id] = ticket
                continue
            }
            let ordered = group.sorted {
                ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
            }
            for (index, session) in ordered.enumerated() {
                labels[session.id] = "\(ticket)-\(letters(index))"
            }
        }
        return labels
    }

    /// 0 → A, 25 → Z, 26 → AA, 27 → AB …
    static func letters(_ index: Int) -> String {
        var n = index + 1
        var result = ""
        while n > 0 {
            n -= 1
            result = String(UnicodeScalar(UInt8(65 + n % 26))) + result
            n /= 26
        }
        return result
    }
}
