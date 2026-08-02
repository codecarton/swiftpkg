import Foundation
import Testing
@testable import SwiftPkgCore
@testable import swiftpkg

struct ExitCodeTests {

    @Test("each error class maps to its documented exit code")
    func errorExitCodes() {
        #expect(MunkiPkgError.message("x").exitCode == 1)
        #expect(MunkiPkgError.projectExists("x").exitCode == 2)
        #expect(MunkiPkgError.invalidConfiguration("x").exitCode == 3)
        #expect(MunkiPkgError.importFailed("x").exitCode == 4)
        #expect(MunkiPkgError.processFailed(tool: "t", message: "m").exitCode == 5)
        #expect(MunkiPkgError.notarizationFailed("x").exitCode == 7)
    }

    @Test("unknown errors default to exit 1")
    func unknownErrorDefault() {
        struct Other: Error {}
        #expect(exitCode(for: Other()) == 1)
        #expect(exitCode(for: MunkiPkgError.notarizationFailed("x")) == 7)
    }

    // End-to-end through the CLI entry point.
    @Test("create on an existing directory exits 2")
    func createExistingExitsTwo() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let project = temp.url.appendingPathComponent("Existing", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        let code = await SwiftPkg.run(arguments: ["--create", project.path])
        #expect(code == 2)
    }

    @Test("building a nonexistent project is a general error (1)")
    func buildMissingProjectExitsOne() async {
        let code = await SwiftPkg.run(arguments: ["/no/such/swiftpkg-project-xyz"])
        #expect(code == 1)
    }

    @Test("conflicting format flags are a usage error (64)")
    func usageErrorExit() async {
        let code = await SwiftPkg.run(arguments: ["--json", "--yaml", "/tmp/whatever"])
        #expect(code == usageErrorExitCode)
    }
}
