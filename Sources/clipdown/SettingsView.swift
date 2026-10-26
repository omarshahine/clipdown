import ClipDownCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage("settingsTab") private var tab = "apps"

    var body: some View {
        TabView(selection: $tab) {
            AppsTab().tabItem { Label("Apps", systemImage: "square.grid.2x2") }.tag("apps")
            PreviewTab().tabItem { Label("Preview", systemImage: "eye") }.tag("preview")
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }.tag("general")
        }
        .frame(width: 620, height: 480)
    }
}

// MARK: - Apps

struct AppsTab: View {
    @EnvironmentObject private var engine: ClipboardEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("When one of these apps is in front, ClipDown reshapes plain technical text on the clipboard for it. Every other app gets your original text.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                if engine.settings.targets.isEmpty {
                    Text("No apps yet. Add one below.").foregroundStyle(.secondary)
                }
                ForEach(engine.settings.targets) { target in
                    TargetRow(target: target)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))

            HStack {
                AddAppMenu()
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Label("**Rich text** pastes real inline code, code blocks, lists and headings. Best for Teams, Outlook, Mail and Notes.", systemImage: "textformat")
                Label("**Markdown** pastes Markdown source. Best for Slack, Obsidian, Notion and Discord.", systemImage: "number")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

struct TargetRow: View {
    @EnvironmentObject private var engine: ClipboardEngine
    let target: TargetApp

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppInfo.icon(for: target.bundleID))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(target.name)
                Text(target.bundleID).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Format", selection: binding(\.format)) {
                ForEach(OutputFormat.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)
            Toggle("Enabled", isOn: binding(\.enabled))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            Button {
                engine.update { $0.targets.removeAll { $0.bundleID == target.bundleID } }
            } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove \(target.name)")
        }
        .padding(.vertical, 4)
        .opacity(target.enabled ? 1 : 0.55)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<TargetApp, Value>) -> Binding<Value> {
        Binding(
            get: { target[keyPath: keyPath] },
            set: { value in
                engine.update { settings in
                    guard let i = settings.targets.firstIndex(where: { $0.bundleID == target.bundleID }) else { return }
                    settings.targets[i][keyPath: keyPath] = value
                }
            })
    }
}

struct AddAppMenu: View {
    @EnvironmentObject private var engine: ClipboardEngine

    var body: some View {
        let existing = Set(engine.settings.targets.map(\.bundleID))
        let suggestions = Settings.suggestions.filter { !existing.contains($0.bundleID) && AppInfo.isInstalled($0.bundleID) }
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> TargetApp? in
                guard let id = app.bundleIdentifier, !existing.contains(id), id != Bundle.main.bundleIdentifier,
                      !suggestions.contains(where: { $0.bundleID == id }) else { return nil }
                return TargetApp(bundleID: id, name: app.localizedName ?? id, format: .richText)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        Menu {
            if !suggestions.isEmpty {
                Section("Suggested") {
                    ForEach(suggestions) { app in
                        Button("\(app.name) (\(app.format.label))") { add(app) }
                    }
                }
            }
            if !running.isEmpty {
                Section("Running") {
                    ForEach(running) { app in Button(app.name) { add(app) } }
                }
            }
            Divider()
            Button("Choose an App…", action: choose)
        } label: {
            Label("Add App", systemImage: "plus")
        }
        .fixedSize()
    }

    private func add(_ app: TargetApp) {
        engine.update { $0.targets.append(app) }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        guard !engine.settings.targets.contains(where: { $0.bundleID == id }) else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        let format = Settings.suggestions.first { $0.bundleID == id }?.format ?? .richText
        add(TargetApp(bundleID: id, name: name, format: format))
    }
}

enum AppInfo {
    static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    static func icon(for bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }
}

// MARK: - Preview

struct PreviewTab: View {
    enum Mode: String, CaseIterable { case rendered = "Rendered", markdown = "Markdown", html = "HTML" }

    @State private var input = PreviewTab.sample
    @State private var mode = Mode.rendered

