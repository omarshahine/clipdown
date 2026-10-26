import Foundation
import Testing
@testable import ClipDownCore

@Suite struct SettingsTests {
    @Test func defaultsToTeamsAsRichText() {
        let s = Settings()
        #expect(s.enabled)
        #expect(s.targets.map(\.bundleID) == ["com.microsoft.teams2"])
        #expect(s.target(for: "com.microsoft.teams2")?.format == .richText)
    }

    @Test func targetLookupHonorsSwitches() {
        var s = Settings()
        s.targets.append(TargetApp(bundleID: "md.obsidian", name: "Obsidian", format: .markdown, enabled: false))
        #expect(s.target(for: "md.obsidian") == nil)
        #expect(s.target(for: nil) == nil)
        s.enabled = false
        #expect(s.target(for: "com.microsoft.teams2") == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        var s = Settings()
        s.targets.append(TargetApp(bundleID: "md.obsidian", name: "Obsidian", format: .markdown))
        let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        #expect(decoded == s)
    }

    @Test func markdownAndHTMLAgree() {
        let text = "Run  npm test  first"
        #expect(Policy.markdown(for: text) == "Run `npm test` first")
        #expect(Policy.html(for: text) == Renderer.htmlDocument("Run `npm test` first"))
    }
}
