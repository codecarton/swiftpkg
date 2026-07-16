import Foundation

enum SwiftPkg {
    static func run(
        arguments: [String],
        runner: any ProcessRunning = SystemProcessRunner(),
        fileManager: FileManager = .default
    ) -> Int32 {
        switch CLIParser.parse(arguments) {
        case .help:
            print(CLIParser.usage)
            return 0
        case .version:
            print(munkipkgVersion)
            return 0
        case .failure(let message):
            FileHandle.standardError.write(Data(("ERROR: \(message)\n").utf8))
            return 255
        case .options(let options):
            guard let path = options.projectDirectory else {
                print(CLIParser.usage)
                return 0
            }
            let console = Console(quiet: options.quiet)
            let project = URL(fileURLWithPath: path).standardizedFileURL
            let projects = ProjectOperations(fileManager: fileManager, runner: runner, console: console)
            do {
                if options.create {
                    try projects.createProject(at: project, options: options)
                } else if let package = options.importPackage {
                    try PackageImporter(fileManager: fileManager, runner: runner, console: console)
                        .importPackage(at: URL(fileURLWithPath: package).standardizedFileURL, to: project, options: options)
                } else {
                    guard fileManager.directoryExists(at: project) else {
                        throw MunkiPkgError.message(fileManager.itemExists(at: project)
                            ? "\(project.path) is not a directory."
                            : "\(project.path): Project not found.")
                    }
                    if options.sync {
                        try projects.syncFromBOM(project: project, options: options)
                    } else {
                        try PackageBuilder(fileManager: fileManager, runner: runner, console: console)
                            .build(project: project, options: options)
                    }
                }
                return 0
            } catch {
                console.error(String(describing: error))
                return 255
            }
        }
    }
}
