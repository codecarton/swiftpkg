import Darwin
import Foundation

struct BuildContext {
    var info: BuildInfo
    let project: URL
    let payload: URL?
    let scripts: URL?
    let buildDirectory: URL
    let temporaryDirectory: URL
    var componentPlist: URL?
    var packageInfo: URL

    var output: URL { buildDirectory.appendingPathComponent(info.string("name")!) }
}

struct PackageBuilder {
    let fileManager: FileManager
    let runner: any ProcessRunning
    let console: Console

    func build(project: URL, options: CLIOptions) throws {
        let info = try BuildInfoIO.load(project: project, options: options)
        if ["preserve", "preserve-other"].contains(info.string("ownership") ?? ""), geteuid() != 0 {
            console.warning("build-info ownership: \(info.string("ownership")!) might require using sudo to build this package.")
        }
        let payloadURL = project.appendingPathComponent("payload", isDirectory: true)
        let scriptsURL = project.appendingPathComponent("scripts", isDirectory: true)
        let payload = fileManager.directoryExists(at: payloadURL) ? payloadURL : nil
        var scripts: URL? = fileManager.directoryExists(at: scriptsURL) ? scriptsURL : nil
        if let scriptsURL = scripts {
            let entries = try fileManager.contents(at: scriptsURL).filter { $0 != ".DS_Store" }
            if entries.isEmpty { scripts = nil }
        }
        guard payload != nil || scripts != nil else {
            throw MunkiPkgError.message("\(project.path) does not contain a payload folder or a scripts folder.")
        }
        let buildDirectory = project.appendingPathComponent("build", isDirectory: true)
        if !fileManager.itemExists(at: buildDirectory) {
            try fileManager.createDirectory(at: buildDirectory, withIntermediateDirectories: false)
        } else if !fileManager.directoryExists(at: buildDirectory) {
            throw MunkiPkgError.message("\(buildDirectory.path) is not a directory.")
        }
        let temporary = fileManager.temporaryDirectory.appendingPathComponent("swiftpkg-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: temporary) }

        var context = BuildContext(
            info: info, project: project, payload: payload, scripts: scripts,
            buildDirectory: buildDirectory, temporaryDirectory: temporary,
            componentPlist: nil, packageInfo: temporary.appendingPathComponent("PackageInfo")
        )
        if let payload, info.bool("suppress_bundle_relocation") {
            context.componentPlist = try makeComponentPropertyList(payload: payload, temporary: temporary, quiet: options.quiet)
        }
        try makePackageInfo(info: info, at: context.packageInfo)
        try fileManager.removeIfPresent(at: context.output)
        if let scripts { try prepareScripts(scripts) }
        try buildComponent(context, options: options)
        if options.exportBOMInfo { try exportBOM(context) }
        if info.bool("distribution_style") { try buildDistribution(context, options: options) }
        if info.dictionary("notarization_info") != nil, !options.skipNotarization, !options.skipSigning {
            let requestID = try uploadToNotary(context, options: options)
            if !options.skipStapling, try waitForNotarization(requestID, context: context, options: options) {
                try staple(context, options: options)
            }
        }
    }

    private func makeComponentPropertyList(payload: URL, temporary: URL, quiet: Bool) throws -> URL {
        let destination = temporary.appendingPathComponent("component.plist")
        var arguments: [String] = []
        if quiet { arguments.append("--quiet") }
        arguments += ["--analyze", "--root", payload.path, destination.path]
        try requireSuccess(ToolPaths.pkgbuild, arguments, failure: "pkgbuild failed while analyzing payload")
        let data = try Data(contentsOf: destination)
        guard var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else {
            throw MunkiPkgError.message("Couldn't read \(destination.path)")
        }
        for index in plist.indices where plist[index]["BundleIsRelocatable"] as? Bool == true {
            plist[index]["BundleIsRelocatable"] = false
            if let path = plist[index]["RootRelativeBundlePath"] as? String {
                console.display("Turning off bundle relocation for \(path)")
            }
        }
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: destination)
        return destination
    }

    private func makePackageInfo(info: BuildInfo, at url: URL) throws {
        let action = info.string("postinstall_action") ?? "none"
        if action != "none" { console.display("Setting postinstall-action to \(action)") }
        let preserve = info.bool("preserve_xattr") ? "true" : "false"
        let xml = "<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"no\"?><pkg-info postinstall-action=\"\(xmlEscaped(action))\" preserve-xattr=\"\(preserve)\"/>"
        try Data(xml.utf8).write(to: url)
    }

