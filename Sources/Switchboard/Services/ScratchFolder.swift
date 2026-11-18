import Foundation

enum ScratchFolder {
    static func name(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    /// Creates `<home>/scratch/<yyyyMMdd-HHmmss>`, suffixing on collision.
    static func create(in home: URL, at date: Date = Date()) throws -> URL {
        let parent = home.appendingPathComponent("scratch", isDirectory: true)
        let base = name(for: date)
        var candidate = parent.appendingPathComponent(base, isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(base)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        return candidate
    }
}
