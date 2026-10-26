/// CommonMark backtick fences: a fence closes only on a run of at least as
/// many backticks as opened it, and a generated fence or code span must be
/// longer than any backtick run inside its content.
enum Fence {
    /// The backtick count opening a fence on this line, or nil.
    static func opening(_ line: String) -> Int? {
        let indent = line.prefix { $0 == " " }.count
        guard indent <= 3 else { return nil }
        let run = line.dropFirst(indent).prefix { $0 == "`" }.count
        guard run >= 3 else { return nil }
        // An info string can't contain backticks, or this is inline code.
        return line.dropFirst(indent + run).contains("`") ? nil : run
    }

    /// Whether `line` closes a fence opened with `run` backticks.
    static func closes(_ line: String, opened run: Int) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.count >= run && t.allSatisfy { $0 == "`" }
    }

    static func longestBacktickRun(_ s: String) -> Int {
        var longest = 0, current = 0
        for c in s {
            current = c == "`" ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }

    /// A fence that can't be closed early by anything in `body`.
    static func delimiter(for body: [String]) -> String {
        String(repeating: "`", count: max(3, body.map(longestBacktickRun).max().map { $0 + 1 } ?? 3))
    }

    /// Inline code for `s`, with enough backticks that its own can't close it.
    static func inlineCode(_ s: String) -> String {
        let run = longestBacktickRun(s)
        guard run > 0 else { return "`" + s + "`" }
        let ticks = String(repeating: "`", count: run + 1)
        return ticks + " " + s + " " + ticks
    }
}
