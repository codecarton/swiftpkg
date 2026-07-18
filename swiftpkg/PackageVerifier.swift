import Foundation

/// Post-build verification: asserts the finished package matches what build-info
/// declared. A belt-and-suspenders companion to the notarization failure checks.
struct PackageVerifier {
    let runner: any ProcessRunning
    let console: Console

    /// - Parameters:
    ///   - signed: signing was requested, so a valid signature must be present.
    ///   - notarized: notarization was requested, so Gatekeeper must accept it.
    func verify(package: URL, signed: Bool, notarized: Bool) throws {
        if signed {
            let result = try runner.run(executable: ToolPaths.pkgutil, arguments: ["--check-signature", package.path])
            guard result.status == 0 else {
                throw MunkiPkgError.message("Verification failed: package is not validly signed. \(diagnostics(result))")
            }
            console.display("Verified package signature")
        }
        if notarized {
            let result = try runner.run(executable: ToolPaths.spctl, arguments: ["-a", "-vvv", "-t", "install", package.path])
            guard result.status == 0 else {
                throw MunkiPkgError.message("Verification failed: package does not pass Gatekeeper assessment. \(diagnostics(result))")
            }
            console.display("Verified Gatekeeper assessment")
        }
    }

    private func diagnostics(_ result: ProcessResult) -> String {
        let text = (result.stderrString + result.stdoutString).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "(no output)" : text
    }
}
