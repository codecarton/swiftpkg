import Foundation
import Testing
@testable import swiftpkg

struct BuildInfoTests {
    @Test("defaults remove spaces and provide typed values")
    func defaultsRemoveSpacesAndProvideTypedValues() {
        let configuration = PackageConfiguration.defaults(for: URL(fileURLWithPath: "/tmp/My Project"))

        #expect(configuration.name == "MyProject-${version}.pkg")
        #expect(configuration.identifier == "com.github.munki.pkg.MyProject")
        #expect(configuration.version == "1.0")
        #expect(configuration.ownership == .recommended)
        #expect(!configuration.usesDistributionStyle)
    }

    @Test("loads supported formats and substitutes version", arguments: [BuildInfoFormat.json, .plist, .yaml, .yml])
    func loadsSupportedFormatsAndSubstitutesVersion(_ format: BuildInfoFormat) throws {
        let temporary = try TemporaryDirectory(); defer { temporary.remove() }
        let project = temporary.url.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        let values: [String: Any] = ["name": "Project-${version}.pkg", "version": "2.5", "title": "Project ${version}", "identifier": "com.example.project", "ownership": "recommended", "postinstall_action": "none"]
        let configuration = try PackageConfiguration(values: values, defaults: .defaults(for: project))
        try BuildInfoStore.write(configuration, to: project, format: format)

        let loaded = try BuildInfoStore.load(from: project, requestedFormat: format)
        #expect(loaded.name == "Project-2.5.pkg")
        #expect(loaded.title == "Project 2.5")
        #expect(loaded.identifier == "com.example.project")
    }

    @Test("rejects multiple build info files")
    func rejectsMultipleBuildInfoFiles() throws {
        let temporary = try TemporaryDirectory(); defer { temporary.remove() }
        let project = temporary.url.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        let configuration = PackageConfiguration.defaults(for: project)
        try BuildInfoStore.write(configuration, to: project, format: .plist)
        try BuildInfoStore.write(configuration, to: project, format: .json)

        #expect(throws: (any Error).self) { try BuildInfoStore.load(from: project, requestedFormat: nil) }
    }

    @Test("decodes nested typed configuration and preserves legacy wire keys")
    func decodesNestedConfigurationAndPreservesLegacyWireKeys() throws {
        let project = URL(fileURLWithPath: "/tmp/Project")
        let values: [String: Any] = [
            "name": "Project.pkg", "identifier": "com.example.project", "version": "1.0", "ownership": "preserve",
            "postinstall_action": "restart", "compression": "latest", "product id": "com.example.product",
            "signing_info": ["identity": "Developer ID", "additional_cert_names": ["CA 1", "CA 2"]],
            "notarization_info": ["keychain_profile": "notary", "staple_timeout": 120]
        ]
        let configuration = try PackageConfiguration(values: values, defaults: .defaults(for: project))

        #expect(configuration.ownership == .preserve)
        #expect(configuration.compression == .latest)
        #expect(configuration.postInstallAction == .restart)
        #expect(configuration.signing?.additionalCertificateNames == ["CA 1", "CA 2"])
        #expect(configuration.encodedValues["product id"] as? String == "com.example.product")
    }

    @Test("rejects illegal enum values")
    func rejectsIllegalEnumValues() {
        #expect(throws: (any Error).self) {
            try PackageConfiguration(values: ["ownership": "invalid"], defaults: .defaults(for: URL(fileURLWithPath: "/tmp/Project")))
        }
    }
}
