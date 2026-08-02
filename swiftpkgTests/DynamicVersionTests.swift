import Foundation
import Testing
@testable import SwiftPkgCore

struct DynamicVersionTests {

    /// 2026-07-18 14:05:30 in the current time zone, so formatting round-trips.
    private static func fixedDate() -> Date {
        var components = DateComponents()
        components.year = 2026; components.month = 7; components.day = 18
        components.hour = 14; components.minute = 5; components.second = 30
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: components)!
    }

    @Test("each token resolves to its documented format")
    func tokensResolve() {
        let now = Self.fixedDate()
        #expect(DynamicVersion.resolve("${TIMESTAMP}", now: now) == "2026.07.18.1405")
        #expect(DynamicVersion.resolve("${DATE}", now: now) == "2026.07.18")
        #expect(DynamicVersion.resolve("${DATETIME}", now: now) == "2026.07.18.140530")
        #expect(DynamicVersion.resolve("1.2.${DATE}", now: now) == "1.2.2026.07.18")
        #expect(DynamicVersion.resolve("static", now: now) == "static")
    }

    @Test("resolvingDynamicVersion feeds the resolved version into ${version} in name")
    func resolvedVersionFlowsIntoName() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let project = temp.url.appendingPathComponent("Dyn", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        let template = try PackageConfiguration(
            values: ["name": "Dyn-${version}.pkg", "identifier": "com.example.dyn", "version": "${DATE}"],
            defaults: .defaults(for: project)
        )
        let resolved = template.resolvingDynamicVersion(now: Self.fixedDate()).substitutingVersion()
        #expect(resolved.version == "2026.07.18")
        #expect(resolved.name == "Dyn-2026.07.18.pkg")
    }
}
