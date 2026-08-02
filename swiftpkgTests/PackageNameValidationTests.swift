import Foundation
import Testing
@testable import SwiftPkgCore

struct PackageNameValidationTests {

    @Test("rejects names that escape the build directory", arguments: [
        "../evil.pkg",
        "../../tmp/evil.pkg",
        "sub/dir/evil.pkg",
        "/etc/evil.pkg",
        "..",
        ".",
        "",
    ])
    func rejectsUnsafeNames(_ name: String) {
        #expect(throws: MunkiPkgError.self) {
            try PackageBuildCoordinator.validatePackageName(name)
        }
    }

    @Test("accepts safe single-component names", arguments: [
        "MyApp-1.0.pkg",
        "com.example.thing.pkg",
        "package_2026.07.18.pkg",
        "no-extension",
    ])
    func acceptsSafeNames(_ name: String) throws {
        try PackageBuildCoordinator.validatePackageName(name)
    }

    // End-to-end: a malicious build-info name must fail before pkgbuild runs.
    @Test("build with a traversal name throws and never invokes pkgbuild")
    func buildRejectsTraversalNameBeforeRunning() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let project = temp.url.appendingPathComponent("Evil", isDirectory: true)
        let payload = project.appendingPathComponent("payload", isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        try write("payload", to: payload.appendingPathComponent("file.txt"))
        try write(
            #"{"name":"../evil.pkg","identifier":"com.test.evil","version":"1.0"}"#,
            to: project.appendingPathComponent("build-info.json")
        )

        let runner = RecordingRunner()
        let coordinator = PackageBuildCoordinator(fileManager: .default, runner: runner, console: makeConsole())
        await #expect(throws: MunkiPkgError.self) {
            try await coordinator.buildPackage(in: project, configuration: PackageBuildOptions())
        }
        #expect(runner.calls.isEmpty)
    }
}
