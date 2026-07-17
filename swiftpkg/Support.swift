import Darwin
import Foundation

enum MunkiPkgError: Error, CustomStringConvertible {
    case message(String)
    case invalidConfiguration(String)
    case processFailed(tool: String, message: String)

    var description: String {
        switch self {
        case let .message(value), let .invalidConfiguration(value): value
        case let .processFailed(tool, message): "\(tool): \(message)"
        }
    }
}

struct ProcessResult: Equatable {
    let status: Int32
    let stdout: Data
    let stderr: Data

    var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
    var stderrString: String { String(decoding: stderr, as: UTF8.self) }
}

protocol ProcessRunning {
    /// Runs an executable with arguments and returns its captured result.
    func run(executable: String, arguments: [String]) throws -> ProcessResult

    /// Runs an executable and throws a structured error when it exits unsuccessfully.
    func runSuccessfully(executable: String, arguments: [String], failureMessage: String) throws
}

extension ProcessRunning {
    func runSuccessfully(executable: String, arguments: [String], failureMessage: String) throws {
        let result = try run(executable: executable, arguments: arguments)
        guard result.status == 0 else {
            let details = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MunkiPkgError.processFailed(tool: URL(fileURLWithPath: executable).lastPathComponent, message: details.isEmpty ? failureMessage : "\(failureMessage) \(details)")
        }
    }
}

struct SystemProcessRunner: ProcessRunning {
    func run(executable: String, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw MunkiPkgError.message("\(URL(fileURLWithPath: executable).lastPathComponent) execution failed: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        return ProcessResult(
            status: process.terminationStatus,
            stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
            stderr: stderr.fileHandleForReading.readDataToEndOfFile()
        )
    }
}

final class Console {
    let quiet: Bool
    private let toolName: String

    init(quiet: Bool, toolName: String = "swiftpkg") {
        self.quiet = quiet
        self.toolName = toolName
    }

    func display(_ message: String, toolName override: String? = nil) {
        guard !quiet else { return }
        print("\(override ?? toolName): \(message)")
    }

    func warning(_ message: String) { writeError("WARNING: \(message)") }
    func error(_ message: String) { writeError("ERROR: \(message)") }

    private func writeError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

enum ToolPaths {
    static let ditto = "/usr/bin/ditto"
    static let lsbom = "/usr/bin/lsbom"
    static let pkgbuild = "/usr/bin/pkgbuild"
    static let pkgutil = "/usr/sbin/pkgutil"
    static let productbuild = "/usr/bin/productbuild"
    static let xcrun = "/usr/bin/xcrun"
}

extension FileManager {
    func itemExists(at url: URL) -> Bool { fileExists(atPath: url.path) }

    func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func contents(at url: URL) throws -> [String] {
        try contentsOfDirectory(atPath: url.path)
    }

    func removeIfPresent(at url: URL) throws {
        if fileExists(atPath: url.path) { try removeItem(at: url) }
    }
}

func xmlEscaped(_ string: String) -> String {
    string
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}

func scalarString(_ value: Any?) -> String? {
    if let string = value as? String { return string }
    if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
        return number.stringValue
    }
    return nil
}
