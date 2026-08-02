import Darwin
import Foundation

/// Mutable holder used to carry a value out of a non-escaping async closure.
private final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

/// Coordinates the stages that produce, sign, and optionally notarize a package.
public struct PackageBuildCoordinator: @unchecked Sendable {
    public let fileManager: FileManager
    public let runner: any ProcessRunning
    public let console: Console

    public init(fileManager: FileManager, runner: any ProcessRunning, console: Console) {
        self.fileManager = fileManager
        self.runner = runner
        self.console = console
    }

    @discardableResult
    public func buildPackage(in project: URL, configuration: PackageBuildOptions) async throws -> BuildResult {
        let packageConfiguration = try BuildInfoStore.load(from: project, requestedFormat: configuration.requestedFormat, versionOverride: configuration.versionOverride)
        try Self.validatePackageName(packageConfiguration.name)
        if packageConfiguration.ownership != .recommended, geteuid() != 0 {
            console.warning("build-info ownership: \(packageConfiguration.ownership.rawValue) might require using sudo to build this package.")
        }
        let layout = try PackageProjectLayout(project: project, fileManager: fileManager, outputDirectory: configuration.outputDirectory)
        try layout.createBuildDirectoryIfNeeded()
        let output = layout.buildDirectory.appendingPathComponent(packageConfiguration.name)
        let notarization = Box(NotarizationService.Outcome(accepted: false, stapled: false))
        try await layout.withTemporaryDirectory { temporaryDirectory in
            let scriptsOverride = try applyBuildVariables(to: layout.scripts, project: project, temporaryDirectory: temporaryDirectory, configuration: configuration)
            let context = PackageBuildContext(configuration: packageConfiguration, layout: layout, temporaryDirectory: temporaryDirectory, scriptsOverride: scriptsOverride)
            let scriptPreparer = ScriptPreparer(fileManager: fileManager, console: console)
            if scriptsOverride == nil, let scripts = layout.scripts { try scriptPreparer.prepareScripts(in: scripts) }
            try ComponentPackageBuilder(fileManager: fileManager, runner: runner, console: console)
                .buildComponent(using: context, isQuiet: configuration.isQuiet, skipsSigning: configuration.skipsSigning)
            if configuration.exportsBOM {
                try BOMMetadataService(fileManager: fileManager, runner: runner, console: console)
                    .exportMetadata(from: try packageBOM(for: context.output), to: project)
            }
            if packageConfiguration.usesDistributionStyle {
                try DistributionPackageBuilder(fileManager: fileManager, runner: runner, console: console)
                    .buildDistribution(using: context, isQuiet: configuration.isQuiet, skipsSigning: configuration.skipsSigning)
            }
            guard let notarizationConfig = packageConfiguration.notarization, !configuration.skipsNotarization, !configuration.skipsSigning else { return }
            notarization.value = try await NotarizationService(runner: runner, console: console)
                .notarize(package: context.output, configuration: notarizationConfig, skipsStapling: configuration.skipsStapling)
        }
        let signed = packageConfiguration.signing != nil && !configuration.skipsSigning
        if configuration.verifies {
            let notarized = packageConfiguration.notarization != nil && !configuration.skipsNotarization && !configuration.skipsSigning
            try PackageVerifier(runner: runner, console: console)
                .verify(package: output, expectedIdentifier: packageConfiguration.identifier, expectedVersion: packageConfiguration.version, signed: signed, notarized: notarized)
        }
        if configuration.writesProvenance {
            let provenance = try ProvenanceBuilder(runner: runner, fileManager: fileManager)
                .build(configuration: packageConfiguration, output: output, project: project)
            let sidecar = URL(fileURLWithPath: output.path + ".provenance.json")
            try Data(provenance.jsonString().utf8).write(to: sidecar, options: .atomic)
            console.display("Wrote provenance to \(sidecar.path)")
        }
        return BuildResult(
            name: packageConfiguration.name,
            version: packageConfiguration.version,
            identifier: packageConfiguration.identifier,
            pkgPath: output.path,
            sha256: try sha256Hex(ofFileAt: output),
            signed: signed,
            notarized: notarization.value.accepted,
            stapled: notarization.value.stapled
        )
    }

