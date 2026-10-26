import ClipDownCore
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel {
    static let shared = AppModel()
    let engine = ClipboardEngine()
    let updates = Updates()
    private var settingsWindow: NSWindow?

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: SettingsView().environmentObject(engine).environmentObject(updates)))
            window.title = "ClipDown"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("Settings")
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
        // Don't let the Preview editor grab keystrokes meant for another app.
        settingsWindow?.makeFirstResponder(nil)
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
        Divider()
        Button("Quit ClipDown") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