    private func prepareScripts(_ scripts: URL) throws {
        let dsStore = scripts.appendingPathComponent(".DS_Store")
        if fileManager.itemExists(at: dsStore) {
            console.display("Removing .DS_Store file from the scripts folder")
            try fileManager.removeItem(at: dsStore)
        }
        for name in ["preinstall", "postinstall"] {
            let script = scripts.appendingPathComponent(name)
            guard fileManager.itemExists(at: script) else { continue }
            let attributes = try fileManager.attributesOfItem(atPath: script.path)
            let current = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
            if current & 0o500 != 0o500 {
                console.display("Making \(name) script executable")
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            }
        }
    }

    private func buildComponent(_ context: BuildContext, options: CLIOptions) throws {
        let info = context.info
        var args = [
            "--ownership", info.string("ownership")!,
            "--identifier", info.string("identifier")!,
            "--version", info.string("version")!,
            "--info", context.packageInfo.path
        ]
        if let payload = context.payload {
            args += ["--root", payload.path]
            if let location = info.string("install_location") { args += ["--install-location", location] }
        } else { args.append("--nopayload") }
        if let compression = info.string("compression") { args += ["--compression", compression] }
        if let component = context.componentPlist { args += ["--component-plist", component.path] }
        if let minimum = info.string("min-os-version") { args += ["--min-os-version", minimum] }
        if info.bool("large-payload") { args.append("--large-payload") }
        if let scripts = context.scripts { args += ["--scripts", scripts.path] }
        if options.quiet { args.append("--quiet") }
        if !info.bool("distribution_style") { try addSigningOptions(to: &args, info: info, options: options) }
        args.append(context.output.path)
        try requireSuccess(ToolPaths.pkgbuild, args, failure: "Package creation failed.")
    }

