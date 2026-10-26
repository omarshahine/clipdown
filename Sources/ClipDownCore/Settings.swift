import Foundation

/// What a destination app should receive when you paste into it.
public enum OutputFormat: String, Codable, CaseIterable, Sendable {
    /// Formatted HTML next to the original text, for apps that render rich
    /// text on paste (Teams, Outlook, Slack, Mail).
    case richText
    /// Markdown source as the clipboard text, for apps that speak Markdown
    /// (Obsidian, Notion, GitHub, Bear).
    case markdown

    public var label: String {
        switch self {
        case .richText: "Rich text"
        case .markdown: "Markdown"
        }
    }
}

public struct TargetApp: Codable, Hashable, Identifiable, Sendable {
    public var bundleID: String
    public var name: String
    public var format: OutputFormat
    public var enabled: Bool

    public var id: String { bundleID }

    public init(bundleID: String, name: String, format: OutputFormat, enabled: Bool = true) {
        self.bundleID = bundleID
        self.name = name
        self.format = format
        self.enabled = enabled
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var enabled = true
    public var targets: [TargetApp] = [Settings.suggestions[0]]

    public init() {}

    public func target(for bundleID: String?) -> TargetApp? {
        guard enabled, let bundleID else { return nil }
        return targets.first { $0.bundleID == bundleID && $0.enabled }
    }

    /// Offered in the Add App menu. Formats are each app's best paste
    /// experience: rich text where the composer renders pasted HTML, Markdown
    /// where it formats pasted Markdown (Slack does both; Markdown keeps its
    /// own code formatting).
    public static let suggestions: [TargetApp] = [
        TargetApp(bundleID: "com.microsoft.teams2", name: "Microsoft Teams", format: .richText),
        TargetApp(bundleID: "com.microsoft.Outlook", name: "Microsoft Outlook", format: .richText),
        TargetApp(bundleID: "com.apple.mail", name: "Mail", format: .richText),
        TargetApp(bundleID: "com.apple.Notes", name: "Notes", format: .richText),
        TargetApp(bundleID: "com.microsoft.Word", name: "Microsoft Word", format: .richText),
        TargetApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", format: .markdown),
        TargetApp(bundleID: "com.hnc.Discord", name: "Discord", format: .markdown),
        TargetApp(bundleID: "md.obsidian", name: "Obsidian", format: .markdown),
        TargetApp(bundleID: "notion.id", name: "Notion", format: .markdown),
        TargetApp(bundleID: "net.shinyfrog.bear", name: "Bear", format: .markdown),
        TargetApp(bundleID: "com.linear", name: "Linear", format: .markdown),
        TargetApp(bundleID: "com.anthropic.claudefordesktop", name: "Claude", format: .markdown),
        TargetApp(bundleID: "com.openai.chat", name: "ChatGPT", format: .markdown),
    ]
}

/// Persists settings in the app's defaults domain, so the menu bar app, the
/// CLI and `defaults read com.omarshahine.clipdown` all see the same thing.
public enum SettingsStore {
    public static let domain = "com.omarshahine.clipdown"
    static let key = "settings"

    /// Tests point the store at a throwaway domain instead of real settings.
    nonisolated(unsafe) static var testDomain: String?

    static var defaults: UserDefaults {
        if let testDomain { return UserDefaults(suiteName: testDomain)! }
        // Inside the app bundle the domain is the standard one; from a bare
        // binary (swift run, a symlink on PATH) the suite points at it.
        return Bundle.main.bundleIdentifier == domain ? .standard : UserDefaults(suiteName: domain)!
    }

    public static func load() -> Settings {
        defaults.synchronize()
        guard let json = defaults.string(forKey: key), let data = json.data(using: .utf8),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return settings
    }

    public static func save(_ settings: Settings) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(String(decoding: data, as: UTF8.self), forKey: key)
        defaults.synchronize()
        DistributedNotificationCenter.default().postNotificationName(
            changedNotification, object: nil, deliverImmediately: true)
    }

    /// Loads, changes and saves under an exclusive lock shared by the app and
    /// the CLI, so two edits can't interleave and drop one another.
    @discardableResult
    public static func edit(_ change: (inout Settings) -> Void) -> Settings {
        let lockURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(testDomain ?? domain).lock")
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        if fd >= 0 { flock(fd, LOCK_EX) }
        defer { if fd >= 0 { flock(fd, LOCK_UN); close(fd) } }
        var settings = load()
        change(&settings)
        save(settings)
        return settings
    }

    /// Posted after every save so a running app picks up CLI edits.
    public static let changedNotification = Notification.Name("com.omarshahine.clipdown.settingsChanged")
}
