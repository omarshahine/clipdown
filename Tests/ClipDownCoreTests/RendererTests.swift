import Foundation
import Testing
@testable import ClipDownCore

@Suite struct RendererTests {
    @Test func paragraphsKeepLineBreaks() {
        #expect(Renderer.html("one\ntwo\n\nthree") == "<p>one<br>two</p><p><br></p><p>three</p>")
        #expect(Renderer.html("text\n\n```\ncode\n```\nafter") == "<p>text</p><p><br></p><pre><code>code</code></pre><p>after</p>")
    }

    @Test func inlineFormatting() {
        #expect(Renderer.html("Use `a < b` and **bold** and *em* at https://x.com/a.")
            == "<p>Use <code>a &lt; b</code> and <strong>bold</strong> and <em>em</em> at <a href=\"https://x.com/a\">https://x.com/a</a>.</p>")
        #expect(Renderer.html("[docs](https://x.com/d)") == "<p><a href=\"https://x.com/d\">docs</a></p>")
        #expect(Renderer.html("`` a`b ``") == "<p><code>a`b</code></p>")
    }

    @Test func codeBlocksAreEscaped() {
        #expect(Renderer.html("```bash\necho \"<hi>\" && ls\n```")
            == "<pre><code class=\"language-bash\">echo &quot;&lt;hi&gt;&quot; &amp;&amp; ls</code></pre>")
    }

    @Test func nestedAndMixedLists() {
        let md = """
        - a
          - b
          more
        - c
        1. d
        """
        #expect(Renderer.html(md) == "<ul><li>a<ul><li>b<br>more</li></ul></li><li>c</li></ul><ol><li>d</li></ol>")
    }

    @Test func listSurvivesBlankLineBetweenItems() {
        #expect(Renderer.html("- a\n\n- b\n\nafter") == "<ul><li>a</li><li>b</li></ul><p><br></p><p>after</p>")
    }

    @Test func headingsQuotesTables() {
        #expect(Renderer.html("# Title") == "<h2>Title</h2>")
        #expect(Renderer.html("> quoted **x**") == "<blockquote><p>quoted <strong>x</strong></p></blockquote>")
        #expect(Renderer.html("| a | b |\n|---|---|\n| 1 | `2` |")
            == "<table><thead><tr><th>a</th><th>b</th></tr></thead><tbody><tr><td>1</td><td><code>2</code></td></tr></tbody></table>")
    }

    @Test func documentDeclaresUTF8() {
        #expect(Renderer.htmlDocument("x").contains("<meta charset=\"utf-8\">"))
    }
}

/// Regressions from the Clawpatch review and security audit (2026-10-25).
@Suite struct RendererRegressions {
    @Test func codeInsideLinkLabels() {
        #expect(Renderer.html("[`README.md`](https://example.com)")
            == "<p><a href=\"https://example.com\"><code>README.md</code></a></p>")
        let html = Policy.html(for: "See [config.json](https://example.com) for --verbose") ?? ""
        #expect(html.contains(">config.json</a>"))
        #expect(!html.contains("\u{E000}") && !html.contains("\u{1}"))
    }

    @Test func forgedPlaceholdersCannotCrash() {
        for input in ["\u{1}0\u{2}", "\u{E000}0\u{E001}", "\u{E000}999\u{E001} `x`", "\u{E000}99999999999999999999\u{E001}"] {
            let html = Renderer.html(input)
            #expect(!html.contains("\u{E000}"))
        }
        #expect(Policy.html(for: "Use --verbose \u{1}999\u{2}") != nil)
    }

    @Test func codeSpansCloseOnMatchingRuns() {
        #expect(Renderer.html("``a```b`` and `c`") == "<p><code>a```b</code> and <code>c</code></p>")
        #expect(Renderer.html("`` `x` ``") == "<p><code>`x`</code></p>")
    }

    @Test func escapedPipesStayInTheirCell() {
        #expect(Renderer.html("| a | b |\n|---|---|\n| x\\|y | z |")
            == "<table><thead><tr><th>a</th><th>b</th></tr></thead><tbody><tr><td>x|y</td><td>z</td></tr></tbody></table>")
    }

    @Test func fenceLanguageIsSanitized() {
        let html = Renderer.html("```bash\" onmouseover=\"alert(1)\necho hi\n```")
        #expect(html == "<pre><code class=\"language-bash\">echo hi</code></pre>")
    }

    @Test func clipboardHTMLCannotBecomeMarkup() {
        let html = Renderer.html("<script>alert(1)</script> [x](javascript:alert(1)) <img src=x onerror=y>")
        #expect(!html.contains("<script") && !html.contains("<img") && !html.contains("href=\"javascript"))
    }
}

/// Regressions from the second Clawpatch pass (2026-10-25).
@Suite struct SecondPassRegressions {
    @Test func placeholdersNeverLandInsideAnAttribute() {
        let html = Renderer.html("https://evil.example/[x](https://b.example/\" onmouseover=\"alert(1))")
        // Every href value must be free of markup.
        let hrefs = html.components(separatedBy: "href=\"").dropFirst().map { $0.prefix { $0 != "\"" } }
        #expect(!hrefs.isEmpty)
        for href in hrefs { #expect(!href.contains("<") && !href.contains(">")) }
        #expect(!html.contains("onmouseover=\""))
    }

    @Test func clawpatchInjectionReproduction() {
        let html = Renderer.html("https://outer/[x](https://inner/onmouseover=location='//evil'//)")
        #expect(html == "<p><a href=\"https://outer/\">https://outer/</a><a href=\"https://inner/onmouseover=location='//evil'//\">x</a></p>")
    }

    @Test func deepQuotesDoNotRecurseWithoutBound() {
        let html = Renderer.html(String(repeating: ">", count: 20_000) + " deep")
        #expect(html.components(separatedBy: "<blockquote>").count - 1 == Renderer.maxQuoteDepth)
    }

    @Test func longBlankRunsStayFast() {
        let start = Date()
        _ = Renderer.html("- a\n" + String(repeating: "\n", count: 40_000) + "b")
        _ = Converter.convert(String(repeating: "\n", count: 40_000) + "Run  npm test  now" + String(repeating: "\n", count: 40_000))
        #expect(Date().timeIntervalSince(start) < 5)
    }
}
