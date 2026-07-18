import Darwin
import Foundation

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

    public func buildPackage(in project: URL, configuration: PackageBuildOptions) async throws {
        let packageConfiguration = try BuildInfoStore.load(from: project, requestedFormat: configuration.requestedFormat)
        if packageConfiguration.ownership != .recommended, geteuid() != 0 {
            console.warning("build-info ownership: \(packageConfiguration.ownership.rawValue) might require using sudo to build this package.")
        }
        let layout = try PackageProjectLayout(project: project, fileManager: fileManager)
        try layout.createBuildDirectoryIfNeeded()
        let output = layout.buildDirectory.appendingPathComponent(packageConfiguration.name)
        try await layout.withTemporaryDirectory { temporaryDirectory in
            let context = PackageBuildContext(configuration: packageConfiguration, layout: layout, temporaryDirectory: temporaryDirectory)
            let scriptPreparer = ScriptPreparer(fileManager: fileManager, console: console)
            if let scripts = layout.scripts { try scriptPreparer.prepareScripts(in: scripts) }
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
            if let notarization = packageConfiguration.notarization, !configuration.skipsNotarization, !configuration.skipsSigning {
                try await NotarizationService(runner: runner, console: console)
                    .notarize(package: context.output, configuration: notarization, skipsStapling: configuration.skipsStapling)
            }
        }
        if configuration.verifies {
            let signed = packageConfiguration.signing != nil && !configuration.skipsSigning
            let notarized = packageConfiguration.notarization != nil && !configuration.skipsNotarization && !configuration.skipsSigning
            try PackageVerifier(runner: runner, console: console)
                .verify(package: output, signed: signed, notarized: notarized)
        }
    }

    private func packageBOM(for package: URL) throws -> URL {
        let result = try runner.run(executable: ToolPaths.pkgutil, arguments: ["--bom", package.path])
        guard result.status == 0, let path = result.stdoutString.split(whereSeparator: \.isNewline).first else {
            throw MunkiPkgError.processFailed(tool: "pkgutil", message: "pkgutil returned no BOM path")
        }
        return URL(fileURLWithPath: String(path))
    }
}

/// Describes the files and directories involved in one package build.
private struct PackageProjectLayout {
    let project: URL
    let payload: URL?
    let scripts: URL?
    let buildDirectory: URL
    let fileManager: FileManager

    init(project: URL, fileManager: FileManager) throws {
        self.project = project
        self.fileManager = fileManager
        let payloadURL = project.appendingPathComponent("payload", isDirectory: true)
        let scriptsURL = project.appendingPathComponent("scripts", isDirectory: true)
        payload = fileManager.directoryExists(at: payloadURL) ? payloadURL : nil
        if fileManager.directoryExists(at: scriptsURL), try !fileManager.contents(at: scriptsURL).filter({ $0 != ".DS_Store" }).isEmpty {
            scripts = scriptsURL
        } else { scripts = nil }
        guard payload != nil || scripts != nil else { throw MunkiPkgError.message("\(project.path) does not contain a payload folder or a scripts folder.") }
        buildDirectory = project.appendingPathComponent("build", isDirectory: true)
    }

    func createBuildDirectoryIfNeeded() throws {
        if !fileManager.itemExists(at: buildDirectory) { try fileManager.createDirectory(at: buildDirectory, withIntermediateDirectories: false) }
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

    var output: URL { layout.buildDirectory.appendingPathComponent(configuration.name) }
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
        if let scripts = context.layout.scripts { arguments += ["--scripts", scripts.path] }
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
private struct NotarizationService: Sendable {
    let runner: any ProcessRunning
    let console: Console

    func notarize(package: URL, configuration: NotarizationConfiguration, skipsStapling: Bool) async throws {
        console.display("Uploading package to Apple notary service")
        let submission = try plistOutput(for: ["notarytool", "submit", "--output-format", "plist", package.path] + authenticationArguments(for: configuration), failureMessage: "Notarization upload failed.")
        guard let identifier = submission["id"] as? String else { throw MunkiPkgError.message("Unexpected output from notarytool") }
        console.display("id \(identifier)", toolName: "notarytool")
        if let message = submission["message"] as? String { console.display(message, toolName: "notarytool") }
        guard !skipsStapling, try await waitForAcceptance(identifier, configuration: configuration) else { return }
        console.display("Stapling package")
        try runner.runSuccessfully(executable: ToolPaths.xcrun, arguments: ["stapler", "staple", package.path], failureMessage: "Stapling failed")
        console.display("The staple and validate action worked!")
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
            if status != "In Progress" && status != "Unknown" { throw MunkiPkgError.message("Notarization failed (\(status)): \(message)") }
            console.display("Notarization state: \(status). Trying again in \(delay) seconds")
        }
        console.warning("Timeout EXCEEDED when waiting for the notarization to complete. You can manually staple the package later if notarization is successful.")
        return false
    }

    private func plistOutput(for arguments: [String], failureMessage: String) throws -> [String: Any] {
        let result = try runner.run(executable: ToolPaths.xcrun, arguments: arguments)
        guard result.status == 0 else { throw MunkiPkgError.processFailed(tool: "notarytool", message: failureMessage) }
        let data: Data
        if result.stdoutString.hasPrefix("Generated JWT"), let newline = result.stdoutString.firstIndex(of: "\n") {
            data = Data(result.stdoutString[result.stdoutString.index(after: newline)...].utf8)
        } else {
            data = result.stdout
        }
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw MunkiPkgError.message(failureMessage) }
        return plist
    }

    private func authenticationArguments(for configuration: NotarizationConfiguration) -> [String] {
        switch configuration.authentication {
        case let .appleID(appleID, teamID, password): return ["--apple-id", appleID, "--team-id", teamID, "--password", password]
        case let .keychainProfile(profile): return ["--keychain-profile", profile]
        }
    }
}

private func appendSigningArguments(_ arguments: inout [String], signing: SigningConfiguration?) {
    guard let signing else { return }
    arguments += ["--sign", signing.identity]
    if let keychain = signing.keychain { arguments += ["--keychain", keychain] }
    for certificate in signing.additionalCertificateNames { arguments += ["--cert", certificate] }
    if let usesTimestamp = signing.usesTimestamp { arguments.append(usesTimestamp ? "--timestamp" : "--timestamp=none") }
}
