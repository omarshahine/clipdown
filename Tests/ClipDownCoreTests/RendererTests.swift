import Testing
@testable import ClipDownCore

@Suite struct RendererTests {
    @Test func paragraphsKeepLineBreaks() {
        #expect(Renderer.html("one\ntwo\n\nthree") == "<p>one<br>two</p><p>three</p>")
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
        #expect(Renderer.html("- a\n\n- b\n\nafter") == "<ul><li>a</li><li>b</li></ul><p>after</p>")
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
