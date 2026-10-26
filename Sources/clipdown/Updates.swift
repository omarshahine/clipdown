import AppKit
import Sparkle

/// Sparkle, only when running as a real app bundle with a feed configured.
/// `swift run`, the CLI and tests never start an updater.
@MainActor
final class Updates: ObservableObject {
    private let controller: SPUStandardUpdaterController?

    init() {
        let bundled = Bundle.main.bundleURL.pathExtension == "app"
            && Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        controller = bundled
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
    }

    var isAvailable: Bool { controller != nil }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }
}
