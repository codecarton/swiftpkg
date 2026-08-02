import Foundation

/// One problem found by `--lint`.
public struct LintFinding: Sendable, Equatable {
    public enum Severity: String, Sendable {
        case error
        case warning
    }

    public let severity: Severity
    public let message: String

    public init(_ severity: Severity, _ message: String) {
        self.severity = severity
        self.message = message
    }
}

/// Validates a package project without building it, for fast PR/CI pre-checks.
public struct Linter {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Returns findings. A `.error` means the project should not build; a
    /// `.warning` is advisory. Throws only when the project can't be read at all
    /// (missing directory / undecodable build-info), which is itself a failure.
    public func lint(project: URL, requestedFormat: BuildInfoFormat?) throws -> [LintFinding] {
        guard fileManager.directoryExists(at: project) else {
            throw MunkiPkgError.message("\(project.path): Project not found.")
        }
        var findings: [LintFinding] = []

        // Decoding failures throw MunkiPkgError; surface them as a lint error
        // rather than a crash so `--lint` always produces a report.
        let configuration: PackageConfiguration
        do {
            configuration = try BuildInfoStore.load(from: project, requestedFormat: requestedFormat)
        } catch let error as MunkiPkgError {
            return [LintFinding(.error, error.description)]
        }

        if configuration.identifier.isEmpty {
            findings.append(LintFinding(.error, "identifier is empty"))
        } else if !Self.isReverseDNS(configuration.identifier) {
            findings.append(LintFinding(.warning, "identifier \"\(configuration.identifier)\" is not reverse-DNS style"))
        }

        if configuration.version.isEmpty {
            findings.append(LintFinding(.error, "version is empty"))
        }

        // A missing .pkg extension is not flagged: the build normalizes the
        // resolved name to end in .pkg (matching munki-pkg), so it is harmless.
        if configuration.name.isEmpty || configuration.name.contains("/") || configuration.name == "." || configuration.name == ".." {
            findings.append(LintFinding(.error, "name \"\(configuration.name)\" must be a single path component"))
        }

        if configuration.notarization != nil, configuration.signing == nil {
            findings.append(LintFinding(.warning, "notarization is configured but signing is not; notarization requires a Developer ID signature"))
        }

        let payload = project.appendingPathComponent("payload", isDirectory: true)
        let scripts = project.appendingPathComponent("scripts", isDirectory: true)
        let hasPayload = fileManager.directoryExists(at: payload)
        let hasScripts = fileManager.directoryExists(at: scripts)
            && ((try? fileManager.contents(at: scripts).contains { $0 != ".DS_Store" }) ?? false)
        if !hasPayload, !hasScripts {
            findings.append(LintFinding(.error, "project has neither a payload directory nor a non-empty scripts directory"))
        }

        if hasScripts {
            findings.append(contentsOf: lintScripts(in: scripts))
        }

        return findings
    }

    /// Reverse-DNS means at least two dot-separated, non-empty components, so
    /// leading, repeated, and trailing dots (`.a`, `a..b`, `a.b.`) are rejected.
    static func isReverseDNS(_ identifier: String) -> Bool {
        let components = identifier.split(separator: ".", omittingEmptySubsequences: false)
        return components.count >= 2 && components.allSatisfy { !$0.isEmpty }
    }

    private func lintScripts(in scripts: URL) -> [LintFinding] {
        var findings: [LintFinding] = []
        for name in ["preinstall", "postinstall"] {
            let script = scripts.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: script.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                findings.append(LintFinding(.error, "\(name) is a directory, but an install script must be a regular file"))
                continue
            }
            if let data = fileManager.contents(atPath: script.path), !data.starts(with: Data("#!".utf8)) {
                findings.append(LintFinding(.warning, "\(name) script does not start with a shebang (#!)"))
            }
            let permissions = (try? fileManager.attributesOfItem(atPath: script.path)[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
            if permissions & 0o111 == 0 {
                findings.append(LintFinding(.warning, "\(name) script is not executable"))
            }
        }
        return findings
    }
}
