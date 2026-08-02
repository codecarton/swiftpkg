import Foundation
import Testing
@testable import SwiftPkgCore

/// Exercises the real SystemProcessRunner (not RecordingRunner) — these guard
/// the concurrent pipe-drain that prevents a large-output deadlock.
struct SystemProcessRunnerTests {

    // ~1.1 MB of stdout, far past the ~64 KB pipe buffer. A runner that waits
    // before draining (or drains sequentially) would hang here forever.
    @Test("captures large stdout completely and in order")
    func capturesLargeStdout() throws {
        let result = try SystemProcessRunner().run(executable: "/usr/bin/seq", arguments: ["1", "200000"])
        #expect(result.status == 0)
        let lines = result.stdoutString.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.isEmpty }
        #expect(lines.count == 200_000)
        #expect(lines.first == "1")
        #expect(lines.last == "200000")
    }

    @Test("separates stderr and reports non-zero status")
    func separatesStderr() throws {
        let result = try SystemProcessRunner().run(executable: "/bin/ls", arguments: ["/no/such/path/swiftpkg-test-xyz"])
        #expect(result.status != 0)
        #expect(result.stdout.isEmpty)
        #expect(!result.stderrString.isEmpty)
    }

    @Test("reports a structured error when the executable cannot launch")
    func reportsLaunchFailure() {
        #expect(throws: MunkiPkgError.self) {
            try SystemProcessRunner().run(executable: "/nonexistent/tool/swiftpkg-should-not-exist", arguments: [])
        }
    }
}
