# Changelog

What changed in each ClipDown release, newest first. The release workflow publishes these notes, so every version needs a section before it's tagged.

## 1.2.0

- Settings has standard Mac toolbar tabs, and the window is titled after the tab you're on. It reopens on the tab you used last.

## 1.1.2

- Fixed: copies of ClipDown built from source never saw updates. Releases were numbered below them, so Sparkle thought they were already newer. Release builds now take the same build number as source builds.

## 1.1.1

- Quotes from Claude Code and Codex paste as real quotes. ClipDown used to mistake the `│` bar beside a quote for a table and turn the whole thing into a code block.
- Text the terminal broke at the window width flows again. Paragraphs, list items and quotes come out whole instead of as ragged lines.
- The `●` at the start of a Claude Code reply is dropped.

## 1.1.0

- Signed and notarized releases that update themselves through Sparkle. **Check for Updates…** is in the menu, and automatic checks can be turned off in **Settings > General**.
- Install with Homebrew: `brew install --cask omarshahine/tap/clipdown`.
- Sturdier conversion of links, URLs, code spans, fences and lists, plus guards that keep huge or hostile clips fast.
- Settings edits from the app and the `clipdown` command no longer overwrite each other.
