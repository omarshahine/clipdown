import Foundation

/// Turns plain text that lost its formatting (typically copied out of a
/// terminal) back into Markdown, using conservative heuristics.
public enum Converter {
    public struct Result: Equatable, Sendable {
        public let markdown: String
        /// How much evidence of code or Markdown was found. Zero means the
        /// text looks like ordinary prose and should be left alone.
        public let signals: Int
    }

    public static func convert(_ text: String) -> Result {
        var signals = 0
        let lines = normalize(text)
        var out: [String] = []
        var i = 0
        var inList = false

        func emitBlock(_ body: [String], lang: String) {
            if let last = out.last, !last.isEmpty { out.append("") }
            out.append("```" + lang)
            out.append(contentsOf: body)
            out.append("```")
            signals += 2
            inList = false
        }

        while i < lines.count {
            let line = lines[i]

            // Existing fenced code: keep verbatim.
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                out.append(line)
                i += 1
                while i < lines.count {
                    out.append(lines[i])
                    i += 1
                    if out.last!.trimmingCharacters(in: .whitespaces).hasPrefix("```") { break }
                }
                signals += 2
                continue
            }

            if line.isEmpty {
                out.append("")
                i += 1
                continue
            }

            // Box-drawing tables: monospace keeps the columns aligned.
            if isBoxLine(line) {
                var body: [String] = []
                while i < lines.count, isBoxLine(lines[i]) { body.append(lines[i]); i += 1 }
                emitBlock(body, lang: "")
                continue
            }

            // Shell prompts and command lines.
            if let lang = commandLanguage(line) {
                var body = [line]
                let startedWithPrompt = isPrompt(line)
                i += 1
                while i < lines.count, !lines[i].isEmpty {
                    let next = lines[i]
                    let prev = body.last!
                    let continues = prev.hasSuffix("\\") || prev.hasSuffix("|") || prev.hasSuffix("`")
                        || startedWithPrompt || commandLanguage(next) != nil || next.hasPrefix("  ")
                    guard continues, !isBoxLine(next) else { break }
                    body.append(next)
                    i += 1
                }
                emitBlock(body, lang: lang)
                continue
            }

            // A paragraph that is a JSON object or array.
            if line.hasPrefix("<"), htmlTag.matches(line) {
                var body: [String] = []
                while i < lines.count, !lines[i].isEmpty { body.append(lines[i]); i += 1 }
                emitBlock(body, lang: "html")
                continue
            }

            if line.hasPrefix("{") || line.hasPrefix("[") {
                var j = i
                var body: [String] = []
                while j < lines.count, !lines[j].isEmpty { body.append(lines[j]); j += 1 }
                let joined = body.joined(separator: "\n")
                if looksLikeJSON(joined) {
                    emitBlock(body, lang: "json")
                    i = j
                    continue
                }
            }

            // Indented runs outside a list are code.
            if !inList, line.hasPrefix("    ") || line.hasPrefix("\t") {
                var body: [String] = []
                while i < lines.count, lines[i].hasPrefix("    ") || lines[i].hasPrefix("\t") || lines[i].isEmpty {
                    body.append(lines[i])
                    i += 1
                }
                while body.last?.isEmpty == true { body.removeLast(); i -= 1 }
                let indent = body.filter { !$0.isEmpty }.map(leadingSpaces).min() ?? 0
                emitBlock(body.map { String($0.dropFirst(min(indent, leadingSpaces($0)))) }, lang: "")
                continue
            }

            // Prose: headings, list items, plain lines.
            if let m = listItem.firstMatch(line) {
                let indent = m[1] ?? ""
                var marker = m[2] ?? "-"
                if marker == "•" || marker == "*" || marker == "+" { marker = "-" }
                let (content, n) = inline(m[3] ?? "")
                signals += n
                out.append(indent + marker + " " + content)
                inList = true
            } else if isHeading(line) {
                if let last = out.last, !last.isEmpty { out.append("") }
                out.append("**" + line.trimmingCharacters(in: .whitespaces) + "**")
                if i + 1 < lines.count, !lines[i + 1].isEmpty, listItem.firstMatch(lines[i + 1]) == nil {
                    out.append("")
                }
                inList = false
            } else {
                if existingMarkdownBlock.matches(line) { signals += 1 }
                let (content, n) = inline(line)
                signals += n
                out.append(content)
                if !line.hasPrefix(" ") { inList = false }
            }
            i += 1
        }

