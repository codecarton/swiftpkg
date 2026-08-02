import Foundation
import Testing
@testable import SwiftPkgCore

struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftpkg-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

final class RecordingRunner: ProcessRunning, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
    }

    var calls: [Call] = []
    var result = ProcessResult(status: 0, stdout: Data(), stderr: Data())
    /// When set, chooses the result per call; falls back to `result` when nil.
    var resultProvider: ((_ executable: String, _ arguments: [String]) -> ProcessResult)?
    var onRun: ((String, [String]) throws -> Void)?

    func run(executable: String, arguments: [String]) throws -> ProcessResult {
        calls.append(Call(executable: executable, arguments: arguments))
        try onRun?(executable, arguments)
        return resultProvider?(executable, arguments) ?? result
    }
}

func write(_ string: String, to url: URL) throws {
    try Data(string.utf8).write(to: url, options: .atomic)
}

func makeConsole() -> Console {
    Console(quiet: true)
}
