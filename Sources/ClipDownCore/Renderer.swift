import Foundation

/// Renders the Markdown subset the converter produces (plus common Markdown a
/// clip may already carry) to HTML that Teams' compose box accepts.
public enum Renderer {
    public static func htmlDocument(_ markdown: String) -> String {
        "<html><head><meta charset=\"utf-8\"></head><body>" + html(markdown) + "</body></html>"
    }

    /// Deeper `>` nesting renders as text, so a run of markers can't recurse
    /// without bound.
    static let maxQuoteDepth = 8

    public static func html(_ markdown: String) -> String {
        html(markdown, depth: 0)
    }

    static func html(_ markdown: String, depth: Int) -> String {
        let lines = markdown.components(separatedBy: "\n")
        // The next non-blank line after each index, computed once, so runs of
        // blank lines stay linear.
        var nextNonblank = [Int](repeating: lines.count, count: lines.count + 1)
        for k in stride(from: lines.count - 1, through: 0, by: -1) {
            nextNonblank[k] = lines[k].trimmingCharacters(in: .whitespaces).isEmpty ? nextNonblank[k + 1] : k
        }
        var out = ""
        var paragraph: [String] = []
        var lists: [(tag: String, indent: Int)] = []
        var i = 0
        // Chat apps (Teams) and NSAttributedString ignore paragraph margins,
        // so a blank line in the source becomes an explicit empty line.
        var blankPending = false

        func spaceIfNeeded() {
            if blankPending, !out.isEmpty { out += "<p><br></p>" }
            blankPending = false
        }

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            spaceIfNeeded()
            out += "<p>" + paragraph.map(inline).joined(separator: "<br>") + "</p>"
            paragraph = []
        }
        func closeLists(above indent: Int = -1) {
            while let top = lists.last, top.indent > indent {
                out += "</li></\(top.tag)>"
                lists.removeLast()
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                closeLists()
                // Only plain language names reach the class attribute.
                let lang = String(trimmed.dropFirst(3).prefix { !$0.isWhitespace }
                    .filter { $0.isLetter || $0.isNumber || "+-_#.".contains($0) })
                var body: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    body.append(lines[i])
                    i += 1
                }
                i += 1
                let cls = lang.isEmpty ? "" : " class=\"language-\(escape(lang))\""
                spaceIfNeeded()
                out += "<pre><code\(cls)>" + escape(body.joined(separator: "\n")) + "</code></pre>"
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                // A list survives blank lines only if another item follows.
                let n = nextNonblank[i + 1]
                let next: String? = n < lines.count ? lines[n] : nil
                if next.map({ Converter.listItem.firstMatch($0) == nil && !$0.hasPrefix(" ") }) ?? true {
                    closeLists()
                }
                blankPending = true
                i += 1
                continue
            }

            if let m = Converter.listItem.firstMatch(line) {
                flushParagraph()
                let indent = (m[1] ?? "").count
                let tag = (m[2] ?? "-").first!.isNumber ? "ol" : "ul"
                closeLists(above: indent)
                // Items of a list already open stay tight, even across blank lines.
                if lists.isEmpty { spaceIfNeeded() } else { blankPending = false }
                if let top = lists.last, top.indent == indent {
                    if top.tag == tag {
                        out += "</li>"
                    } else {
                        out += "</li></\(top.tag)>"
                        lists.removeLast()
                        out += "<\(tag)>"
                        lists.append((tag, indent))
                    }
                } else {
                    out += "<\(tag)>"
                    lists.append((tag, indent))
                }
                out += "<li>" + inline(m[3] ?? "")
                i += 1
                continue
            }

            // Indented text under a list item continues that item.
            if !lists.isEmpty, line.hasPrefix(" ") {
                out += "<br>" + inline(trimmed)
                i += 1
                continue
            }
            closeLists()

            if let m = heading.firstMatch(line) {
                flushParagraph()
                let level = min((m[1] ?? "#").count + 1, 4)
                spaceIfNeeded()
                out += "<h\(level)>" + inline(m[2] ?? "") + "</h\(level)>"
                i += 1
                continue
            }

