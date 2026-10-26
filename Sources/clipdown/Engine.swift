import AppKit
import ClipDownCore
import os

let log = Logger(subsystem: "com.omarshahine.clipdown", category: "engine")

/// What ClipDown last put on the clipboard.
enum Shape: String {
    case plain, richText, markdown
    /// A Convert Now result: left as-is until the next copy.
    case manual

    init(_ format: OutputFormat) {
        switch format {
        case .richText: self = .richText
        case .markdown: self = .markdown
        }
    }
}

struct Conversion {
    let appName: String
    let format: OutputFormat
    let date: Date
}

/// Watches which app is in front and keeps the clipboard in the right shape
/// for it: HTML for rich-text apps, Markdown for Markdown apps, and the
/// original text everywhere else.
@MainActor
final class ClipboardEngine: ObservableObject {
    @Published private(set) var settings = SettingsStore.load()
    @Published private(set) var lastConversion: Conversion?

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount = -1
    private var timer: Timer?

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.frontmostChanged() } }
        // Edits made from the CLI.
        DistributedNotificationCenter.default().addObserver(
            forName: SettingsStore.changedNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.reload() } }
        frontmostChanged()
        log.info("started; targets: \(self.settings.targets.map(\.bundleID).joined(separator: ", "))")
    }

    func update(_ change: (inout Settings) -> Void) {
        // Apply the edit to what's on disk, not the cached copy, under the
        // store's lock, so a concurrent CLI edit isn't overwritten.
        settings = SettingsStore.edit(change)
        frontmostChanged()
    }

    private func reload() {
        let fresh = SettingsStore.load()
        guard fresh != settings else { return }
        settings = fresh
        frontmostChanged()
    }

    private var frontmostTarget: TargetApp? {
        settings.target(for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    private func frontmostChanged() {
        let target = frontmostTarget
        reshape(for: target)
        if target != nil {
            // Keep watching while a target app is in front, so a copy made
            // without switching apps (Universal Clipboard, a clipboard
            // manager) is picked up too. Ticks read only the change count.
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.tick() }
                }
            }
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    private func tick() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        reshape(for: frontmostTarget)
    }

    private func reshape(for target: TargetApp?) {
        // Every read and the final write must see the same clipboard
        // generation. If another app copies mid-conversion, its newer clip
        // wins and stays eligible for the next tick.
        let generation = pasteboard.changeCount
        lastChangeCount = generation
        let types = pasteboard.types?.map(\.rawValue) ?? []
        guard pasteboard.pasteboardItems?.count == 1 else { return }

        // A clip ClipDown already touched: switch it to the shape this app wants.
        if types.contains(Policy.markerType) {
            guard let original = pasteboard.string(forType: .init(Policy.markerType)) else { return }
            let current = pasteboard.string(forType: .init(Policy.shapeType)).flatMap(Shape.init) ?? .plain
            let wanted = target.map { Shape($0.format) } ?? .plain
            guard current != .manual, current != wanted, let markdown = Policy.markdown(for: original) else { return }
            write(original: original, markdown: markdown, shape: wanted, ifStill: generation)
            return
        }

        // A fresh clip: only read its contents when a target app is in front
        // and the type list says it's plain text.
        guard let target, Policy.isCandidate(types: types),
              let text = pasteboard.string(forType: .string),
              let markdown = Policy.markdown(for: text),
              write(original: text, markdown: markdown, shape: Shape(target.format), ifStill: generation) else { return }
        lastConversion = Conversion(appName: target.name, format: target.format, date: .now)
        log.info("converted \(text.count) chars for \(target.bundleID) as \(target.format.rawValue)")
    }

    /// Converts the clipboard for whatever app you paste into next, ignoring
    /// the app list. Returns false when there's nothing to convert.
    @discardableResult
    func convertNow(as format: OutputFormat) -> Bool {
        let generation = pasteboard.changeCount
        let types = pasteboard.types?.map(\.rawValue) ?? []
        guard pasteboard.pasteboardItems?.count == 1 else { return false }
        let text = types.contains(Policy.markerType)
            ? pasteboard.string(forType: .init(Policy.markerType))
            : (Policy.isCandidate(types: types) ? pasteboard.string(forType: .string) : nil)
        guard let text, let markdown = Policy.markdown(for: text),
              write(original: text, markdown: markdown, shape: .manual, manualFormat: format, ifStill: generation)
        else { return false }
        lastConversion = Conversion(appName: "Convert Now", format: format, date: .now)
        return true
    }

    /// Replaces the clipboard, unless it changed since `generation` was read.
    /// Returns whether it wrote.
    @discardableResult
    private func write(original: String, markdown: String, shape: Shape,
                       manualFormat: OutputFormat? = nil, ifStill generation: Int) -> Bool {
        // Build everything first, rendering included, so the generation check
        // sits right before the write.
        let item = NSPasteboardItem()
        switch manualFormat ?? (shape == .markdown ? .markdown : shape == .richText ? .richText : nil) {
        case .richText:
            item.setString(original, forType: .string)
            item.setString(Renderer.htmlDocument(markdown), forType: .html)
        case .markdown:
            item.setString(markdown, forType: .string)
        case nil:
            item.setString(original, forType: .string)
        }
        item.setString(original, forType: .init(Policy.markerType))
        item.setString(shape.rawValue, forType: .init(Policy.shapeType))
        // nspasteboard.org convention: clipboard managers skip this entry,
        // since the original is already in their history.
        item.setData(Data(), forType: .init("org.nspasteboard.AutoGeneratedType"))
        guard pasteboard.changeCount == generation else {
            log.info("clipboard changed during conversion; keeping the newer clip")
            return false
        }
        // Record the generation this write created, not whatever is live
        // afterwards, so a copy landing right after still gets processed.
        lastChangeCount = pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            // The clipboard is already cleared; put the original text back.
            log.error("couldn't write the converted clip to the pasteboard; restoring the original")
            pasteboard.setString(original, forType: .string)
            lastChangeCount = pasteboard.changeCount
            return false
        }
        return true
    }

    /// Puts the original text back before ClipDown quits, so a Markdown or
    /// rich-text shape never outlives the app that made it.
    func restoreOriginal() {
        reshape(for: nil)
    }
}
