import Foundation

// Build-time variable substitution for install scripts.
//
// IMPORTANT: substituted values are embedded verbatim in scripts, which end up
// as plain text inside the resulting .pkg (readable via `pkgutil --expand`).
// This is for build-time variables (server URLs, org identifiers, version
// metadata) — NOT for secrets. For runtime secrets, fetch from Keychain or an
// MDM-delivered profile inside the script itself.

/// Loads and merges build-time variables from a `.env` file.
public enum EnvLoader {
    /// Maximum `.env` file size (1 MB); larger files are rejected.
    public static let maxFileSize = 1_048_576

    /// Process-environment prefix whose variables are merged in by default.
    public static let inheritedPrefix = "SWIFTPKG_"

    private static let keyPattern = try! NSRegularExpression(pattern: #"^[A-Za-z_][A-Za-z0-9_]*$"#)

    /// Parses a `.env` file into key/value pairs. Returns empty if the file is
    /// absent. Throws on unreadable files or ones over `maxFileSize`.
    public static func load(from path: String, console: Console? = nil) throws -> [String: String] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else { return [:] }

        let attributes = try fileManager.attributesOfItem(atPath: path)
        if let size = attributes[.size] as? Int, size > maxFileSize {
            throw MunkiPkgError.invalidConfiguration("Environment file exceeds the \(maxFileSize)-byte limit: \(path)")
        }
        if let permissions = attributes[.posixPermissions] as? Int, permissions & 0o044 != 0 {
            console?.warning("environment file \(path) is group- or world-readable (mode 0\(String(permissions, radix: 8))). Recommend `chmod 600 \(path)`.")
        }

        guard let data = fileManager.contents(atPath: path), let content = String(data: data, encoding: .utf8) else {
            throw MunkiPkgError.invalidConfiguration("Failed to read environment file: \(path)")
        }

        var variables: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<equals]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            if keyPattern.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) == nil {
                console?.warning("skipping environment entry with invalid key: '\(key)'")
                continue
            }
            var value = String(trimmed[trimmed.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            variables[key] = value
        }
        return variables
    }

    /// Merges `.env` values over `SWIFTPKG_*` process-environment variables.
    /// `.env` values win. `environment` is injectable for testing.
    public static func merge(
        fileVariables: [String: String],
        inheritsEnvironment: Bool = true,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var merged: [String: String] = [:]
        if inheritsEnvironment {
            for (key, value) in environment where key.hasPrefix(inheritedPrefix) { merged[key] = value }
        }
        for (key, value) in fileVariables { merged[key] = value }
        return merged
    }
}

/// Replaces `${VAR}` placeholders in script content in a single pass, so a
/// substituted value containing placeholder syntax is never re-expanded.
public enum PlaceholderReplacer {
    public struct Result: Sendable {
        public let content: String
        /// Placeholder names present in the script with no matching variable.
        public let unresolved: Set<String>
    }

    private static let pattern = try! NSRegularExpression(pattern: #"\$\{([A-Za-z_][A-Za-z0-9_]*)\}"#)

    public static func replace(in content: String, with variables: [String: String]) -> Result {
        let ns = content as NSString
        let matches = pattern.matches(in: content, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return Result(content: content, unresolved: []) }

        let output = NSMutableString()
        var cursor = 0
        var unresolved: Set<String> = []
        for match in matches {
            let range = match.range
            if range.location > cursor {
                output.append(ns.substring(with: NSRange(location: cursor, length: range.location - cursor)))
            }
            let key = ns.substring(with: match.range(at: 1))
            if let value = variables[key] {
                output.append(value)
            } else {
                output.append(ns.substring(with: range))
                unresolved.insert(key)
            }
            cursor = range.location + range.length
        }
        if cursor < ns.length {
            output.append(ns.substring(with: NSRange(location: cursor, length: ns.length - cursor)))
        }
        return Result(content: output as String, unresolved: unresolved)
    }
}

/// Applies build variables to a project's scripts, writing substituted copies to
/// a private temp directory so pkgbuild packages those instead of the originals.
public enum ScriptEnvironment {
    static let scriptNames: Set<String> = ["preinstall", "postinstall", "preupgrade", "postupgrade", "preexpansion"]

    private static func isScript(_ name: String) -> Bool {
        scriptNames.contains(name) || name.hasSuffix(".sh") || name.hasSuffix(".py")
    }

    /// Returns placeholder names referenced by any script but not in `variables`.
    public static func unresolvedPlaceholders(in scriptsDir: URL, given variables: [String: String], fileManager: FileManager = .default) -> [String: Set<String>] {
        let contents = (try? fileManager.contentsOfDirectory(atPath: scriptsDir.path)) ?? []
        var byScript: [String: Set<String>] = [:]
        for name in contents where isScript(name) {
            let path = scriptsDir.appendingPathComponent(name).path
            guard let data = fileManager.contents(atPath: path), let text = String(data: data, encoding: .utf8) else { continue }
            let unresolved = PlaceholderReplacer.replace(in: text, with: variables).unresolved
            if !unresolved.isEmpty { byScript[name] = unresolved }
        }
        return byScript
    }

    /// Copies scripts into `<tempDir>/env-scripts` (mode 0700), substituting
    /// `${VAR}` placeholders. Returns the processed directory and any unresolved
    /// placeholders, or nil when there is nothing to substitute.
    public static func process(scriptsDir: URL, into tempDir: URL, with variables: [String: String], fileManager: FileManager = .default) throws -> (directory: URL, unresolved: [String: Set<String>])? {
        guard !variables.isEmpty else { return nil }
        let contents = (try? fileManager.contentsOfDirectory(atPath: scriptsDir.path))?.filter { $0 != ".DS_Store" } ?? []
        guard !contents.isEmpty else { return nil }

        let processedDir = tempDir.appendingPathComponent("env-scripts", isDirectory: true)
        try fileManager.createDirectory(at: processedDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tempDir.path)

        var unresolvedByScript: [String: Set<String>] = [:]
        for name in contents {
            let source = scriptsDir.appendingPathComponent(name)
            let destination = processedDir.appendingPathComponent(name)
            if isScript(name), let data = fileManager.contents(atPath: source.path), let text = String(data: data, encoding: .utf8) {
                let result = PlaceholderReplacer.replace(in: text, with: variables)
                try Data(result.content.utf8).write(to: destination, options: .atomic)
                if !result.unresolved.isEmpty { unresolvedByScript[name] = result.unresolved }
                // Keep values non-world-readable during the build; force owner-exec
                // since pkgbuild requires runnable scripts.
                let sourcePermissions = ((try? fileManager.attributesOfItem(atPath: source.path))?[.posixPermissions] as? Int) ?? 0o700
                try fileManager.setAttributes([.posixPermissions: (sourcePermissions & 0o700) | 0o100], ofItemAtPath: destination.path)
            } else {
                try fileManager.copyItem(at: source, to: destination)
            }
        }
        return (processedDir, unresolvedByScript)
    }
}
