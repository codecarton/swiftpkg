import Foundation
import Testing
@testable import SwiftPkgCore

struct DistributionVerificationTests {
    @Test("distribution verification compares the effective product identifier")
    func verifiesProductIdentifier() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let project = temp.url.appendingPathComponent("Distribution", isDirectory: true)
        let payload = project.appendingPathComponent("payload", isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        try write(
            #"{"name":"Distribution-${version}.pkg","identifier":"com.example.component","version":"2.0","distribution_style":true,"product id":"com.example.product"}"#,
            to: project.appendingPathComponent("build-info.json")
        )
        try write("payload", to: payload.appendingPathComponent("file.txt"))
        let loaded = try BuildInfoStore.load(from: project, requestedFormat: nil)
        #expect(loaded.productIdentifier == "com.example.product")

        let runner = RecordingRunner()
        runner.onRun = { executable, arguments in
            if executable == ToolPaths.pkgbuild, arguments.first == "--analyze" {
                try write("<?xml version=\"1.0\"?><plist version=\"1.0\"><array/></plist>", to: URL(fileURLWithPath: arguments.last!))
            } else if executable == ToolPaths.pkgbuild || executable == ToolPaths.productbuild {
                try write("fake package", to: URL(fileURLWithPath: arguments.last!))
            } else if executable == ToolPaths.pkgutil, arguments.first == "--expand" {
                let destination = URL(fileURLWithPath: arguments.last!)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try write(
                    #"<?xml version="1.0"?><installer-gui-script><product id="com.example.product" version="2.0"/></installer-gui-script>"#,
                    to: destination.appendingPathComponent("Distribution")
                )
            }
        }

        let coordinator = PackageBuildCoordinator(fileManager: .default, runner: runner, console: makeConsole())
        try await coordinator.buildPackage(
            in: project,
            configuration: PackageBuildOptions(skipsSigning: true, verifies: true)
        )

        #expect(runner.calls.contains { $0.executable == ToolPaths.pkgutil && $0.arguments.first == "--expand" })
    }
}
