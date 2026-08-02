import ArgumentParser
import Foundation
import SwiftPkgCore

/// Format for the machine/human result printed to stdout after a build.
public enum BuildManifestFormat: String, CaseIterable, Sendable, ExpressibleByArgument {
    case text
    case json
}

public struct CLIOptions: ParsableArguments {
    @Flag(name: .long, help: "Create a new empty project with default settings.")
    public var create = false

    @Option(name: .customLong("import"), help: "Import an existing package.")
    public var importPackage: String?

    @Flag(name: .long, help: "Create build-info in JSON format.")
    public var json = false

    @Flag(name: .long, help: "Create build-info in YAML format.")
    public var yaml = false

    @Flag(name: .long, help: "Export the built package's Bom.txt.")
    public var exportBOMInfo = false

    @Flag(name: .long, help: "Apply Bom.txt metadata without building.")
    public var sync = false

    @Flag(name: .long, help: "Inhibit status messages on stdout.")
    public var quiet = false

    @Flag(name: [.customShort("f"), .long], help: "Convert an existing directory to a project.")
    public var force = false

    @Flag(name: .long, help: "Skip configured package signing.")
    public var skipSigning = false

    @Flag(name: .long, help: "Skip configured notarization.")
    public var skipNotarization = false

    @Flag(name: .long, help: "Skip stapling after notarization.")
    public var skipStapling = false

    @Flag(name: .long, help: "Accepted for munki-pkg compatibility; ignored. swiftpkg never prompts to import into a repo, so there is nothing to skip.")
    public var skipImport = false

    @Flag(name: .long, help: "Show program's version number and exit.")
    public var version = false

    @Option(name: .long, help: "Result printed to stdout after a build: 'text' (default) or 'json' (machine-readable manifest). json implies quiet human output so stdout carries only the manifest.")
    public var outputFormat: BuildManifestFormat = .text

    @Option(name: .long, help: "Override the build-info version (e.g. from a git tag or CI variable). Resolved before ${version} substitution.")
    public var pkgVersion: String?

    @Option(name: .long, help: "Write the built package to this directory instead of the project's build/ directory. Created if it does not exist.")
    public var outputDir: String?

    @Argument(help: "The package project directory.")
    public var projectDirectory: String?

    public init() {}
}

public enum CLIParseResult {
    case options(CLIOptions)
    case help
    case version
    case failure(String)
}

/// Represents the single operation requested by parsed command-line options.
public enum CLICommand {
    case create(project: URL, format: BuildInfoFormat, force: Bool)
    case `import`(package: URL, project: URL, format: BuildInfoFormat)
    case synchronize(project: URL, requestedFormat: BuildInfoFormat?)
    case build(project: URL, configuration: PackageBuildOptions)

    /// Resolves a parsed option set into one executable command.
    public static func resolve(from options: CLIOptions) throws -> CLICommand? {
        guard let projectDirectory = options.projectDirectory else { return nil }
        let project = URL(fileURLWithPath: projectDirectory).standardizedFileURL
        let requestedFormat = try requestedFormat(from: options)

        if options.create {
            return .create(project: project, format: requestedFormat ?? .plist, force: options.force)
        }
        if let packagePath = options.importPackage {
            return .import(
                package: URL(fileURLWithPath: packagePath).standardizedFileURL,
                project: project,
                format: requestedFormat ?? .plist
            )
        }
        if options.sync { return .synchronize(project: project, requestedFormat: requestedFormat) }
        return .build(
            project: project,
            configuration: PackageBuildOptions(
                requestedFormat: requestedFormat,
                exportsBOM: options.exportBOMInfo,
                isQuiet: options.quiet,
                skipsSigning: options.skipSigning,
                skipsNotarization: options.skipNotarization,
                skipsStapling: options.skipStapling,
                versionOverride: options.pkgVersion,
                outputDirectory: options.outputDir.map { URL(fileURLWithPath: $0).standardizedFileURL }
            )
        )
    }

    private static func requestedFormat(from options: CLIOptions) throws -> BuildInfoFormat? {
        guard !(options.json && options.yaml) else {
            throw MunkiPkgError.invalidConfiguration("Only a single build-info file can be built at a time!")
        }
        if options.json { return .json }
        if options.yaml { return .yaml }
        return nil
    }
}

public enum CLIParser {
    public static let usage = """
    Usage: swiftpkg [options] pkg_project_directory
           A tool for building a package from the contents of a
           pkg_project_directory.

    Options:
      -h, --help              Show this help message and exit.
      --version               Show program's version number and exit.
      --create                Create a new empty project with default settings.
      --import PKG            Import an existing package.
      --json                  Create build-info in JSON format.
      --yaml                  Create build-info in YAML format.
      --export-bom-info       Export the built package's Bom.txt.
      --sync                  Apply Bom.txt metadata without building.
      --quiet                 Inhibit status messages on stdout.
      -f, --force             Convert an existing directory to a project.
      --skip-signing          Skip configured package signing.
      --skip-notarization     Skip configured notarization.
      --skip-stapling         Skip stapling after notarization.
      --output-format FORMAT  Build result on stdout: text (default) or json.
      --skip-import           Accepted for munki-pkg compatibility; ignored.
      --pkg-version VERSION   Override the build-info version.
      --output-dir DIR        Write the package to DIR instead of build/.
    """

    public static func parse(_ arguments: [String]) -> CLIParseResult {
        if arguments.last == "--import" {
            return .failure("--import option requires an argument")
        }
        do {
            let options = try CLIOptions.parse(arguments)
            if options.version { return .version }
            if options.json && options.yaml {
                return .failure("Only a single build-info file can be built at a time!")
            }
            return .options(options)
        } catch {
            if arguments.contains("-h") || arguments.contains("--help") {
                return .help
            }
            return .failure(String(describing: error))
        }
    }
}
