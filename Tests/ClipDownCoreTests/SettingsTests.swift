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

@Suite(.serialized) struct SettingsStoreTests {
    @Test func concurrentEditsAreNotLost() async {
        SettingsStore.testDomain = "com.omarshahine.clipdown.tests"
        defer {
            UserDefaults().removePersistentDomain(forName: "com.omarshahine.clipdown.tests")
            SettingsStore.testDomain = nil
        }
        SettingsStore.save(Settings())
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    SettingsStore.edit { $0.targets.append(TargetApp(bundleID: "test.\(i)", name: "T\(i)", format: .markdown)) }
                }
            }
        }
        #expect(Set(SettingsStore.load().targets.map(\.bundleID)).isSuperset(of: (0..<20).map { "test.\($0)" }))
    }
}
