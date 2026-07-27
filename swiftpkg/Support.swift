import Darwin
import Foundation

public enum MunkiPkgError: Error, CustomStringConvertible, LocalizedError {
    case message(String)
    case invalidConfiguration(String)
    case processFailed(tool: String, message: String)

    public var description: String {
        switch self {
        case let .message(value), let .invalidConfiguration(value): value
        case let .processFailed(tool, message): "\(tool): \(message)"
        }
    }

    public var errorDescription: String? { description }
}

public struct ProcessResult: Equatable, Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: Data

    public init(status: Int32, stdout: Data, stderr: Data) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrString: String { String(decoding: stderr, as: UTF8.self) }
}

public protocol ProcessRunning: Sendable {
    /// Runs an executable with arguments and returns its captured result.
    func run(executable: String, arguments: [String]) throws -> ProcessResult

    /// Runs an executable and throws a structured error when it exits unsuccessfully.
    func runSuccessfully(executable: String, arguments: [String], failureMessage: String) throws
}

public protocol ProcessControlling: Sendable {
    func cancel()
}

public extension ProcessResult {
    /// The tool's own account of a failure, appended to `fallback`. Tools explain
    /// themselves better than we can from the outside — notarytool, for one, names
    /// the missing keychain profile and the command that creates it — so prefer
    /// their words. stdout is a fallback for tools that report failures there;
    /// when neither says anything, `fallback` stands alone.
    func failureDetail(fallback: String) -> String {
        let detail = [stderrString, stdoutString]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let detail else { return fallback }
        return "\(fallback) \(detail)"
    }
}

public extension ProcessRunning {
    func runSuccessfully(executable: String, arguments: [String], failureMessage: String) throws {
        let result = try run(executable: executable, arguments: arguments)
        guard result.status == 0 else {
            throw MunkiPkgError.processFailed(tool: URL(fileURLWithPath: executable).lastPathComponent, message: result.failureDetail(fallback: failureMessage))
        }
    }
}

public final class SystemProcessRunner: ProcessRunning, ProcessControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var activeProcess: Process?

    public init() {}

    public func run(executable: String, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        lock.withLock { activeProcess = process }
        defer {
            lock.withLock {
                if activeProcess === process { activeProcess = nil }
            }
        }
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

    public func cancel() {
        let process = lock.withLock { activeProcess }
        if process?.isRunning == true { process?.terminate() }
    }
}

public final class Console: @unchecked Sendable {
    public let quiet: Bool
    private let toolName: String
    private let eventHandler: (@Sendable (ConsoleEvent) -> Void)?

    public init(
        quiet: Bool,
        toolName: String = "swiftpkg",
        eventHandler: (@Sendable (ConsoleEvent) -> Void)? = nil
    ) {
        self.quiet = quiet
        self.toolName = toolName
        self.eventHandler = eventHandler
    }

    public func display(_ message: String, toolName override: String? = nil) {
        guard !quiet else { return }
        if let eventHandler {
            eventHandler(.status(message))
        } else {
            print("\(override ?? toolName): \(message)")
        }
    }

    public func warning(_ message: String) {
        if let eventHandler { eventHandler(.warning(message)) }
        else { writeError("WARNING: \(message)") }
    }

    public func error(_ message: String) {
        if let eventHandler { eventHandler(.error(message)) }
        else { writeError("ERROR: \(message)") }
    }

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
    public func itemExists(at url: URL) -> Bool { fileExists(atPath: url.path) }

    public func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    public func contents(at url: URL) throws -> [String] {
        try contentsOfDirectory(atPath: url.path)
    }

    public func removeIfPresent(at url: URL) throws {
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
