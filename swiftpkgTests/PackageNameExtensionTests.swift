import Foundation
import Testing
@testable import SwiftPkgCore

struct PackageNameExtensionTests {
    private var defaults: PackageConfiguration { .defaults(for: URL(fileURLWithPath: "/tmp/Proj")) }

    private func config(name: String, version: String = "1.0") throws -> PackageConfiguration {
        try PackageConfiguration(
            values: ["name": name, "identifier": "com.example.proj", "version": version],
            defaults: defaults
        )
    }

    @Test("a name without .pkg gains the extension")
    func appendsExtension() throws {
        let resolved = try config(name: "MunkiBootstrap").substitutingVersion()
        #expect(resolved.name == "MunkiBootstrap.pkg")
    }

    @Test("a name already ending in .pkg is left unchanged")
    func keepsExtension() throws {
        let resolved = try config(name: "AdminDock.pkg").substitutingVersion()
        #expect(resolved.name == "AdminDock.pkg")
    }

    @Test("the extension is appended after ${version} substitution")
    func appendsAfterVersionSubstitution() throws {
        let resolved = try config(name: "Tool-${version}", version: "2.3").substitutingVersion()
        #expect(resolved.name == "Tool-2.3.pkg")
    }
}
