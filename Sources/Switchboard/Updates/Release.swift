import Foundation

/// A dotted numeric version such as "0.1.2", compared component by component.
struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    let components: [Int]

    /// Accepts "1.2.3" and tags such as "v1.2.3"; nil for anything else.
    init?(_ text: String) {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        guard !parts.isEmpty, numbers.count == parts.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        components = numbers
    }

    var description: String { components.map(String.init).joined(separator: ".") }

    /// The running app's CFBundleShortVersionString.
    static var running: AppVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    }

    /// The version of the app bundle on disk, read fresh (Bundle caches it).
    static func installed(at appURL: URL) -> AppVersion? {
        let plist = appURL.appendingPathComponent("Contents/Info.plist")
        let info = NSDictionary(contentsOf: plist)
        return (info?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }

    func hash(into hasher: inout Hasher) {
        var trimmed = components
        while trimmed.last == 0 { trimmed.removeLast() }
        hasher.combine(trimmed)
    }
}

/// A published Switchboard release.
struct Release: Equatable, Sendable {
    let version: AppVersion
    let pageURL: URL
    /// The notarized Switchboard-<version>.zip, when the release has one.
    let zipURL: URL?

    static let latestURL = URL(string: "https://api.github.com/repos/110DigitalLabs/switchboard/releases/latest")!

    /// Parses GitHub's "latest release" JSON; drafts and prereleases are nil.
    static func parse(gitHubJSON data: Data) -> Release? {
        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let html_url: URL
            let draft: Bool?
            let prerelease: Bool?
            let assets: [Asset]?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.draft != true, payload.prerelease != true,
              let version = AppVersion(payload.tag_name) else { return nil }
        let zip = payload.assets?.first { $0.name == "Switchboard-\(version).zip" }
            ?? payload.assets?.first { $0.name.hasPrefix("Switchboard") && $0.name.hasSuffix(".zip") }
        return Release(version: version, pageURL: payload.html_url, zipURL: zip?.browser_download_url)
    }

    /// Asks GitHub for the latest release.
    static func fetchLatest() async throws -> Release {
        var request = URLRequest(url: latestURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Switchboard", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let release = parse(gitHubJSON: data) else {
            throw UpdateError("Couldn't read the latest release from GitHub.")
        }
        return release
    }
}

struct UpdateError: LocalizedError, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
