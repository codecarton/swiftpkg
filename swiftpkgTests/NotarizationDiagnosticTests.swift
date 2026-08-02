import Foundation
import Testing
@testable import SwiftPkgCore

struct NotarizationDiagnosticTests {

    private func result(status: Int32, stdout: String = "", stderr: String = "") -> ProcessResult {
        ProcessResult(status: status, stdout: Data(stdout.utf8), stderr: Data(stderr.utf8))
    }

    /// The failure that cost a CI investigation: notarytool names the missing
    /// profile and the command that creates it, and that must reach the user.
    @Test("a missing keychain profile keeps notarytool's explanation")
    func missingKeychainProfileIsExplained() {
        let stderr = """
        Error: No Keychain password item found for profile: notarization_credentials
        Run 'notarytool store-credentials' to create another credential profile.
        """
        let message = result(status: 1, stderr: stderr).failureDetail(fallback: "Notarization upload failed.")
        #expect(message.contains("Notarization upload failed."))
        #expect(message.contains("notarization_credentials"))
        #expect(message.contains("store-credentials"))
    }

    @Test("falls back to stdout when the tool reports on stdout instead")
    func fallsBackToStdout() {
        let message = result(status: 1, stdout: "Submission not found").failureDetail(fallback: "Notarization check failed.")
        #expect(message == "Notarization check failed. Submission not found")
    }

    @Test("stderr wins when the tool writes to both")
    func stderrWins() {
        let message = result(status: 1, stdout: "noise", stderr: "the real cause").failureDetail(fallback: "failed.")
        #expect(message == "failed. the real cause")
    }

    @Test("a silent failure still yields the base message, with no trailing space")
    func silentFailureKeepsBaseMessage() {
        #expect(result(status: 1).failureDetail(fallback: "Notarization upload failed.") == "Notarization upload failed.")
        #expect(result(status: 1, stderr: "   \n  ").failureDetail(fallback: "failed.") == "failed.")
    }
}
