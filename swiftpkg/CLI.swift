import Foundation

struct CLIOptions: Equatable {
    var create = false
    var importPackage: String?
    var json = false
    var yaml = false
    var exportBOMInfo = false
    var sync = false
    var quiet = false
    var force = false
    var skipSigning = false
    var skipNotarization = false
    var skipStapling = false
    var projectDirectory: String?
}

enum CLIParseResult: Equatable {
    case options(CLIOptions)
    case help
    case version
    case failure(String)
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
        var options = CLIOptions()
        var positional: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "-h", "--help": return .help
            case "--version": return .version
            case "--create": options.create = true
            case "--json": options.json = true
            case "--yaml": options.yaml = true
            case "--export-bom-info": options.exportBOMInfo = true
            case "--sync": options.sync = true
            case "--quiet": options.quiet = true
            case "-f", "--force": options.force = true
            case "--skip-signing": options.skipSigning = true
            case "--skip-notarization": options.skipNotarization = true
            case "--skip-stapling": options.skipStapling = true
            case "--import":
                index += 1
                guard index < arguments.count else { return .failure("--import option requires an argument") }
                options.importPackage = arguments[index]
            default:
                if argument.hasPrefix("--import=") {
                    options.importPackage = String(argument.dropFirst("--import=".count))
                } else if argument.hasPrefix("-") {
                    return .failure("no such option: \(argument)")
                } else {
                    positional.append(argument)
                }
            }
            index += 1
        }
        guard positional.count <= 1 else {
            return .failure("Only a single package project can be built at a time!")
        }
        if options.json && options.yaml {
            return .failure("Only a single build-info file can be built at a time!")
        }
        options.projectDirectory = positional.first
        return .options(options)
    }
}
