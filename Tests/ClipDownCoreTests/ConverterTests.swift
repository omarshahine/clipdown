import Testing
@testable import ClipDownCore

private func md(_ text: String) -> String { Converter.convert(text).markdown }

@Suite struct InlineCode {
    @Test func nbspPaddingFromClaudeCode() {
        #expect(md("Switched to \u{00A0}main\u{00A0} and deleted \u{00A0}feature/x\u{00A0} .")
            == "Switched to `main` and deleted `feature/x`.")
    }

    @Test func doubleSpacePadding() {
        #expect(md("Run  npm test  before pushing.") == "Run `npm test` before pushing.")
    }

    @Test func pathsFilesAndIdentifiers() {
        #expect(md("Copied to ~/.config/app/state.db.") == "Copied to `~/.config/app/state.db`.")
        #expect(md("Edit .github/CODEOWNERS today") == "Edit `.github/CODEOWNERS` today")
        #expect(md("Run scripts/install.sh, then open Sources/clipdown/main.swift.")
            == "Run `scripts/install.sh`, then open `Sources/clipdown/main.swift`.")
        #expect(Converter.convert("Ask Autopilot/Codex about feature/clipdown-v1").signals == 0)
        #expect(md("Set APP_TOKEN_PATH and call mailFolders('inbox') with --verbose")
            == "Set `APP_TOKEN_PATH` and call `mailFolders('inbox')` with `--verbose`")
        #expect(md("It ships as installer.cmd and reads config.json.") == "It ships as `installer.cmd` and reads `config.json`.")
        #expect(md("The automaticRepliesSetting and sync_cursor fields") == "The `automaticRepliesSetting` and `sync_cursor` fields")
    }

    @Test func commandAfterColon() {
        #expect(md("Then, once: gh auth login") == "Then, once: `gh auth login`")
        #expect(md("Install: brew install --cask foo") == "Install: `brew install --cask foo`")
    }

    @Test func leavesProseAlone() {
        let prose = [
            "My iPhone and macOS machines run Node.js just fine.",
            "Note: open the app and find it.",
            "Check the file(s) for Autopilot/Codex and A/B tests, e.g. 24/7 support.",
            "Wi-Fi is re-run every 30 minutes at 07:00.",
            "See https://example.com/a_b/c?x=1 for details.",
        ]
        for line in prose {
            let r = Converter.convert(line)
            #expect(r.markdown == line)
            #expect(r.signals == 0)
        }
    }

    @Test func respectsExistingMarkdown() {
        let text = "The dump uses **Graph HTML plus structured `mentions`**, with no card."
        let r = Converter.convert(text)
        #expect(r.markdown == text)
        #expect(r.signals > 0)
    }
}

@Suite struct Blocks {
    @Test func boxTableBecomesCodeBlock() {
        let text = """
        Files needing approval:

        ┌──────┬──────┐
        │ Area │ Who  │
        └──────┴──────┘
        """
        #expect(md(text) == """
        Files needing approval:

        ```
        ┌──────┬──────┐
        │ Area │ Who  │
        └──────┴──────┘
        ```
        """)
    }

    @Test func promptSessionKeepsOutput() {
        let text = """
        PS C:\\Users\\me\\repo> tool auth login
        Logged in as me@example.com
        PS C:\\Users\\me\\repo> tool accept-eula
        """
        #expect(md(text) == "```powershell\n" + text + "\n```")
    }

    @Test func commandLinesAfterLabel() {
        let text = """
        macOS (Terminal):
        gh api -H "Accept: raw" repos/me/x/contents/install.sh | bash

        Done.
        """
        #expect(md(text) == """
        macOS (Terminal):

        ```bash
        gh api -H "Accept: raw" repos/me/x/contents/install.sh | bash
        ```

        Done.
        """)
    }

    @Test func proseStartingWithCommandWordIsNotCode() {
        #expect(Converter.commandLanguage("make sure the cache is warm before you start.") == nil)
        #expect(Converter.commandLanguage("open items") == "bash")
        #expect(Converter.commandLanguage("$5 off today") == nil)
        #expect(Converter.commandLanguage("$ swift build -c release") == "bash")
    }

    @Test func jsonParagraph() {
        #expect(md("{\n  \"a\": 1\n}") == "```json\n{\n  \"a\": 1\n}\n```")
    }

    @Test func sharedIndentIsStripped() {
        #expect(md("  hello\n  world") == "hello\nworld")
    }

    @Test func headingsAndLists() {
        let text = """
        RUNNING FROM THE REPO
        • First item
        - Second item
          - Nested item
          continuation line
        1. Numbered
        """
        #expect(md(text) == """
        **RUNNING FROM THE REPO**
        - First item
        - Second item
          - Nested item
          continuation line
        1. Numbered
        """)
    }
}

@Suite struct PolicyTests {
    @Test func onlyPlainTextIsACandidate() {
        #expect(Policy.isCandidate(types: ["public.utf8-plain-text"]))
        #expect(!Policy.isCandidate(types: ["public.utf8-plain-text", "public.html"]))
        #expect(!Policy.isCandidate(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        #expect(!Policy.isCandidate(types: ["public.utf8-plain-text", Policy.markerType]))
        #expect(!Policy.isCandidate(types: ["public.png"]))
    }

    @Test func skipsProseAndLoneURLs() {
        #expect(Policy.html(for: "Lunch at noon works for me.") == nil)
        #expect(Policy.html(for: "https://example.com/path?q=1") == nil)
        #expect(Policy.html(for: String(repeating: "--flag ", count: 10_000)) == nil)
        #expect(Policy.html(for: "Run  npm test  first") != nil)
    }
}

@Suite struct FalsePositivesFromHistory {
    @Test func htmlSourceIsABlockNotPaths() {
        #expect(md("<p>Hello <b>there</b></p>\n<ul><li>x</li></ul>") == "```html\n<p>Hello <b>there</b></p>\n<ul><li>x</li></ul>\n```")
        #expect(Converter.convert("I wrote </p> by hand").signals == 0)
    }

    @Test func alignedProseIsNotCode() {
        #expect(Converter.convert("Share Times  Duo screenshots  done").signals == 0)
        #expect(Converter.convert("left  |  right").signals == 0)
    }

    @Test func guidsAndNamesAreNotCode() {
        #expect(Converter.convert("image-2020 -e21ad872-4227 here").signals == 0)
        #expect(Converter.convert("Ask Jane Doe(janedoe) about it").signals == 0)
        #expect(md("call kevent() and run -rf") == "call `kevent()` and run `-rf`")
    }

    @Test func singleWordClipsAreLeftAlone() {
        #expect(Policy.html(for: "ReadMe.md") == nil)
        #expect(Policy.html(for: "~/GitHub/clipdown") == nil)
    }
}