    private func buildDistribution(_ context: BuildContext, options: CLIOptions) throws {
        let temporaryOutput = context.buildDirectory.appendingPathComponent("Dist-\(context.info.string("name")!)")
        try fileManager.removeIfPresent(at: temporaryOutput)
        let distribution = context.temporaryDirectory.appendingPathComponent("Distribution")
        let name = context.info.string("name")!
        let title = context.info.string("title") ?? name
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <installer-gui-script minSpecVersion="1">
            <title>\(xmlEscaped(title))</title>
            <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
            <choices-outline><line choice="default"/></choices-outline>
            <choice id="default" visible="false"><pkg-ref id="default"/></choice>
            <pkg-ref id="default">\(xmlEscaped(name))</pkg-ref>
        </installer-gui-script>
        """
        try Data(xml.utf8).write(to: distribution)
        var args = ["--distribution", distribution.path, "--package-path", context.buildDirectory.path]
        if options.quiet { args.append("--quiet") }
        try addSigningOptions(to: &args, info: context.info, options: options)
        let requirements = context.project.appendingPathComponent("product-requirements.plist")
        if fileManager.itemExists(at: requirements) { args += ["--product", requirements.path] }
        args += [
            "--identifier", context.info.string("product id") ?? context.info.string("identifier")!,
            "--version", context.info.string("version")!, temporaryOutput.path
        ]
        try requireSuccess(ToolPaths.productbuild, args, failure: "Distribution package creation failed.")
        console.display("Removing component package \(context.output.path)")
        try fileManager.removeItem(at: context.output)
        console.display("Renaming distribution package \(temporaryOutput.path) to \(context.output.path)")
        try fileManager.moveItem(at: temporaryOutput, to: context.output)
    }

    private func addSigningOptions(to args: inout [String], info: BuildInfo, options: CLIOptions) throws {
        guard let signing = info.dictionary("signing_info"), !options.skipSigning else { return }
        console.display("Adding package signing info to command")
        guard let identity = signing["identity"] as? String else {
            throw MunkiPkgError.message("Missing identity in signing info!")
        }
        args += ["--sign", identity]
        if let keychain = signing["keychain"] as? String { args += ["--keychain", keychain] }
        if let certificate = signing["additional_cert_names"] as? String { args += ["--cert", certificate] }
        if let certificates = signing["additional_cert_names"] as? [String] {
            for certificate in certificates { args += ["--cert", certificate] }
        }
        if let timestamp = signing["timestamp"] as? Bool { args.append(timestamp ? "--timestamp" : "--timestamp=none") }
    }

    private func exportBOM(_ context: BuildContext) throws {
        console.display("Extracting bom file from \(context.output.path)")
        let result = try runner.run(ToolPaths.pkgutil, ["--bom", context.output.path])
        guard result.status == 0 else { throw MunkiPkgError.message(result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let bomPath = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bomPath.isEmpty else { throw MunkiPkgError.message("pkgutil returned no BOM path") }
        console.display("Exporting bom info to \(context.project.appendingPathComponent("Bom.txt").path)")
        try ProjectOperations(fileManager: fileManager, runner: runner, console: console)
            .exportBOM(from: URL(fileURLWithPath: bomPath), project: context.project)
        try? fileManager.removeItem(atPath: bomPath)
    }

    private func authenticationArguments(_ info: BuildInfo) throws -> [String] {
        guard let notary = info.dictionary("notarization_info") else { throw MunkiPkgError.message("Missing notarization_info") }
        if let appleID = notary["apple_id"] as? String,
           let teamID = notary["team_id"] as? String,
           let password = notary["password"] as? String {
            return ["--apple-id", appleID, "--team-id", teamID, "--password", password]
        }
        if let profile = notary["keychain_profile"] as? String { return ["--keychain-profile", profile] }
        throw MunkiPkgError.message("apple_id + team_id + password or keychain_profile must be specified in notarization_info.")
    }

    private func uploadToNotary(_ context: BuildContext, options: CLIOptions) throws -> String {
        console.display("Uploading package to Apple notary service")
        let args = ["notarytool", "submit", "--output-format", "plist", context.output.path] + (try authenticationArguments(context.info))
        let output = try runNotary(args, failure: "Notarization upload failed.")
        guard let id = output["id"] as? String else { throw MunkiPkgError.message("Unexpected output from notarytool") }
        console.display("id \(id)", toolName: "notarytool")
        if let message = output["message"] as? String { console.display(message, toolName: "notarytool") }
        return id
    }

    private func waitForNotarization(_ id: String, context: BuildContext, options: CLIOptions) throws -> Bool {
        console.display("Getting notarization state")
        let notary = context.info.dictionary("notarization_info") ?? [:]
        let timeout = (notary["staple_timeout"] as? NSNumber)?.intValue ?? 300
        var elapsed = 0
        var delay = 5
        while elapsed < timeout {
            Thread.sleep(forTimeInterval: TimeInterval(delay))
            elapsed += delay
            delay += 5
            let args = ["notarytool", "info", id, "--output-format", "plist"] + (try authenticationArguments(context.info))
            let output = try runNotary(args, failure: "Notarization check failed.")
            let status = output["status"] as? String ?? "Unknown"
            let message = output["message"] as? String ?? ""
            if status == "Accepted" {
                console.display("Notarization successful. \(message)")
                return true
            }
            if status != "In Progress" && status != "Unknown" {
                throw MunkiPkgError.message("Notarization failed (\(status)): \(message)")
            }
            console.display("Notarization state: \(status). Trying again in \(delay) seconds")
        }
        FileHandle.standardError.write(Data("swiftpkg: Timeout EXCEEDED when waiting for the notarization to complete. You can manually staple the package later if notarization is successful.\n".utf8))
        return false
    }

    private func runNotary(_ arguments: [String], failure: String) throws -> [String: Any] {
        let result = try runner.run(ToolPaths.xcrun, arguments)
        guard result.status == 0 else {
            FileHandle.standardError.write(Data(("notarytool: " + result.stderrString).utf8))
            throw MunkiPkgError.message(failure)
        }
        var data = result.stdout
        if result.stdoutString.hasPrefix("Generated JWT"), let newline = result.stdoutString.firstIndex(of: "\n") {
            data = Data(result.stdoutString[result.stdoutString.index(after: newline)...].utf8)
        }
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw MunkiPkgError.message(failure)
        }
        return plist
    }

    private func staple(_ context: BuildContext, options: CLIOptions) throws {
        console.display("Stapling package")
        try requireSuccess(ToolPaths.xcrun, ["stapler", "staple", context.output.path], failure: "Stapling failed")
        console.display("The staple and validate action worked!")
    }

    private func requireSuccess(_ executable: String, _ arguments: [String], failure: String) throws {
        let result = try runner.run(executable, arguments)
        guard result.status == 0 else {
            let details = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MunkiPkgError.message(details.isEmpty ? failure : "\(failure) \(details)")
        }
    }
}
