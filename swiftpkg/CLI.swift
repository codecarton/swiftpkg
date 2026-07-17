import ArgumentParser
import Foundation

struct CLIOptions: ParsableArguments {
    @Flag(name: .long, help: "Create a new empty project with default settings.")
    var create = false

    @Option(name: .customLong("import"), help: "Import an existing package.")
    var importPackage: String?

    @Flag(name: .long, help: "Create build-info in JSON format.")
    var json = false

    @Flag(name: .long, help: "Create build-info in YAML format.")
    var yaml = false

    @Flag(name: .long, help: "Export the built package's Bom.txt.")
    var exportBOMInfo = false

    @Flag(name: .long, help: "Apply Bom.txt metadata without building.")
    var sync = false

    @Flag(name: .long, help: "Inhibit status messages on stdout.")
    var quiet = false

    @Flag(name: [.customShort("f"), .long], help: "Convert an existing directory to a project.")
    var force = false

    @Flag(name: .long, help: "Skip configured package signing.")
    var skipSigning = false

    @Flag(name: .long, help: "Skip configured notarization.")
    var skipNotarization = false

    @Flag(name: .long, help: "Skip stapling after notarization.")
    var skipStapling = false

    @Flag(name: .long, help: "Show program's version number and exit.")
    var version = false

    @Argument(help: "The package project directory.")
    var projectDirectory: String? = nil
}

enum CLIParseResult {
    case options(CLIOptions)
    case help
    case version
    case failure(String)
}

/// Represents the single operation requested by parsed command-line options.
enum CLICommand {
    case create(project: URL, format: BuildInfoFormat, force: Bool)
    case `import`(package: URL, project: URL, format: BuildInfoFormat)
    case synchronize(project: URL, requestedFormat: BuildInfoFormat?)
    case build(project: URL, configuration: BuildConfiguration)

    /// Resolves a parsed option set into one executable command.
    static func resolve(from options: CLIOptions) throws -> CLICommand? {
        guard let projectDirectory = options.projectDirectory else { return nil }
        let project = URL(fileURLWithPath: projectDirectory).standardizedFileURL
        let requestedFormat = try BuildInfoFormat.requested(by: options)

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
        return .build(project: project, configuration: BuildConfiguration(options: options, requestedFormat: requestedFormat))
    }
}

/// Contains build-only command-line choices after parsing has completed.
struct BuildConfiguration {
    let requestedFormat: BuildInfoFormat?
    let exportsBOM: Bool
    let isQuiet: Bool
    let skipsSigning: Bool
    let skipsNotarization: Bool
    let skipsStapling: Bool

    init(options: CLIOptions, requestedFormat: BuildInfoFormat?) {
        self.requestedFormat = requestedFormat
        exportsBOM = options.exportBOMInfo
        isQuiet = options.quiet
        skipsSigning = options.skipSigning
        skipsNotarization = options.skipNotarization
        skipsStapling = options.skipStapling
    }
}

enum CLIParser {
    static let usage = """
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
    """

    static func parse(_ arguments: [String]) -> CLIParseResult {
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
