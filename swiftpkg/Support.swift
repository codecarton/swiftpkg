import Darwin
import Foundation

public enum MunkiPkgError: Error, CustomStringConvertible, LocalizedError {
    case message(String)
    case invalidConfiguration(String)
    case processFailed(tool: String, message: String)
    case projectExists(String)
    case importFailed(String)
    case notarizationFailed(String)

    public var description: String {
        switch self {
        case let .message(value),
             let .invalidConfiguration(value),
             let .projectExists(value),
             let .importFailed(value),
             let .notarizationFailed(value):
            value
        case let .processFailed(tool, message): "\(tool): \(message)"
        }
    }

    public var errorDescription: String? { description }

    /// Process exit code for this error class. `0` is reserved for success and
    /// `64` (EX_USAGE) for command-line usage errors; `6` is reserved for a
    /// future dedicated signing-failure class. See the README exit-code table.
    public var exitCode: Int32 {
        switch self {
        case .message: 1
        case .projectExists: 2
        case .invalidConfiguration: 3
        case .importFailed: 4
        case .processFailed: 5
        case .notarizationFailed: 7
        }
    }
}

/// Exit code for a command-line usage/parse error (sysexits.h EX_USAGE).
public let usageErrorExitCode: Int32 = 64

/// Maps any thrown error to a process exit code, defaulting unknown errors to 1.
public func exitCode(for error: any Error) -> Int32 {
    (error as? MunkiPkgError)?.exitCode ?? 1
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

        // Drain stdout and stderr concurrently on background queues *before*
        // waiting. Reading only after waitUntilExit() (or draining the pipes
        // sequentially) deadlocks: a child that writes more than the ~64KB pipe
        // buffer to either stream blocks on write(), never exits, and the wait
        // hangs forever. Each field is written exactly once by its own closure;
        // the parent reads the box only after group.wait(), so there is no
        // concurrent mutation.
        final class DataBox: @unchecked Sendable {
            var stdout = Data()
            var stderr = Data()
        }
        let box = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            box.stdout = stdout.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            box.stderr = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        process.waitUntilExit()
        group.wait()
        return ProcessResult(
            status: process.terminationStatus,
            stdout: box.stdout,
            stderr: box.stderr
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
    static let git = "/usr/bin/git"
    static let spctl = "/usr/sbin/spctl"
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
