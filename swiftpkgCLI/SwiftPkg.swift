import Foundation
import SwiftPkgCore

public enum SwiftPkg {
    public static func run(
        arguments: [String],
        runner: any ProcessRunning = SystemProcessRunner(),
        fileManager: FileManager = .default
    ) async -> Int32 {
        switch CLIParser.parse(arguments) {
        case .help:
            print(CLIParser.usage)
            return 0
        case .version:
            print(swiftpkgVersion)
            return 0
        case .failure(let message):
            FileHandle.standardError.write(Data(("ERROR: \(message)\n").utf8))
            return 255
        case .options(let options):
            let command: CLICommand?
            do {
                command = try CLICommand.resolve(from: options)
            } catch {
                consoleError(String(describing: error))
                return 255
            }
            guard let command else {
                print(CLIParser.usage)
                return 0
            }
            let console = Console(quiet: options.quiet)
            do {
                switch command {
                case let .create(project, format, force):
                    try ProjectCreator(fileManager: fileManager, console: console)
                        .createProject(at: project, format: format, force: force)
                case let .import(package, project, format):
                    try PackageImporter(fileManager: fileManager, runner: runner, console: console)
                        .importPackage(at: package, to: project, format: format)
                case let .synchronize(project, requestedFormat):
                    guard fileManager.directoryExists(at: project) else {
                        throw MunkiPkgError.message(fileManager.itemExists(at: project)
                            ? "\(project.path) is not a directory."
                            : "\(project.path): Project not found.")
                    }
                    try BOMMetadataService(fileManager: fileManager, runner: runner, console: console)
                        .synchronizeMetadataFromBOM(in: project, requestedFormat: requestedFormat)
                case let .lint(project, requestedFormat):
                    let findings = try Linter(fileManager: fileManager).lint(project: project, requestedFormat: requestedFormat)
                    for finding in findings {
                        FileHandle.standardError.write(Data("\(finding.severity.rawValue): \(finding.message)\n".utf8))
                    }
                    let errors = findings.filter { $0.severity == .error }.count
                    if errors > 0 {
                        FileHandle.standardError.write(Data("lint failed: \(errors) error(s), \(findings.count - errors) warning(s)\n".utf8))
                        return 1
                    }
                    console.display("lint passed (\(findings.count) warning(s))")
                    return 0
                case let .build(project, configuration):
                    guard fileManager.directoryExists(at: project) else {
                        throw MunkiPkgError.message(fileManager.itemExists(at: project)
                            ? "\(project.path) is not a directory."
                            : "\(project.path): Project not found.")
                    }
                    try await PackageBuildCoordinator(fileManager: fileManager, runner: runner, console: console)
                        .buildPackage(in: project, configuration: configuration)
                }
                return 0
            } catch {
                console.error(String(describing: error))
                return 255
            }
        }
    }
}

private func consoleError(_ message: String) {
    FileHandle.standardError.write(Data(("ERROR: \(message)\n").utf8))
}
