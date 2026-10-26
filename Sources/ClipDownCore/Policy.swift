import Foundation

/// Decides whether a clipboard is a candidate, from its type list alone, so
/// the contents are read only when there is something to do.
public enum Policy {
    /// Holds the original text, so the clip can be reshaped for each app.
    public static let markerType = "com.omarshahine.clipdown.original"
    /// Records which shape is on the clipboard right now.
    public static let shapeType = "com.omarshahine.clipdown.shape"
    public static let maxLength = 50_000

    /// Any of these means the clip already has formatting, isn't text, or is
    /// marked private by a password manager.
    static let blockingTypes: Set<String> = [
        markerType,
        "public.html", "public.rtf", "com.apple.flat-rtfd", "com.apple.webarchive",
        "public.file-url", "public.png", "public.tiff", "public.jpeg",
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
        "com.agilebits.onepassword", "com.microsoft.teams.message",
    ]

    public static func isCandidate(types: [String]) -> Bool {
        types.contains("public.utf8-plain-text") && blockingTypes.isDisjoint(with: types)
    }

    public enum Verdict: Equatable, Sendable {
        case convert(markdown: String, signals: Int)
        case empty, tooLarge, singleWord, prose

        /// Why a clip is left alone, for people.
        public var reason: String {
            switch self {
            case .convert: "Converts"
            case .empty: "Nothing to convert"
            case .tooLarge: "Left alone: over 50 KB"
            case .singleWord: "Left alone: a single word or link"
            case .prose: "Left alone: reads like prose"
            }
        }
    }

    /// Decides what happens to a clip. The size check comes first, so a huge
    /// clip is never run through the heuristics.
    public static func verdict(for text: String) -> Verdict {
        guard text.utf8.count <= maxLength else { return .tooLarge }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        // A single word (a URL, a filename) is usually dropped into a sentence,
        // and chat apps build their own previews for links.
        if !trimmed.contains(where: \.isWhitespace) { return .singleWord }
        let result = Converter.convert(text)
        return result.signals > 0 ? .convert(markdown: result.markdown, signals: result.signals) : .prose
    }

    /// Returns the Markdown for a clip, or nil to leave the clipboard alone.
    public static func markdown(for text: String) -> String? {
        if case .convert(let markdown, _) = verdict(for: text) { return markdown }
        return nil
    }

    /// Returns the HTML to add, or nil to leave the clipboard alone.
    public static func html(for text: String) -> String? {
        markdown(for: text).map(Renderer.htmlDocument)
    }
}