    var body: some View {
        // The same decision the clipboard gets, so the preview never shows a
        // conversion that wouldn't happen (and never converts a huge clip).
        let verdict = Policy.verdict(for: input)
        let markdown: String? = if case .convert(let md, _) = verdict { md } else { nil }

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Paste anything to see what ClipDown would do with it.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Paste Clipboard") {
                    let pb = NSPasteboard.general
                    input = pb.string(forType: .init(Policy.markerType)) ?? pb.string(forType: .string) ?? ""
                }
                Button("Sample") { input = PreviewTab.sample }
            }

            CodeEditor(text: $input)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(height: 140)

            HStack {
                Picker("Show", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                if case .convert(_, let signals) = verdict {
                    Label("Converts (\(signals) signals)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label(verdict.reason, systemImage: "minus.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)

            ScrollView {
                Group {
                    switch mode {
                    case .rendered:
                        if let markdown {
                            Text(PreviewTab.rendered(Renderer.htmlDocument(markdown)))
                        } else {
                            Text(input.prefix(5_000))
                        }
                    case .markdown:
                        Text(markdown ?? String(input.prefix(5_000))).font(.system(.callout, design: .monospaced))
                    case .html:
                        Text(markdown.map(Renderer.html) ?? "No HTML: the clip is pasted as is.")
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(20)
    }

    static func rendered(_ html: String) -> AttributedString {
        let styled = html.replacingOccurrences(
            of: "<head>",
            with: "<head><style>body{font:13px -apple-system;color:\(NSColor.labelColor.cssHex)} p,ul,ol,pre{margin:0} code,pre{font:12px ui-monospace,Menlo;background-color:rgba(127,127,127,0.16)}</style>")
        guard let data = styled.data(using: .utf8),
              let ns = try? NSAttributedString(data: data, options: [
                  .documentType: NSAttributedString.DocumentType.html,
                  .characterEncoding: String.Encoding.utf8.rawValue,
              ], documentAttributes: nil) else { return AttributedString(html) }
        return AttributedString(ns)
    }

    static let sample = """
    Switched to \u{00A0}main\u{00A0} and deleted \u{00A0}feature/clipdown\u{00A0}. The config lives at ~/Library/Preferences/com.example.app.plist.

    NEXT STEPS
    - Rebuild with swift build -c release and check config.json
    - Restart: launchctl kickstart -k gui/501/com.example.agent

    $ swift test --parallel
    All tests pass.
    """
}

/// A plain-text editor with every automatic substitution off, so the preview
/// shows exactly what you pasted (no smart dashes, quotes or autocorrect).
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        let view = scroll.documentView as! NSTextView
        view.delegate = context.coordinator
        view.isRichText = false
        view.drawsBackground = false
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.textContainerInset = NSSize(width: 6, height: 8)
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let view = scroll.documentView as! NSTextView
        if view.string != text { view.string = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ note: Notification) {
            if let view = note.object as? NSTextView { text.wrappedValue = view.string }
        }
    }
}

private extension NSColor {
    /// The color as #rrggbb, resolved for the current appearance.
    var cssHex: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000" }
        return String(format: "#%02x%02x%02x", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

// MARK: - General

struct GeneralTab: View {
    @EnvironmentObject private var engine: ClipboardEngine
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var loginNote: String?

    var body: some View {
        Form {
            Section {
                Toggle("Reshape the clipboard for the apps in my list", isOn: Binding(
                    get: { engine.settings.enabled },
                    set: { on in engine.update { $0.enabled = on } }))
                Toggle("Open ClipDown at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in
                        guard on != LoginItem.isEnabled else { return }
                        let error = LoginItem.set(on)
                        // Show what macOS actually did, not what was asked for.
                        openAtLogin = LoginItem.isEnabled
                        loginNote = error.map { "Couldn't change the login item: \($0)" } ?? loginStatusNote
                    }
                if let loginNote {
                    Text(loginNote).font(.callout).foregroundStyle(.secondary)
                    if LoginItem.status == .requiresApproval {
                        Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
            }
            Section("Privacy") {
                Text("ClipDown runs entirely on your Mac and never touches the network. It reads the clipboard only while an app in your list is in front, and only when the clip is plain text.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
                Link("ClipDown on GitHub", destination: URL(string: "https://github.com/omarshahine/clipdown")!)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            openAtLogin = LoginItem.isEnabled
            loginNote = loginStatusNote
        }
    }

    private var loginStatusNote: String? {
        LoginItem.status == .requiresApproval
            ? "macOS needs your approval in System Settings > General > Login Items." : nil
    }
}
