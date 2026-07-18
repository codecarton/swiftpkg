import Foundation
import Testing
@testable import SwiftPkgCore

/// Returns a scripted sequence of results, one per call, recording each call.
private final class ScriptedRunner: ProcessRunning, @unchecked Sendable {
    private var results: [ProcessResult]
    private(set) var calls: [(executable: String, arguments: [String])] = []

    init(_ results: [ProcessResult]) { self.results = results }

    func run(executable: String, arguments: [String]) throws -> ProcessResult {
        calls.append((executable, arguments))
        return results.isEmpty ? ProcessResult(status: 0, stdout: Data(), stderr: Data()) : results.removeFirst()
    }
}

private func plistResult(_ dictionary: [String: Any]) throws -> ProcessResult {
    ProcessResult(
        status: 0,
        stdout: try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0),
        stderr: Data()
    )
}

struct NotarizationServiceTests {

    // The core of this change: a notarization that never resolves must fail the
    // build, not warn and exit 0 with an un-stapled package. staplingTimeout: 0
    // triggers the timeout path immediately with no sleep.
    @Test("timeout waiting for notarization throws instead of succeeding silently")
    func timeoutThrows() async throws {
        let runner = ScriptedRunner([try plistResult(["id": "submission-abc"])])
        let configuration = NotarizationConfiguration(authentication: .keychainProfile("profile"), staplingTimeout: 0)
        await #expect(throws: MunkiPkgError.self) {
            try await NotarizationService(runner: runner, console: Console(quiet: true))
                .notarize(package: URL(fileURLWithPath: "/tmp/does-not-matter.pkg"), configuration: configuration, skipsStapling: false)
        }
    }

    // Guard against over-correction: an Accepted submission must still staple.
    // (Costs one ~5s poll sleep — the wait loop's minimum delay.)
    @Test("accepted notarization still staples the package")
    func acceptedStaples() async throws {
        let runner = ScriptedRunner([
            try plistResult(["id": "submission-abc"]),
            try plistResult(["status": "Accepted", "message": "ok"]),
            ProcessResult(status: 0, stdout: Data(), stderr: Data()),
        ])
        let configuration = NotarizationConfiguration(authentication: .keychainProfile("profile"), staplingTimeout: 60)
        try await NotarizationService(runner: runner, console: Console(quiet: true))
            .notarize(package: URL(fileURLWithPath: "/tmp/does-not-matter.pkg"), configuration: configuration, skipsStapling: false)
        #expect(runner.calls.count == 3)
        #expect(runner.calls.last?.arguments.contains("staple") == true)
    }
}
