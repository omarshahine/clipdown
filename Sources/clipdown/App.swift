import ClipDownCore
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel {
    static let shared = AppModel()
    let engine = ClipboardEngine()
    let updates = Updates()
    private var settingsWindow: NSWindow?
    private var conversions: AnyCancellable?

    init() {
        conversions = engine.$lastConversion.compactMap { $0 }.sink { _ in StarAsk.shared.recordConversion() }
    }

    /// `activate: false` shows the window without pulling focus from the app
    /// you're working in.
    func showSettings(activate: Bool = true) {
        if settingsWindow == nil {
            let tabs = SettingsTabs(engine: engine, updates: updates)
            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("Settings")
            settingsWindow = window
        }
        (settingsWindow?.contentViewController as? SettingsTabs)?.selectSavedTab()
        guard activate else {
            settingsWindow?.orderFrontRegardless()
            return
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
        // Don't let the Preview editor grab keystrokes meant for another app.
        settingsWindow?.makeFirstResponder(nil)
    }
}

/// The GitHub star ask: a button that's always in the menu and Settings, plus
/// a one-time note in Settings > General after a few conversions. Stars
/// in place through the GitHub CLI when it's signed in, like Orca does, and
/// opens the repo in the browser otherwise.
@MainActor
final class StarAsk: ObservableObject {
    static let shared = StarAsk()
    static let repo = "omarshahine/clipdown"
    static let url = URL(string: "https://github.com/\(repo)")!
    /// Conversions before the one-time ask.
    static let threshold = 5
    static let countKey = "conversionCount"
    static let askedKey = "starAsked"
    /// Set while the note is showing in Settings > General.
    static let pendingKey = "starAskPending"

    @Published private(set) var starred = false

    func refresh() async {
        starred = await GitHubCLI.run(["api", "user/starred/\(Self.repo)"]) == 0
    }

    func recordConversion() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.askedKey) else { return }
        let count = defaults.integer(forKey: Self.countKey) + 1
        defaults.set(count, forKey: Self.countKey)
        guard count >= Self.threshold else { return }
        defaults.set(true, forKey: Self.askedKey)
        Task {
            // Already a stargazer: nothing to ask.
            await refresh()
            guard !starred else { return }
            defaults.set(true, forKey: Self.pendingKey)
            defaults.set("general", forKey: SettingsTabs.tabKey)
            AppModel.shared.showSettings(activate: false)
        }
    }

    func star() {
        let defaults = UserDefaults.standard
        // Starred already, or chose to: never ask.
        defaults.set(true, forKey: Self.askedKey)
        defaults.set(false, forKey: Self.pendingKey)
        Task {
            if await GitHubCLI.run(["api", "-X", "PUT", "user/starred/\(Self.repo)"]) == 0 {
                starred = true
            } else {
                NSWorkspace.shared.open(Self.url)
            }
        }
    }
}

/// The GitHub CLI, if it's installed where Homebrew puts it. Apps launched
/// from Finder don't get the shell's PATH, so look in the usual places.
enum GitHubCLI {
    static let path = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// Runs gh and returns its exit status, or nil when gh is missing or
    /// takes longer than 15 seconds.
    static func run(_ arguments: [String]) async -> Int32? {
        guard let path else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationReason == .exit ? $0.terminationStatus : nil) }
            do { try process.run() } catch {
                process.terminationHandler = nil
                continuation.resume(returning: nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
                if process.isRunning { process.terminate() }
            }
        }
    }
}

enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static var isEnabled: Bool { status == .enabled }

    /// Returns nil on success, or what went wrong for display.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            log.error("login item \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppModel.shared.engine.start()
            // First run: start at login by default and show what ClipDown does.
            let defaults = UserDefaults.standard
            if !defaults.bool(forKey: "launchedBefore") {
                defaults.set(true, forKey: "launchedBefore")
                LoginItem.set(true)
                AppModel.shared.showSettings()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.engine.restoreOriginal() }
    }

    /// Opening the app again (Finder, Spotlight, `open -a ClipDown`) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { AppModel.shared.showSettings() }
        return true
    }
}

struct ClipDownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var engine = AppModel.shared.engine

    var body: some Scene {
        MenuBarExtra {
            MenuContent().environmentObject(engine)
        } label: {
            Image(nsImage: MenuBarIcon.image(enabled: engine.settings.enabled))
        }
    }
}

enum MenuBarIcon {
    /// The template glyph from the bundle, falling back to an SF Symbol.
    static func image(enabled: Bool) -> NSImage {
        let image = Bundle.main.image(forResource: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "ClipDown")!
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        guard !enabled else { return image }
        // Dim the glyph when ClipDown is switched off.
        let dimmed = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.35)
            return true
        }
        dimmed.isTemplate = true
        return dimmed
    }
}

struct MenuContent: View {
    @EnvironmentObject private var engine: ClipboardEngine
    @ObservedObject private var stars = StarAsk.shared

    var body: some View {
        Toggle("ClipDown Is On", isOn: Binding(
            get: { engine.settings.enabled },
            set: { on in engine.update { $0.enabled = on } }))

        let active = engine.settings.targets.filter(\.enabled)
        Text(active.isEmpty ? "No apps selected" : "Watching " + active.map(\.name).joined(separator: ", "))
        if let last = engine.lastConversion {
            Text("Last: \(last.format.label) for \(last.appName), \(last.date.formatted(.relative(presentation: .named)))")
        }

        Divider()
        Menu("Convert Clipboard Now") {
            ForEach(OutputFormat.allCases, id: \.self) { format in
                Button("As \(format.label)") {
                    if !engine.convertNow(as: format) { NSSound.beep() }
                }
            }
        }
        if AppModel.shared.updates.isAvailable {
            Button("Check for Updates…") { AppModel.shared.updates.checkForUpdates() }
        }
        Button("Settings…") { AppModel.shared.showSettings() }
            .keyboardShortcut(",")
        if !stars.starred {
            Button("Star ClipDown on GitHub") { stars.star() }
        }
        Divider()
        Button("Quit ClipDown") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