    /// Loads `.env` + inherited variables and, if any apply, writes substituted
    /// script copies to a private temp dir, returning that directory for the
    /// build to use in place of the originals.
    private func applyBuildVariables(to scripts: URL?, project: URL, temporaryDirectory: URL, configuration: PackageBuildOptions) throws -> URL? {
        guard let scripts else { return nil }

        let envPath: String
        if let explicit = configuration.envFile {
            guard fileManager.fileExists(atPath: explicit) else {
                throw MunkiPkgError.invalidConfiguration("--env-file not found: \(explicit)")
            }
            envPath = explicit
        } else {
            envPath = project.appendingPathComponent(".env").path
        }

        let fileVariables = try EnvLoader.load(from: envPath, console: console)
        let variables = EnvLoader.merge(fileVariables: fileVariables, inheritsEnvironment: configuration.inheritsEnvironment)

        guard !variables.isEmpty else {
            if configuration.strictEnvironment {
                try failOnUnresolved(ScriptEnvironment.unresolvedPlaceholders(in: scripts, given: [:], fileManager: fileManager))
            }
            return nil
        }

        guard let processed = try ScriptEnvironment.process(scriptsDir: scripts, into: temporaryDirectory, with: variables, fileManager: fileManager) else {
            return nil
        }
        if configuration.strictEnvironment {
            try failOnUnresolved(processed.unresolved)
        } else {
            for (script, keys) in processed.unresolved {
                console.warning("\(script): unresolved placeholder(s) \(keys.sorted().joined(separator: ", "))")
            }
        }
        // Report what the pass replaced, not what it loaded. A variable that no
        // script references is the usual sign of a typo in either place, and a
        // count of loaded variables hides it behind an encouraging number.
        let applied = processed.substitutedNames
        if applied.isEmpty {
            console.display("Loaded \(variables.count) build variable(s); no install script referenced any of them")
        } else {
            console.display("Applied \(applied.count) of \(variables.count) build variable(s) to \(processed.substituted.count) install script(s)")
        }
        return processed.directory
    }

    private func failOnUnresolved(_ unresolved: [String: Set<String>]) throws {
        guard !unresolved.isEmpty else { return }
        let detail = unresolved.sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value.sorted().joined(separator: ", "))" }
            .joined(separator: "; ")
        throw MunkiPkgError.invalidConfiguration("Unresolved script placeholders (--strict-env): \(detail)")
    }

    private func packageBOM(for package: URL) throws -> URL {
        let result = try runner.run(executable: ToolPaths.pkgutil, arguments: ["--bom", package.path])
        guard result.status == 0, let path = result.stdoutString.split(whereSeparator: \.isNewline).first else {
            throw MunkiPkgError.processFailed(tool: "pkgutil", message: "pkgutil returned no BOM path")
        }
        return URL(fileURLWithPath: String(path))
    }

    /// Rejects a package `name` that could escape the build directory.
    ///
    /// The output package path is `build/<name>` (and `build/Dist-<name>` for
    /// distribution builds), so a `name` containing a path separator or `..`
    /// would write the artifact outside `build/`. Require a single, safe path
    /// component. Called with the post-`${version}`-substitution name.
    static func validatePackageName(_ name: String) throws {
        guard !name.isEmpty,
              name != ".", name != "..",
              !name.contains("/"),
              !name.contains("\0"),
              URL(fileURLWithPath: name).lastPathComponent == name
        else {
            throw MunkiPkgError.invalidConfiguration(
                "Package name \"\(name)\" must be a single path component (no \"/\" or \"..\")."
            )
        }
    }
}

/// Describes the files and directories involved in one package build.
private struct PackageProjectLayout {
    let project: URL
    let payload: URL?
    let scripts: URL?
    let buildDirectory: URL
    let fileManager: FileManager

    init(project: URL, fileManager: FileManager, outputDirectory: URL? = nil) throws {
        self.project = project
        self.fileManager = fileManager
        let payloadURL = project.appendingPathComponent("payload", isDirectory: true)
        let scriptsURL = project.appendingPathComponent("scripts", isDirectory: true)
        payload = fileManager.directoryExists(at: payloadURL) ? payloadURL : nil
        if fileManager.directoryExists(at: scriptsURL), try !fileManager.contents(at: scriptsURL).filter({ $0 != ".DS_Store" }).isEmpty {
            scripts = scriptsURL
        } else { scripts = nil }
        // A project with neither payload nor scripts is valid: it builds a
        // receipt-only package (pkgbuild --nopayload) that installs no files but
        // records a receipt, which Munki conditions can key off. munki-pkg
        // allows this, so swiftpkg does too.
        buildDirectory = outputDirectory ?? project.appendingPathComponent("build", isDirectory: true)
    }