        while out.last?.isEmpty == true { out.removeLast() }
        return Result(markdown: out.joined(separator: "\n"), signals: signals)
    }

    // MARK: - Normalization

    static func normalize(_ text: String) -> [String] {
        var lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        // Terminals pad lines to the window width, so trailing whitespace goes,
        // except inside an existing code fence where it can be meaningful.
        var inFence = false
        lines = lines.map { line -> String in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
            } else if inFence {
                return line
            }
            var l = line
            while let c = l.last, c == " " || c == "\t" { l.removeLast() }
            return l
        }
        // Trim leading and trailing blank lines in one pass each (removeFirst
        // in a loop is quadratic on a run of blank lines).
        let firstText = lines.firstIndex { !$0.isEmpty } ?? lines.count
        let lastText = lines.lastIndex { !$0.isEmpty } ?? -1
        lines = firstText <= lastText ? Array(lines[firstText...lastText]) : []
        // Terminal output is often indented as a whole; strip the shared indent.
        let indent = lines.filter { !$0.isEmpty }.map(leadingSpaces).min() ?? 0
        if indent > 0 { lines = lines.map { String($0.dropFirst(min(indent, leadingSpaces($0)))) } }
        return lines
    }

    static func leadingSpaces(_ s: String) -> Int {
        s.prefix { $0 == " " }.count
    }

    // MARK: - Block detection

    static let listItem = Pattern(#"^(\s*)([-*+•]|\d{1,3}[.)])\s+(.*)$"#)
    static let existingMarkdownBlock = Pattern(#"^(#{1,6} |> |\|.*\|$)"#)

    static func isBoxLine(_ line: String) -> Bool {
        line.unicodeScalars.contains { (0x2500...0x257F).contains($0.value) }
    }

    static let commands: Set<String> = [
        "gh", "git", "curl", "wget", "npm", "npx", "pnpm", "yarn", "bun", "brew", "cd", "ls", "cat",
        "sudo", "ssh", "scp", "rsync", "docker", "kubectl", "python", "python3", "pip", "pip3", "node",
        "swift", "xcodebuild", "xcrun", "launchctl", "defaults", "sqlite3", "chezmoi", "make", "go",
        "cargo", "wrangler", "az", "aws", "gcloud", "helm", "export", "echo", "grep", "rg", "find",
        "mkdir", "trash", "open", "osascript", "pbcopy", "pbpaste", "claude", "codex", "uv", "deno",
        "terraform", "jq", "sed", "awk", "chmod", "chown", "tail", "head", "ps", "kill", "codesign",
        "plutil", "mdls", "tar", "unzip", "pwsh", "winget", "dotnet", "pytest", "ruff", "mvn", "gradle",
        "flutter", "dart", "pod", "adb", "tmux", "poetry", "conda", "rails", "bundle",
    ]

    /// Command names that are also everyday words, so they need stronger evidence.
    static let englishCommands: Set<String> = [
        "open", "find", "make", "go", "cat", "echo", "kill", "head", "tail", "export", "trash", "ps",
    ]

    static let prompt = Pattern(#"^(\$ |❯ |% |PS [A-Za-z]:\\[^>]*> ?|[\w.-]+@[\w.-]+[:~][^$#\s]*[$#] ?)\S"#)

    static func isPrompt(_ line: String) -> Bool { prompt.matches(line) }

    /// Returns a fence language when the line is a shell command, nil otherwise.
    static func commandLanguage(_ line: String) -> String? {
        if isPrompt(line) {
            return line.hasPrefix("PS ") ? "powershell" : "bash"
        }
        var words = line.split(separator: " ", omittingEmptySubsequences: true)
        if words.first == "sudo" { words.removeFirst() }
        guard let first = words.first, commands.contains(String(first)) else { return nil }
        guard words.count > 1 || line.count <= 20 else { return nil }
        // Prose that happens to start with a command word reads like a sentence.
        if line.hasSuffix(".") && !line.hasSuffix(" .") { return nil }
        if sentenceBreak.matches(line) { return nil }
        let codeish = line.contains { "-/|=~$\"'<>{}[]".contains($0) }
        guard codeish || words.count <= 3 else { return nil }
        return "bash"
    }

    static let htmlTag = Pattern(#"^<(!--|!DOCTYPE|/?[A-Za-z][\w:-]*)(\s[^>]*)?/?>"#)

    static func looksLikeJSON(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (t.hasPrefix("{") && t.hasSuffix("}")) || (t.hasPrefix("[") && t.hasSuffix("]")) else { return false }
        if let data = t.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil {
            return true
        }
        return t.contains("\":") || t.contains("\": ")
    }

    static let headingPattern = Pattern(#"^[A-Z0-9][A-Z0-9 &/:()'’\-]*$"#)

    static func isHeading(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t == line, t.count <= 60, headingPattern.matches(t) else { return false }
        return t.filter(\.isLetter).count >= 4
    }

    // MARK: - Inline heuristics

    /// Spans that must not be rewritten: existing code spans (any number of
    /// backticks), Markdown links and images (label and target), and URLs.
    static let protected = Pattern(#"(?<!`)(`+)(?!`)[^\n]+?(?<!`)\1(?!`)|\bhttps?://[^\s<>()]+[^\s<>().,;:!?'"]"#)

    /// Ranges of Markdown links and images, `[label](target)` and
    /// `![alt](target)`. Scanned rather than matched, because a target can
    /// nest parentheses to any depth (and escape them).
    static let maxLinkPart = 512

    static func linkRanges(_ ns: NSString) -> [NSRange] {
        let (open, close, bang, lparen, rparen, backslash, newline): (unichar, unichar, unichar, unichar, unichar, unichar, unichar) =
            (91, 93, 33, 40, 41, 92, 10)
        var ranges: [NSRange] = []
        var i = 0
        while i < ns.length {
            guard ns.character(at: i) == open else { i += 1; continue }
            let start = i > 0 && ns.character(at: i - 1) == bang ? i - 1 : i
            // Labels and targets are bounded so a run of unclosed links stays
            // linear instead of rescanning the line from every bracket.
            var j = i + 1
            while j < ns.length, j - i <= maxLinkPart, ns.character(at: j) != close,
                  ns.character(at: j) != newline, ns.character(at: j) != open { j += 1 }
            guard j + 1 < ns.length, ns.character(at: j) == close, ns.character(at: j + 1) == lparen else { i = j; continue }
            var k = j + 2, depth = 1
            while k < ns.length, depth > 0, k - j <= maxLinkPart {
                let c = ns.character(at: k)
                if c == newline { break }
                if c == backslash { k += 2; continue }
                if c == lparen { depth += 1 } else if c == rparen { depth -= 1 }
                k += 1
            }
            if depth == 0 {
                ranges.append(NSRange(location: start, length: k - start))
                i = k
            } else {
                i = j + 1
            }
        }
        return ranges
    }

    /// Claude Code renders inline code with a padding space on each side, so a
    /// copy leaves `word  code  word` (or `code .` before punctuation).
    /// Claude Code pads inline code with a non-breaking space on each side.
    static let nbspCode = Pattern("(?<=^|[\\s(\\[\"'])\u{00A0}([^\u{00A0}\\n]+?)\u{00A0}(?: (?=[.,;:!?)\\]]))?(?=$|[\\s.,;:!?)\\]\"'’])")

    /// Other terminals leave plain padding, which reads as a double space.
    static let paddedCode = Pattern(#"(?<=\S)  ([^ ]+(?: [^ ]+){0,5}) (?= |[.,;:!?)\]'"’]|$)"#)
    static let quotedCommand = Pattern(#""((?:sudo )?([a-z][\w-]*) [^"\n]{1,80})""#)
    static let commandTail = Pattern(#"(?<=: )((?:sudo )?([a-z][\w-]*) [^\n]*)$"#)
    static let path = Pattern(#"(?<![\w`/.:~<])((?:~|\.{1,2})?/[\w.@%+\-]+(?:/[\w.@%+\-]*)*|\.[\w-]+/[\w.@%+\-/]+)"#)
    static let fileExtensions = "md|json|jsonc|ya?ml|db|sqlite|sql|sh|zsh|bash|ps1|cmd|bat|swift|ts|tsx|js|mjs|cjs|py|toml|plist|txt|html|css|lock|env|log|go|rs|rb|java|kt|xml|csv|xcodeproj|xcworkspace|entitlements|app|dmg|pkg|zip"
    /// `scripts/install.sh`: a relative path is only trusted when it ends in a file extension,
    /// so prose like "Autopilot/Codex" stays put.
    static let relativeFilePath = Pattern(#"(?<![\w`/.:~\-])([\w.\-]+(?:/[\w.@%+\-]+)+\.(?:"# + fileExtensions + #"))(?!\w|\.\w)"#)
    static let fileName = Pattern(#"(?<![\w`/.\-])([\w-]+(?:\.[\w-]+)*\.(?:"# + fileExtensions + #"))(?!\w|\.\w)"#)
    static let envVar = Pattern(#"(?<![\w`])([A-Z][A-Z0-9]*_[A-Z0-9_]*[A-Z0-9])(?![\w`])"#)
    static let functionCall = Pattern(#"(?<![\w`.])([A-Za-z_][\w]*(?:\.[A-Za-z_]\w*)*\([^()\s]*\))(?![\w`])"#)
    static let flag = Pattern(#"(?<![\w`\-/])(--[a-zA-Z][\w-]*(?:=[^\s`]+)?|-[a-zA-Z]{1,2})(?![\w`\-])"#)
    static let snakeCase = Pattern(#"(?<![\w`\-])([a-z][a-z0-9]*(?:_[a-z0-9]+)+)(?![\w`\-])"#)
    static let camelCase = Pattern(#"(?<![\w`\-])([a-z]+(?:[A-Z][a-z0-9]+)+)(?![\w`\-])"#)

    static let sentenceBreak = Pattern(#"[a-z]{2,}[.!?] [A-Z]"#)
    static let flagOrPipe = Pattern(#" --?[a-zA-Z]| \| "#)
    static let productJS = Pattern(#"^[A-Z][a-z]+\.js$"#)
    /// `()` or code-looking arguments; "file(s)" is a plural, not a call.
    static let callArguments = Pattern(#"\(\)$|\([^)]*['"0-9,=:_.][^)]*\)$"#)

    /// Markdown a clip already carries. Link parts are bounded and a label
    /// can't contain `[`, so a run of brackets can't go quadratic.
    static let existingMarkdown = Pattern(#"`[^`\n]+`|\*\*[^*\n]+\*\*|\[[^\[\]\n]{1,512}\]\([^)\s]{1,512}\)"#)

    /// Product names that look like camelCase identifiers but aren't code.
    static let camelExceptions: Set<String> = [
        "iPhone", "iPad", "iPadOS", "macOS", "iOS", "iCloud", "iMessage", "iTunes", "iMac", "iPod",
        "watchOS", "tvOS", "visionOS", "eBay", "eSIM", "eShop", "iPhones", "iPads", "macBook", "vNext",
    ]

    static func code(_ s: String) -> String {
        s.contains("`") ? "`` " + s + " ``" : "`" + s + "`"
    }

    /// Applies `rule` only to the parts of `line` outside protected spans.
    static func outsideProtected(_ line: String, _ rule: (String) -> (String, Int)) -> (String, Int) {
        let ns = line as NSString
        var out = ""
        var last = 0
        var count = 0
        let matched = protected.regex.matches(in: line, range: NSRange(location: 0, length: ns.length)).map(\.range)
        // Merge both kinds, dropping any range that starts inside an earlier one.
        var ranges: [NSRange] = []
        for r in (matched + linkRanges(ns)).sorted(by: { $0.location < $1.location }) {
            if let prev = ranges.last, r.location < prev.location + prev.length { continue }
            ranges.append(r)
        }
        for r in ranges {
            let (text, n) = rule(ns.substring(with: NSRange(location: last, length: r.location - last)))
            out += text + ns.substring(with: r)
            count += n
            last = r.location + r.length
        }
        let (text, n) = rule(ns.substring(from: last))
        return (out + text, count + n)
    }

    public static func inline(_ line: String) -> (String, Int) {
        var s = line
        var total = 0

        func apply(_ rule: (String) -> (String, Int)) {
            let (next, n) = outsideProtected(s, rule)
            s = next
            total += n
        }

        // Padded spans run on the raw line: the padding is the evidence.
        apply { part in nbspCode.replace(part) { g in g[1].map(code) } }
        apply { part in
            paddedCode.replace(part) { g in
                guard let body = g[1], body.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
                // Prose aligned with double spaces is common; multi-word spans need a command.
                if body.contains(" "), !commands.contains(String(body.prefix { $0 != " " })) { return nil }
                return " " + code(body)
            }
        }
        apply { part in
            quotedCommand.replace(part) { g in
                guard let body = g[1], let cmd = g[2], commands.contains(cmd) else { return nil }
                return code(body)
            }
        }
        apply { part in
            commandTail.replace(part) { g in
                guard let body = g[1], let cmd = g[2], commands.contains(cmd) else { return nil }
                // Without flags or a pipe, only short tails led by a word that isn't English.
                let flagged = flagOrPipe.matches(body)
                let short = body.split(separator: " ").count <= 5 && !body.hasSuffix(".")
                    && !englishCommands.contains(cmd)
                guard flagged || short else { return nil }
                return code(body)
            }
        }
        apply { part in
            path.replace(part) { g in
                guard var p = g[1] else { return nil }
                var dots = ""
                while p.hasSuffix(".") { p.removeLast(); dots += "." }
                return p.count > 1 ? code(p) + dots : nil
            }
        }
        apply { part in relativeFilePath.replace(part) { g in g[1].map(code) } }
        apply { part in
            fileName.replace(part) { g in
                guard let name = g[1] else { return nil }
                // "Node.js" and friends are product names.
                if productJS.matches(name) { return nil }
                return code(name)
            }
        }
        apply { part in envVar.replace(part) { g in g[1].map(code) } }
        apply { part in
            functionCall.replace(part) { g in
                // "file(s)" is a plural, not a call.
                guard let call = g[1], callArguments.matches(call) else { return nil }
                return code(call)
            }
        }
        apply { part in flag.replace(part) { g in g[1].map(code) } }
        apply { part in snakeCase.replace(part) { g in g[1].map(code) } }
        apply { part in
            camelCase.replace(part) { g in
                guard let word = g[1], !camelExceptions.contains(word) else { return nil }
                return code(word)
            }
        }

        // Count Markdown the text already carried.
        let (_, carried) = existingMarkdown.replace(line) { $0[0] }
        return (s, total + carried)
    }
}
