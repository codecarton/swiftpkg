import Foundation
import Testing
@testable import SwiftPkgCore

struct ConsoleTests {
    @Test("successful process output is relayed to a frontend reporter")
    func relaysProcessOutputToReporter() {
        let recorder = ConsoleEventRecorder()
        let console = Console(quiet: false, eventHandler: recorder.record)

        console.displayProcessOutput(ProcessResult(
            status: 0,
            stdout: Data("pkgbuild: analyzing\npkgbuild: wrote package\n".utf8),
            stderr: Data("pkgbuild: warning\n".utf8)
        ))

        #expect(recorder.events == [
            .init(kind: .status, message: "pkgbuild: analyzing"),
            .init(kind: .status, message: "pkgbuild: wrote package"),
            .init(kind: .warning, message: "pkgbuild: warning"),
        ])
    }

    @Test("quiet process output suppresses status but preserves diagnostics")
    func quietProcessOutputPreservesDiagnostics() {
        let recorder = ConsoleEventRecorder()
        let console = Console(quiet: true, eventHandler: recorder.record)

        console.displayProcessOutput(ProcessResult(
            status: 0,
            stdout: Data("pkgbuild: wrote package\n".utf8),
            stderr: Data("pkgbuild: warning\n".utf8)
        ))

        #expect(recorder.events == [
            .init(kind: .warning, message: "pkgbuild: warning"),
        ])
    }
}

private final class ConsoleEventRecorder: @unchecked Sendable {
    struct Event: Equatable {
        enum Kind: Equatable {
            case status
            case warning
            case error
        }

        let kind: Kind
        let message: String
    }

    private let lock = NSLock()
    private var recordedEvents: [Event] = []

    var events: [Event] {
        lock.withLock { recordedEvents }
    }

    func record(_ event: ConsoleEvent) {
        let recorded = switch event {
        case .status(let message): Event(kind: .status, message: message)
        case .warning(let message): Event(kind: .warning, message: message)
        case .error(let message): Event(kind: .error, message: message)
        }
        lock.withLock { recordedEvents.append(recorded) }
    }
}