    func createBuildDirectoryIfNeeded() throws {
        if !fileManager.itemExists(at: buildDirectory) { try fileManager.createDirectory(at: buildDirectory, withIntermediateDirectories: true) }
        else if !fileManager.directoryExists(at: buildDirectory) { throw MunkiPkgError.message("\(buildDirectory.path) is not a directory.") }
    }

    func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = fileManager.temporaryDirectory.appendingPathComponent("swiftpkg-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: directory) }
        try await body(directory)
    }
}

/// Holds immutable paths and settings shared by build stages.
private struct PackageBuildContext {
    let configuration: PackageConfiguration
    let layout: PackageProjectLayout
    let temporaryDirectory: URL
    /// Substituted scripts directory to package instead of `layout.scripts`.
    var scriptsOverride: URL? = nil

    var output: URL { layout.buildDirectory.appendingPathComponent(configuration.name) }
    /// The scripts directory pkgbuild should package.
    var effectiveScripts: URL? { scriptsOverride ?? layout.scripts }
}

/// Normalizes installer scripts before package construction.
private struct ScriptPreparer {
    let fileManager: FileManager
    let console: Console

    func prepareScripts(in scripts: URL) throws {
        let dsStore = scripts.appendingPathComponent(".DS_Store")
        if fileManager.itemExists(at: dsStore) { console.display("Removing .DS_Store file from the scripts folder"); try fileManager.removeItem(at: dsStore) }
        for scriptName in ["preinstall", "postinstall"] {
            let script = scripts.appendingPathComponent(scriptName)
            guard fileManager.itemExists(at: script) else { continue }
            let permissions = (try fileManager.attributesOfItem(atPath: script.path)[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
            if permissions & 0o500 != 0o500 {
                console.display("Making \(scriptName) script executable")
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            }
        }
    }
}

/// Builds a component package with `pkgbuild`.
private struct ComponentPackageBuilder {
    let fileManager: FileManager
    let runner: any ProcessRunning
    let console: Console

    func buildComponent(using context: PackageBuildContext, isQuiet: Bool, skipsSigning: Bool) throws {
        let packageInfo = context.temporaryDirectory.appendingPathComponent("PackageInfo")
        try writePackageInfo(for: context.configuration, to: packageInfo)
        try fileManager.removeIfPresent(at: context.output)
        var arguments = ["--ownership", context.configuration.ownership.rawValue, "--identifier", context.configuration.identifier, "--version", context.configuration.version, "--info", packageInfo.path]
        if let payload = context.layout.payload {
            arguments += ["--root", payload.path]
            if let installLocation = context.configuration.installLocation { arguments += ["--install-location", installLocation] }
            if context.configuration.suppressesBundleRelocation {
                let componentPlist = try componentPropertyList(for: payload, in: context.temporaryDirectory, isQuiet: isQuiet)
                arguments += ["--component-plist", componentPlist.path]
            }
        } else { arguments.append("--nopayload") }
        if let compression = context.configuration.compression { arguments += ["--compression", compression.rawValue] }
        if let minimumOSVersion = context.configuration.minimumOSVersion { arguments += ["--min-os-version", minimumOSVersion] }
        if context.configuration.usesLargePayload { arguments.append("--large-payload") }
        if let scripts = context.effectiveScripts { arguments += ["--scripts", scripts.path] }
        if isQuiet { arguments.append("--quiet") }
        if !context.configuration.usesDistributionStyle, !skipsSigning { appendSigningArguments(&arguments, signing: context.configuration.signing) }
        arguments.append(context.output.path)
        try runner.runSuccessfully(executable: ToolPaths.pkgbuild, arguments: arguments, failureMessage: "Package creation failed.")
    }

    private func writePackageInfo(for configuration: PackageConfiguration, to url: URL) throws {
        if configuration.postInstallAction != .none { console.display("Setting postinstall-action to \(configuration.postInstallAction.rawValue)") }
        let xml = "<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"no\"?><pkg-info postinstall-action=\"\(configuration.postInstallAction.rawValue)\" preserve-xattr=\"\(configuration.preservesExtendedAttributes)\"/>"
        try Data(xml.utf8).write(to: url)
    }

    private func componentPropertyList(for payload: URL, in temporaryDirectory: URL, isQuiet: Bool) throws -> URL {
        let destination = temporaryDirectory.appendingPathComponent("component.plist")
        var arguments = ["--analyze", "--root", payload.path, destination.path]
        if isQuiet { arguments.insert("--quiet", at: 0) }
        try runner.runSuccessfully(executable: ToolPaths.pkgbuild, arguments: arguments, failureMessage: "pkgbuild failed while analyzing payload")
        let data = try Data(contentsOf: destination)
        guard var propertyList = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else {
            throw MunkiPkgError.message("Couldn't read \(destination.path)")
        }
        for index in propertyList.indices where propertyList[index]["BundleIsRelocatable"] as? Bool == true {
            propertyList[index]["BundleIsRelocatable"] = false
            if let path = propertyList[index]["RootRelativeBundlePath"] as? String { console.display("Turning off bundle relocation for \(path)") }
        }
        try PropertyListSerialization.data(fromPropertyList: propertyList, format: .xml, options: 0).write(to: destination)
        return destination
    }
}

/// Builds a distribution package with `productbuild`.
private struct DistributionPackageBuilder {
    let fileManager: FileManager
    let runner: any ProcessRunning
    let console: Console

    func buildDistribution(using context: PackageBuildContext, isQuiet: Bool, skipsSigning: Bool) throws {
        let temporaryOutput = context.layout.buildDirectory.appendingPathComponent("Dist-\(context.configuration.name)")
        try fileManager.removeIfPresent(at: temporaryOutput)
        let distribution = context.temporaryDirectory.appendingPathComponent("Distribution")
        let title = context.configuration.title ?? context.configuration.name
        let xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?><installer-gui-script minSpecVersion=\"1\"><title>\(xmlEscaped(title))</title><options customize=\"never\" require-scripts=\"false\" hostArchitectures=\"arm64,x86_64\"/><choices-outline><line choice=\"default\"/></choices-outline><choice id=\"default\" visible=\"false\"><pkg-ref id=\"default\"/></choice><pkg-ref id=\"default\">\(xmlEscaped(context.configuration.name))</pkg-ref></installer-gui-script>"
        try Data(xml.utf8).write(to: distribution)
        var arguments = ["--distribution", distribution.path, "--package-path", context.layout.buildDirectory.path]
        if isQuiet { arguments.append("--quiet") }
        if !skipsSigning { appendSigningArguments(&arguments, signing: context.configuration.signing) }
        let requirements = context.layout.project.appendingPathComponent("product-requirements.plist")
        if fileManager.itemExists(at: requirements) { arguments += ["--product", requirements.path] }
        arguments += ["--identifier", context.configuration.productIdentifier ?? context.configuration.identifier, "--version", context.configuration.version, temporaryOutput.path]
        try runner.runSuccessfully(executable: ToolPaths.productbuild, arguments: arguments, failureMessage: "Distribution package creation failed.")
        console.display("Removing component package \(context.output.path)")
        try fileManager.removeItem(at: context.output)
        console.display("Renaming distribution package \(temporaryOutput.path) to \(context.output.path)")
        try fileManager.moveItem(at: temporaryOutput, to: context.output)
    }
}

/// Uploads a package to Apple notarization and optionally staples it.
struct NotarizationService: Sendable {
    let runner: any ProcessRunning
    let console: Console

    /// The outcome of a notarization attempt: whether Apple accepted the
    /// submission, and whether the ticket was stapled to the package.
    struct Outcome: Sendable {
        let accepted: Bool
        let stapled: Bool
    }

    /// Uploads the package and always polls for acceptance, then staples when
    /// accepted and stapling was not skipped. Acceptance and stapling are
    /// reported independently so the build manifest reflects what actually
    /// happened rather than what was merely requested.
    func notarize(package: URL, configuration: NotarizationConfiguration, skipsStapling: Bool) async throws -> Outcome {
        if case let .invalid(reason) = configuration.authentication {
            throw MunkiPkgError.invalidConfiguration(reason)
        }
        console.display("Uploading package to Apple notary service")
        let submission = try plistOutput(for: ["notarytool", "submit", "--output-format", "plist", package.path] + authenticationArguments(for: configuration), failureMessage: "Notarization upload failed.")
        guard let identifier = submission["id"] as? String else { throw MunkiPkgError.notarizationFailed("Unexpected output from notarytool") }
        console.display("id \(identifier)", toolName: "notarytool")
        if let message = submission["message"] as? String { console.display(message, toolName: "notarytool") }
        let accepted = try await waitForAcceptance(identifier, configuration: configuration)
        guard accepted, !skipsStapling else { return Outcome(accepted: accepted, stapled: false) }
        console.display("Stapling package")
        try runner.runSuccessfully(executable: ToolPaths.xcrun, arguments: ["stapler", "staple", package.path], failureMessage: "Stapling failed")
        console.display("The staple and validate action worked!")
        return Outcome(accepted: true, stapled: true)
    }

    private func waitForAcceptance(_ identifier: String, configuration: NotarizationConfiguration) async throws -> Bool {
        var elapsed = 0; var delay = 5
        while elapsed < configuration.staplingTimeout {
            try await Task.sleep(for: .seconds(delay))
            elapsed += delay
            delay += 5
            let output = try plistOutput(for: ["notarytool", "info", identifier, "--output-format", "plist"] + authenticationArguments(for: configuration), failureMessage: "Notarization check failed.")
            let status = output["status"] as? String ?? "Unknown"
            let message = output["message"] as? String ?? ""
            if status == "Accepted" { console.display("Notarization successful. \(message)"); return true }
            if status != "In Progress" && status != "Unknown" { throw MunkiPkgError.notarizationFailed("Notarization failed (\(status)): \(message)") }
            console.display("Notarization state: \(status). Trying again in \(delay) seconds")
        }
        throw MunkiPkgError.notarizationFailed("Timeout exceeded (\(configuration.staplingTimeout)s) waiting for notarization to complete. The package was uploaded but never confirmed Accepted, so it was not stapled. Check with 'xcrun notarytool info \(identifier)' and staple manually if it later succeeds.")
    }

    /// Carries notarytool's own explanation through, the way every other
    /// subprocess call does via `runSuccessfully`. Without it a missing keychain
    /// profile — which notarytool names, along with the command that creates it —
    /// surfaces only as "Notarization upload failed."
    private func plistOutput(for arguments: [String], failureMessage: String) throws -> [String: Any] {
        let result: ProcessResult
        do {
            result = try runner.run(executable: ToolPaths.xcrun, arguments: arguments)
        } catch {
            throw MunkiPkgError.notarizationFailed("\(failureMessage) \(error.localizedDescription)")
        }
        guard result.status == 0 else {
            throw MunkiPkgError.notarizationFailed("notarytool: \(result.failureDetail(fallback: failureMessage))")
        }
        let data: Data
        if result.stdoutString.hasPrefix("Generated JWT"), let newline = result.stdoutString.firstIndex(of: "\n") {
            data = Data(result.stdoutString[result.stdoutString.index(after: newline)...].utf8)
        } else {
            data = result.stdout
        }
        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(from: data, format: nil)
        } catch {
            throw MunkiPkgError.notarizationFailed("\(failureMessage) \(error.localizedDescription)")
        }
        guard let plist = object as? [String: Any] else { throw MunkiPkgError.notarizationFailed(failureMessage) }
        return plist
    }

    private func authenticationArguments(for configuration: NotarizationConfiguration) -> [String] {
        switch configuration.authentication {
        case let .appleID(appleID, teamID, password): return ["--apple-id", appleID, "--team-id", teamID, "--password", password]
        case let .keychainProfile(profile): return ["--keychain-profile", profile]
        case .invalid: return []  // notarize(package:...) rejects .invalid before reaching here
        }
    }
}

private func appendSigningArguments(_ arguments: inout [String], signing: SigningConfiguration?) {
    guard let signing else { return }
    arguments += ["--sign", signing.identity]
    if let keychain = signing.keychain { arguments += ["--keychain", expandKeychainPath(keychain)] }
    for certificate in signing.additionalCertificateNames { arguments += ["--cert", certificate] }
    if let usesTimestamp = signing.usesTimestamp { arguments.append(usesTimestamp ? "--timestamp" : "--timestamp=none") }
}

/// Expands `${HOME}` and a leading tilde in a build-info keychain path so that
/// projects written as `${HOME}/Library/Keychains/signing.keychain` resolve to a
/// real path before being handed to `productbuild`/`productsign`. Mirrors the
/// original munki-pkg, whose build-info files rely on this expansion.
func expandKeychainPath(_ path: String) -> String {
    let withHome = path.replacingOccurrences(of: "${HOME}", with: NSHomeDirectory())
    return NSString(string: withHome).expandingTildeInPath
}
