import Foundation
import Testing
@testable import Switchboard

struct TerminalAppearanceTests {
    private func component(_ red: Double, _ green: Double, _ blue: Double) -> [String: Any] {
        ["Red Component": red, "Green Component": green, "Blue Component": blue, "Color Space": "sRGB"]
    }

    private func iTermColors(ansiCount: Int = 16) -> [String: Any] {
        var plist: [String: Any] = [
            "Foreground Color": component(0.9, 0.9, 0.9),
            "Background Color": component(0.1, 0.1, 0.1),
            "Cursor Color": component(1, 1, 1),
        ]
        for index in 0..<ansiCount { plist["Ansi \(index) Color"] = component(Double(index) / 15, 0, 0) }
        return plist
    }

    @Test func builtInThemesHaveSixteenColorsAndUniqueIDs() {
        #expect(TerminalTheme.builtIn.allSatisfy { $0.ansi.count == 16 })
        #expect(Set(TerminalTheme.builtIn.map(\.id)).count == TerminalTheme.builtIn.count)
        #expect(TerminalTheme.builtIn.first?.id == TerminalTheme.systemID)
    }

    @Test func readsITermColors() throws {
        let theme = try #require(TerminalTheme(iTermColors: iTermColors(), id: "imported:x", name: "X"))
        #expect(theme.ansi.count == 16)
        #expect(theme.ansi[15].red == 1)
        #expect(theme.foreground == .init(red: 0.9, green: 0.9, blue: 0.9))
        #expect(theme.selection == nil)
        #expect(theme.isDark)
        #expect(TerminalTheme(iTermColors: iTermColors(ansiCount: 15), id: "x", name: "X") == nil)
    }

    @Test func readsAnITermColorsFileNamedAfterIt() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Night Owl \(UUID()).itermcolors")
        try PropertyListSerialization.data(fromPropertyList: iTermColors(), format: .xml, options: 0).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let theme = try #require(TerminalTheme(iTermColorsFile: url))
        #expect(theme.name.hasPrefix("Night Owl"))
        #expect(theme.id == "imported:\(theme.name)")
    }

    @Test func readsTheITermDefaultProfile() throws {
        let suite = "switchboard-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var chosen = iTermColors()
        chosen["Guid"] = "B"
        chosen["Name"] = "Work"
        chosen["Normal Font"] = "JetBrainsMono-Regular 14"
        defaults.set([["Guid": "A", "Name": "Other", "Normal Font": "Menlo-Regular 11"], chosen],
                     forKey: "New Bookmarks")
        defaults.set("B", forKey: "Default Bookmark Guid")

        let profile = try #require(ITermProfile.defaultProfile(defaults: defaults))
        #expect(profile.name == "Work")
        #expect(profile.fontName == "JetBrainsMono-Regular")
        #expect(profile.fontSize == 14)
        #expect(profile.theme?.name == "iTerm2 – Work")
    }

    @Test func parsesITermFontStrings() {
        #expect(ITermProfile.font("Monaco 12") == ("Monaco", 12))
        #expect(ITermProfile.font("Fira Code 13.5") == ("Fira Code", 13.5))
        #expect(ITermProfile.font("Monaco") == (nil, nil))
        #expect(ITermProfile.font(nil) == (nil, nil))
    }

    @Test func sizesStayInRange() {
        var appearance = TerminalAppearance()
        appearance.fontSize = 36
        #expect(appearance.resized(by: 1).fontSize == 36)
        appearance.fontSize = 8
        #expect(appearance.resized(by: -1).fontSize == 8)
        #expect(TerminalAppearance().resized(by: 1).fontSize == 14)
    }

    @Test func decodesOldOrPartialSettings() throws {
        let decoded = try JSONDecoder().decode(TerminalAppearance.self,
                                               from: Data(#"{"fontSize":200,"cursorShape":"zigzag"}"#.utf8))
        #expect(decoded.fontSize == 36)
        #expect(decoded.cursorShape == .block)
        #expect(decoded.themeID == TerminalTheme.systemID)
        #expect(decoded.fontName == nil)
    }

    @Test @MainActor func settingsPersistImportsAndFallBackWhenRemoved() throws {
        let suite = "switchboard-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let theme = try #require(TerminalTheme(iTermColors: iTermColors(), id: "imported:x", name: "X"))

        let settings = AppSettings(defaults: defaults)
        #expect(settings.terminalTheme.id == TerminalTheme.systemID)
        settings.importTheme(theme)
        settings.terminalAppearance.fontSize = 16

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.terminalTheme == theme)
        #expect(reloaded.terminalAppearance.fontSize == 16)

        reloaded.removeImportedTheme("imported:x")
        #expect(reloaded.terminalTheme.id == TerminalTheme.systemID)
        #expect(AppSettings(defaults: defaults).importedThemes.isEmpty)
    }
}
