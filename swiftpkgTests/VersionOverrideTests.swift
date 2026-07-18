import Foundation
import Testing
@testable import SwiftPkgCore

struct VersionOverrideTests {

    @Test("withVersion changes only the version, before substitution")
    func withVersionChangesOnlyVersion() {
        let base = PackageConfiguration.defaults(for: URL(fileURLWithPath: "/tmp/Thing"))
        let bumped = base.withVersion("9.9")
        #expect(bumped.version == "9.9")
        #expect(bumped.name == base.name) // "${version}" not yet substituted
        #expect(bumped.identifier == base.identifier)
    }

    @Test("load with a version override replaces version and ${version} in name")
    func loadWithOverride() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let project = temp.url.appendingPathComponent("P", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        try write(
            #"{"name":"App-${version}.pkg","identifier":"com.example.app","version":"1.0"}"#,
            to: project.appendingPathComponent("build-info.json")
        )

        let overridden = try BuildInfoStore.load(from: project, requestedFormat: nil, versionOverride: "2.5")
        #expect(overridden.version == "2.5")
        #expect(overridden.name == "App-2.5.pkg")

        let normal = try BuildInfoStore.load(from: project, requestedFormat: nil)
        #expect(normal.version == "1.0")
        #expect(normal.name == "App-1.0.pkg")
    }
}
