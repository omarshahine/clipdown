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

    /// Returns the Markdown for a clip, or nil to leave the clipboard alone.
    public static func markdown(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, text.utf8.count <= maxLength else { return nil }
        // A single word (a URL, a filename) is usually dropped into a sentence,
        // and chat apps build their own previews for links.
        if !trimmed.contains(where: \.isWhitespace) { return nil }
        let result = Converter.convert(text)
        return result.signals > 0 ? result.markdown : nil
    }

    /// Returns the HTML to add, or nil to leave the clipboard alone.
    public static func html(for text: String) -> String? {
        markdown(for: text).map(Renderer.htmlDocument)
    }
}
