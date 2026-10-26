import Foundation

/// Thin wrapper over NSRegularExpression. Foundation's engine supports the
/// lookbehinds the heuristics rely on.
struct Pattern: @unchecked Sendable {
    let regex: NSRegularExpression

    init(_ pattern: String, _ options: NSRegularExpression.Options = []) {
        // Patterns are compile-time constants; a bad one is a programmer error.
        regex = try! NSRegularExpression(pattern: pattern, options: options)
    }

    func matches(_ s: String) -> Bool {
        regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    func firstMatch(_ s: String) -> [String?]? {
        guard let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: s).map { String(s[$0]) }
        }
    }

    /// Replaces every match with `transform(groups)`; returning nil keeps the match.
    /// Returns the new string and how many replacements were made.
    func replace(_ s: String, _ transform: ([String?]) -> String?) -> (String, Int) {
        let ns = s as NSString
        var out = ""
        var last = 0
        var count = 0
        for m in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let groups = (0..<m.numberOfRanges).map { i -> String? in
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            guard let replacement = transform(groups) else { continue }
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += replacement
            last = m.range.location + m.range.length
            count += 1
        }
        out += ns.substring(from: last)
        return (out, count)
    }
}
