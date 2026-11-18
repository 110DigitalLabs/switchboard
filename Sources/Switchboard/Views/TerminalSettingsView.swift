import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Font, size, cursor and color theme for every terminal, with iTerm2
/// imports. Changes apply to open terminals at once.
struct TerminalSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var importMessage: String?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                ThemePreview(theme: settings.terminalTheme, appearance: settings.terminalAppearance)
                    .listRowInsets(EdgeInsets())
            }

            Section("Theme") {
                ThemeGrid(themes: settings.terminalThemes, selection: $settings.terminalAppearance.themeID,
                          onRemove: settings.removeImportedTheme)
                HStack {
                    Button("Import .itermcolors…") { importColorsFile() }
                    Button("Use iTerm2 Profile") { importITermProfile() }
                        .help("Copy the font and colors of iTerm2's default profile")
                    Spacer()
                }
                if let importMessage {
                    Text(importMessage).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Text") {
                Picker("Font", selection: $settings.terminalAppearance.fontName) {
                    Text("SF Mono (System)").tag(String?.none)
                    Divider()
                    ForEach(fontChoices) { Text($0.family).tag(Optional($0.postScriptName)) }
                }
                Stepper(value: $settings.terminalAppearance.fontSize, in: TerminalAppearance.fontSizes, step: 1) {
                    LabeledContent("Size", value: "\(Int(settings.terminalAppearance.fontSize)) pt")
                }
            }

            Section("Cursor") {
                Picker("Shape", selection: $settings.terminalAppearance.cursorShape) {
                    ForEach(TerminalAppearance.CursorShape.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Blink", isOn: $settings.terminalAppearance.cursorBlinks)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Installed fixed-pitch families, plus a saved font that is not among
    /// them (an iTerm2 font that is not fixed pitch, or since uninstalled).
    private var fontChoices: [MonospacedFonts.Choice] {
        var choices = MonospacedFonts.installed
        if let name = settings.terminalAppearance.fontName, !choices.contains(where: { $0.postScriptName == name }) {
            choices.insert(.init(postScriptName: name, family: NSFont(name: name, size: 12)?.familyName ?? name), at: 0)
        }
        return choices
    }

    private func importColorsFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "itermcolors") ?? .propertyList]
        panel.allowsMultipleSelection = true
        panel.prompt = "Import"
        guard panel.runModal() == .OK else { return }
        let themes = panel.urls.compactMap(TerminalTheme.init(iTermColorsFile:))
        themes.forEach(settings.importTheme)
        let failed = panel.urls.count - themes.count
        importMessage = failed == 0 ? nil : "\(failed) file(s) were not iTerm2 color presets."
    }

    private func importITermProfile() {
        guard let profile = ITermProfile.defaultProfile() else {
            importMessage = "No iTerm2 profile found."
            return
        }
        if let theme = profile.theme { settings.importTheme(theme) }
        if let name = profile.fontName, NSFont(name: name, size: 12) != nil {
            settings.terminalAppearance.fontName = name
        }
        if let size = profile.fontSize { settings.terminalAppearance.fontSize = TerminalAppearance.clamped(size) }
        importMessage = "Copied iTerm2's “\(profile.name)” profile."
    }
}

/// A sample of shell and agent output in the theme's colors and font.
private struct ThemePreview: View {
    let theme: TerminalTheme
    let appearance: TerminalAppearance

    var body: some View {
        let font = Font(appearance.font)
        let ansi = theme.ansi.map { Color(nsColor: $0.nsColor) }
        VStack(alignment: .leading, spacing: 2) {
            (Text("~/Projects/app").foregroundColor(ansi[4]) + Text(" on ").foregroundColor(foreground)
                + Text("main").foregroundColor(ansi[5]) + Text(" $ git status").foregroundColor(foreground))
            Text("modified:   Sources/App.swift").foregroundColor(ansi[1])
            Text("new file:   Tests/AppTests.swift").foregroundColor(ansi[2])
            (Text("● ").foregroundColor(foreground) + Text("Fixed the login bug in ").foregroundColor(foreground)
                + Text("Auth.swift").foregroundColor(ansi[12]))
            Text("  warning: 2 tests skipped").foregroundColor(ansi[3])
            Text("  Churned for 6s · done").foregroundColor(ansi[8])
            HStack(spacing: 0) {
                Text("❯ ").foregroundColor(foreground)
                Rectangle().fill(cursor).frame(width: cursorWidth, height: appearance.fontSize * 1.2)
            }
        }
        .font(font)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(background)
    }

    private var foreground: Color { Color(nsColor: theme.foreground?.nsColor ?? .textColor) }
    private var background: Color { Color(nsColor: theme.background?.nsColor ?? .textBackgroundColor) }
    private var cursor: Color { Color(nsColor: theme.cursor?.nsColor ?? .selectedControlColor) }
    private var cursorWidth: CGFloat {
        switch appearance.cursorShape {
        case .block: appearance.fontSize * 0.6
        case .bar, .underline: 2
        }
    }
}

/// Swatches for each theme: background, text, and six ANSI colors.
private struct ThemeGrid: View {
    let themes: [TerminalTheme]
    @Binding var selection: String
    let onRemove: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
            ForEach(themes) { theme in
                ThemeSwatch(theme: theme, isSelected: theme.id == selection)
                    .onTapGesture { selection = theme.id }
                    .contextMenu {
                        if theme.id.hasPrefix("imported:") {
                            Button("Remove “\(theme.name)”", role: .destructive) { onRemove(theme.id) }
                        }
                    }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ThemeSwatch: View {
    let theme: TerminalTheme
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Text("Aa").font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundColor(Color(nsColor: theme.foreground?.nsColor ?? .textColor))
                ForEach([1, 2, 3, 4, 5, 6], id: \.self) { index in
                    Circle().fill(Color(nsColor: theme.ansi[index].nsColor)).frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: theme.background?.nsColor ?? .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator))
            Text(theme.name).font(.caption).lineLimit(1).truncationMode(.tail)
        }
        .padding(4)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(theme.name)
    }
}
