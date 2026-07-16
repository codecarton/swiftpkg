import Foundation

private final class PackageInfoParser: NSObject, XMLParserDelegate {
    var attributes: [String: String] = [:]

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "pkg-info", attributes.isEmpty { attributes = attributeDict }
    }
}

struct PackageImporter {
    let fileManager: FileManager
    let runner: any ProcessRunning
    let console: Console

    func importPackage(at package: URL, to project: URL, options: CLIOptions) throws {
        guard !fileManager.itemExists(at: project) else {
            throw MunkiPkgError.message("Directory \(project.path) already exists.")
        }
        if fileManager.directoryExists(at: package) {
            try importBundlePackage(package, project: project, options: options)
        } else {
            try importFlatPackage(package, project: project, options: options)
        }
        console.display("Created new package project at \(project.path)")
    }

    private func importBundlePackage(_ package: URL, project: URL, options: CLIOptions) throws {
        let contents = package.appendingPathComponent("Contents", isDirectory: true)
        let distributionFiles = try fileManager.contents(at: contents).filter { $0.hasSuffix(".dist") }
        guard distributionFiles.isEmpty else {
            throw MunkiPkgError.message("Bundle-style distribution packages are not supported for import. Consider importing the included sub-package(s).")
        }
        try fileManager.createDirectory(at: project, withIntermediateDirectories: false)
        do {
            try projectOperations.exportBOM(from: contents.appendingPathComponent("Archive.bom"), project: project)
            let payload = project.appendingPathComponent("payload", isDirectory: true)
            try fileManager.createDirectory(at: payload, withIntermediateDirectories: false)
            try requireSuccess(ToolPaths.ditto, ["-x", contents.appendingPathComponent("Archive.pax.gz").path, payload.path], failure: "Ditto failed to expand Payload")
            try copyBundleScripts(package: package, project: project)
            try convertInfoPlist(package: package, project: project, options: options)
            try warnAndSync(project: project, options: options)
            try projectOperations.writeGitignore(project: project)
        } catch {
            try? fileManager.removeItem(at: project)
            throw error
        }
    }

    private func importFlatPackage(_ package: URL, project: URL, options: CLIOptions) throws {
        do {
            try requireSuccess(ToolPaths.pkgutil, ["--expand", package.path, project.path], failure: "Could not expand package.")
            try handleDistributionPackage(project: project)
            let bom = project.appendingPathComponent("Bom")
            try projectOperations.exportBOM(from: bom, project: project)
            try fileManager.removeIfPresent(at: bom)
            let scripts = project.appendingPathComponent("Scripts")
            if fileManager.itemExists(at: scripts) {
                try fileManager.moveItem(at: scripts, to: project.appendingPathComponent("scripts"))
            }
            try expandPayload(project: project)
            try convertPackageInfo(package: package, project: project, options: options)
            try warnAndSync(project: project, options: options)
            try projectOperations.writeGitignore(project: project)
        } catch {
            try? fileManager.removeItem(at: project)
            throw error
        }
    }

    private var projectOperations: ProjectOperations {
        ProjectOperations(fileManager: fileManager, runner: runner, console: console)
    }

    private func warnAndSync(project: URL, options: CLIOptions) throws {
        if projectOperations.hasNonRecommendedOwnership(project: project), geteuid() != 0 {
            FileHandle.standardError.write(Data("""

            WARNING: package contains non-default owner/group on some files. build-info ownership has been set to "preserve".
            Check the bom for accuracy.
            Run munkipkg --sync with sudo to apply the correct owner and group to payload files.

            """.utf8))
        }
        try projectOperations.syncFromBOM(project: project, options: options)
    }

    private func handleDistributionPackage(project: URL) throws {
        guard fileManager.itemExists(at: project.appendingPathComponent("Distribution")) else { return }
        let packages = try fileManager.contents(at: project).filter { name in
            name.hasSuffix(".pkg") && fileManager.directoryExists(at: project.appendingPathComponent(name))
        }
        guard packages.count == 1 else {
            throw MunkiPkgError.message("Distribution packages to be imported must contain exactly one component package! Found: \(packages)")
        }
        let component = project.appendingPathComponent(packages[0])
        for name in ["Bom", "PackageInfo", "Payload", "Scripts"] {
            let source = component.appendingPathComponent(name)
            if fileManager.itemExists(at: source) {
                try fileManager.moveItem(at: source, to: project.appendingPathComponent(name))
            }
        }
        try? fileManager.removeItem(at: component)
    }