            if trimmed.hasPrefix(">"), depth < maxQuoteDepth {
                flushParagraph()
                var quoted: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    let q = lines[i].trimmingCharacters(in: .whitespaces).dropFirst()
                    quoted.append(String(q.hasPrefix(" ") ? q.dropFirst() : q))
                    i += 1
                }
                spaceIfNeeded()
                out += "<blockquote>" + html(quoted.joined(separator: "\n"), depth: depth + 1) + "</blockquote>"
                continue
            }

            if trimmed.hasPrefix("|"), i + 1 < lines.count, tableRule.matches(lines[i + 1]) {
                flushParagraph()
                spaceIfNeeded()
                out += "<table><thead><tr>" + cells(trimmed).map { "<th>\(inline($0))</th>" }.joined() + "</tr></thead><tbody>"
                i += 2
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    out += "<tr>" + cells(lines[i]).map { "<td>\(inline($0))</td>" }.joined() + "</tr>"
                    i += 1
                }
                out += "</tbody></table>"
                continue
            }

            paragraph.append(line)
            i += 1
        }
        flushParagraph()
        closeLists()
        return out
    }

    static let heading = Pattern(#"^(#{1,6})\s+(.*)$"#)
    static let tableRule = Pattern(#"^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$"#)

    static func cells(_ row: String) -> [String] {
        var t = row.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        // Split on unescaped pipes only; `\|` is a literal pipe inside a cell.
        var cells = [""]
        var escaped = false
        for c in t {
            if escaped {
                cells[cells.count - 1].append(c == "|" ? "|" : "\\\(c)")
                escaped = false
            } else if c == "\\" {
                escaped = true
            } else if c == "|" {
                cells.append("")
            } else {
                cells[cells.count - 1].append(c)
            }
        }
        if escaped { cells[cells.count - 1].append("\\") }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// CommonMark code spans: the closing run is exactly as long as the opening one.
    static let codeSpan = Pattern(#"(?<!`)(`+)(?!`)([^\n]+?)(?<!`)\1(?!`)"#)
    /// Bounded, and a label can't contain `[`, so unclosed brackets can't
    /// make this rescan the line from every one of them.
    // Neither a link target nor a bare URL may contain a placeholder
    // delimiter (U+E000 or U+E001): a placeholder restored inside an href
    // would put markup in an attribute.
    static let link = Pattern("\\[([^\\[\\]\\n]{1,1024})\\]\\((https?://[^)\\s\u{E000}\u{E001}]{1,2048})\\)")
    static let bareURL = Pattern("\\bhttps?://[^\\s<>()\u{E000}\u{E001}]+[^\\s<>().,;:!?'\"\u{E000}\u{E001}]")
    static let bold = Pattern(#"\*\*(?=\S)([^*\n]+?)(?<=\S)\*\*"#)
    static let italic = Pattern(#"(?<![\w*])\*(?=\S)([^*\n]+?)(?<=\S)\*(?![\w*])"#)

    /// Placeholder delimiters, from the Unicode private use area. Any copies
    /// in the input are dropped first, so clipboard text can't forge one.
    static let open: Character = "\u{E000}", close: Character = "\u{E001}"
    static let placeholder = Pattern("\u{E000}(\\d{1,6})\u{E001}")

    static func inline(_ text: String) -> String {
        // Code spans and links are swapped for placeholders so later passes can't touch them.
        var stash: [String] = []
        func hold(_ html: String) -> String {
            stash.append(html)
            return "\(open)\(stash.count - 1)\(close)"
        }
        var s = codeSpan.replace(text.filter { $0 != open && $0 != close }) { g in
            var body = g[2] ?? ""
            // One space of padding on both sides is stripped, so `` `x` `` works.
            if body.count > 2, body.hasPrefix(" "), body.hasSuffix(" "), body.contains(where: { $0 != " " }) {
                body = String(body.dropFirst().dropLast())
            }
            return hold("<code>" + escape(body) + "</code>")
        }.0
        s = link.replace(s) { g in
            hold("<a href=\"\(escape(g[2] ?? ""))\">" + escape(g[1] ?? "") + "</a>")
        }.0
        s = bareURL.replace(s) { g in
            let url = escape(g[0] ?? "")
            return hold("<a href=\"\(url)\">\(url)</a>")
        }.0
        s = escape(s)
        s = bold.replace(s) { g in "<strong>" + (g[1] ?? "") + "</strong>" }.0
        s = italic.replace(s) { g in "<em>" + (g[1] ?? "") + "</em>" }.0
        // A link label can hold a code span, so resolve until nothing is left.
        for _ in 0..<4 {
            let (next, n) = placeholder.replace(s) { g in
                g[1].flatMap(Int.init).flatMap { stash.indices.contains($0) ? stash[$0] : nil }
            }
            s = next
            if n == 0 { break }
        }
        return s
    }
}
