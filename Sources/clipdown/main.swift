import AppKit
import ClipDownCore

let usage = """
ClipDown keeps technical text formatted when you paste it.

usage: clipdown                          run the menu bar app
       clipdown targets                  list the apps ClipDown converts for
       clipdown add <bundle-id> [--markdown] [--name <name>]
       clipdown remove <bundle-id>
       clipdown enable | disable
       clipdown --dry-run                print the Markdown for stdin (or the clipboard)
       clipdown --html                   print the HTML for stdin (or the clipboard)
       clipdown --convert-now [--markdown]   convert the clipboard for the next paste

Find an app's bundle id with: osascript -e 'id of app "Slack"'
"""

func readInput() -> String {
    if isatty(STDIN_FILENO) == 0 {
        return String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    }
    return NSPasteboard.general.string(forType: .string) ?? ""
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(64)
}

func editSettings(_ change: (inout Settings) -> Void) {
    SettingsStore.edit(change)
}

/// The value after `flag`, failing if the flag is there without one.
func value(after flag: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: flag) else { return nil }
    guard args.indices.contains(i + 1), !args[i + 1].hasPrefix("--") else { fail("\(flag) needs a value") }
    return args[i + 1]
}

/// Drops what LaunchServices and Xcode add to an app launch: -psn_… and
/// Cocoa defaults overrides such as `-NSDocumentRevisionsDebugMode YES`.
func userArguments(_ raw: [String]) -> [String] {
    var out: [String] = []
    var i = 0
    while i < raw.count {
        let a = raw[i]
        if a.hasPrefix("-psn") {
            i += 1
        } else if a.hasPrefix("-NS") || a.hasPrefix("-Apple") {
            i += 2
        } else {
            out.append(a)
            i += 1
        }
    }
    return out
}

let args = userArguments(Array(CommandLine.arguments.dropFirst()))
switch args.first {
case nil:
    ClipDownApp.main()
case "targets":
    let settings = SettingsStore.load()
    print("ClipDown is \(settings.enabled ? "on" : "off")")
    for t in settings.targets {
        print("\(t.enabled ? "✓" : "–") \(t.name.padding(toLength: 22, withPad: " ", startingAt: 0)) \(t.format.label.padding(toLength: 10, withPad: " ", startingAt: 0)) \(t.bundleID)")
    }
case "add":
    guard args.count > 1, !args[1].hasPrefix("-") else { fail("usage: clipdown add <bundle-id> [--markdown] [--name <name>]") }
    let id = args[1]
    let known = Settings.suggestions.first { $0.bundleID == id }
    let appName = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
    let target = TargetApp(
        bundleID: id,
        name: value(after: "--name", in: args) ?? appName ?? known?.name ?? id,
        format: args.contains("--markdown") ? .markdown : args.contains("--rich-text") ? .richText : known?.format ?? .richText)
    editSettings { s in
        s.targets.removeAll { $0.bundleID == id }
        s.targets.append(target)
    }
    print("added \(target.name) as \(target.format.label)")
case "remove":
    guard args.count > 1 else { fail("usage: clipdown remove <bundle-id>") }
    editSettings { $0.targets.removeAll { $0.bundleID == args[1] } }
    print("removed \(args[1])")
case "enable", "disable":
    editSettings { $0.enabled = args[0] == "enable" }
    print("ClipDown is \(args[0] == "enable" ? "on" : "off")")
case "--dry-run":
    let result = Converter.convert(readInput())
    print(result.markdown)
    FileHandle.standardError.write(Data("signals: \(result.signals)\n".utf8))
case "--html":
    print(Renderer.htmlDocument(Converter.convert(readInput()).markdown))
case "--convert-now":
    let ok = ClipboardEngine().convertNow(as: args.contains("--markdown") ? .markdown : .richText)
    print(ok ? "converted" : "left alone")
case "--unregister-login-item":
    if let error = LoginItem.set(false) { fail("couldn't remove the login item: \(error)") }
case "-h", "--help", "help":
    print(usage)
default:
    fail(usage)
}