    private func expandPayload(project: URL) throws {
        let payloadFile = project.appendingPathComponent("Payload")
        guard fileManager.itemExists(at: payloadFile) else { return }
        let archive = project.appendingPathComponent("Payload.cpio.gz")
        let payload = project.appendingPathComponent("payload", isDirectory: true)
        try fileManager.moveItem(at: payloadFile, to: archive)
        try fileManager.createDirectory(at: payload, withIntermediateDirectories: false)
        try requireSuccess(ToolPaths.ditto, ["-x", archive.path, payload.path], failure: "Ditto failed to expand Payload")
        try fileManager.removeIfPresent(at: archive)
    }

    private func convertPackageInfo(package: URL, project: URL, options: CLIOptions) throws {
        let url = project.appendingPathComponent("PackageInfo")
        guard let parser = XMLParser(contentsOf: url) else { throw MunkiPkgError.message("Could not parse \(url.path)") }
        let delegate = PackageInfoParser()
        parser.delegate = delegate
        guard parser.parse() else { throw MunkiPkgError.message("Could not parse \(url.path): \(parser.parserError?.localizedDescription ?? "invalid XML")") }
        let attributes = delegate.attributes
        var values: [String: Any] = [
            "identifier": attributes["identifier"] ?? "",
            "version": attributes["version"] ?? "1.0",
            "install_location": attributes["install-location"] ?? "/",
            "postinstall_action": attributes["postinstall-action"] ?? "none",
            "preserve_xattr": attributes["preserve-xattr"] == "true",
            "name": package.lastPathComponent,
            "distribution_style": fileManager.itemExists(at: project.appendingPathComponent("Distribution"))
        ]
        if projectOperations.hasNonRecommendedOwnership(project: project) { values["ownership"] = "preserve" }
        try BuildInfoIO.write(BuildInfo(values: values), project: project, options: options)
        try fileManager.removeIfPresent(at: url)
    }

    private func convertInfoPlist(package: URL, project: URL, options: CLIOptions) throws {
        let url = package.appendingPathComponent("Contents/Info.plist")
        let object = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        guard let plist = object as? [String: Any] else { throw MunkiPkgError.message("Could not read \(url.path)") }
        let restart = plist["IFPkgFlagRestartAction"] as? String
        let action: String
        if ["RequiredRestart", "RecommendedRestart"].contains(restart) { action = "restart" }
        else if ["RequiredLogout", "RecommendedLogout"].contains(restart) { action = "logout" }
        else { action = "none" }
        var values: [String: Any] = [
            "identifier": plist["CFBundleIdentifier"] as? String ?? "",
            "version": plist["CFBundleShortVersionString"] ?? plist["CFBundleVersion"] ?? "1.0",
            "install_location": plist["IFPkgFlagDefaultLocation"] as? String ?? "/",
            "postinstall_action": action,
            "name": package.lastPathComponent
        ]
        if projectOperations.hasNonRecommendedOwnership(project: project) { values["ownership"] = "preserve" }
        try BuildInfoIO.write(BuildInfo(values: values), project: project, options: options)
    }

    private func copyBundleScripts(package: URL, project: URL) throws {
        let resources = package.appendingPathComponent("Contents/Resources", isDirectory: true)
        guard fileManager.directoryExists(at: resources) else { return }
        let items = try fileManager.contents(at: resources)
        let known = Set(scriptNames())
        guard !known.isDisjoint(with: items) else { return }
        let scripts = project.appendingPathComponent("scripts", isDirectory: true)
        try fileManager.createDirectory(at: scripts, withIntermediateDirectories: false)
        for item in items where !item.hasSuffix(".lproj") && item != "package_version" {
            try fileManager.copyItem(at: resources.appendingPathComponent(item), to: scripts.appendingPathComponent(item))
        }
        for kind in ["pre", "post"] {
            let found = try fileManager.contents(at: scripts).filter { scriptNames(kind: kind).contains($0) }
            let supported = "\(kind)install"
            if found.count == 1, found[0] != supported {
                console.display("Renaming \(found[0]) script to \(supported)")
                try fileManager.moveItem(at: scripts.appendingPathComponent(found[0]), to: scripts.appendingPathComponent(supported))
            } else if found.count > 1 {
                console.warning("Multiple \(kind)XXXXXX scripts found. Flat packages support only '\(supported)'.")
            }
        }
    }

    private func scriptNames(kind: String = "all") -> [String] {
        let pre = ["preflight", "preinstall", "preupgrade"]
        let post = ["postflight", "postinstall", "postupgrade"]
        return kind == "pre" ? pre : kind == "post" ? post : pre + post
    }

    private func requireSuccess(_ executable: String, _ arguments: [String], failure: String) throws {
        let result = try runner.run(executable, arguments)
        guard result.status == 0 else {
            let detail = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MunkiPkgError.message(detail.isEmpty ? failure : "\(failure) \(detail)")
        }
    }
}
