import Foundation
import Testing
@testable import munkipkg

struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("munkipkg-tests-\(UUID().uuidString)", isDirectory: true)
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

    func run(_ executable: String, _ arguments: [String]) throws -> ProcessResult {
        calls.append(Call(executable: executable, arguments: arguments))
        return result
    }
}

func write(_ string: String, to url: URL) throws {
    try Data(string.utf8).write(to: url, options: .atomic)
}

func makeConsole() -> Console {
    Console(quiet: true)
}
