import Foundation
import Testing
@testable import SwiftPkgCore

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

    @Test("template loading preserves version placeholders")
    func templateLoadingPreservesVersionPlaceholders() throws {
        let temporary = try TemporaryDirectory(); defer { temporary.remove() }
        let project = temporary.url.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        let configuration = try PackageConfiguration(
            values: ["name": "Project-${version}.pkg", "version": "3.0", "title": "Project ${version}"],
            defaults: .defaults(for: project)
        )
        try BuildInfoStore.write(configuration, to: project, format: .json)

        let template = try BuildInfoStore.loadTemplate(from: project)
        let resolved = try BuildInfoStore.load(from: project, requestedFormat: nil)

        #expect(template.name == "Project-${version}.pkg")
        #expect(template.title == "Project ${version}")
        #expect(resolved.name == "Project-3.0.pkg")
    }

    @Test("standalone settings round trip", arguments: BuildInfoFormat.allCases)
    func standaloneSettingsRoundTrip(_ format: BuildInfoFormat) throws {
        let temporary = try TemporaryDirectory(); defer { temporary.remove() }
        let project = temporary.url.appendingPathComponent("Project", isDirectory: true)
        let file = temporary.url.appendingPathComponent("settings").appendingPathExtension(format.rawValue)
        let configuration = PackageConfiguration.defaults(for: project)

        try BuildInfoStore.write(configuration, toFile: file, format: format)
        let loaded = try BuildInfoStore.loadTemplate(from: file, defaultsFor: project)

        #expect(loaded.name == configuration.name)
        #expect(loaded.identifier == configuration.identifier)
    }

    @Test("Apple ID notarization credentials round trip", arguments: BuildInfoFormat.allCases)
    func appleIDNotarizationCredentialsRoundTrip(_ format: BuildInfoFormat) throws {
        let temporary = try TemporaryDirectory(); defer { temporary.remove() }
        let project = temporary.url.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        let defaults = PackageConfiguration.defaults(for: project)
        let configuration = PackageConfiguration(
            name: defaults.name,
            identifier: defaults.identifier,
            version: defaults.version,
            ownership: defaults.ownership,
            installLocation: defaults.installLocation,
            compression: defaults.compression,
            minimumOSVersion: defaults.minimumOSVersion,
            usesLargePayload: defaults.usesLargePayload,
            postInstallAction: defaults.postInstallAction,
            preservesExtendedAttributes: defaults.preservesExtendedAttributes,
            suppressesBundleRelocation: defaults.suppressesBundleRelocation,
            usesDistributionStyle: defaults.usesDistributionStyle,
            title: defaults.title,
            productIdentifier: defaults.productIdentifier,
            signing: defaults.signing,
            notarization: NotarizationConfiguration(
                authentication: .appleID(
                    appleID: "developer@example.com",
                    teamID: "TEAMID1234",
                    password: "app-specific-password"
                ),
                staplingTimeout: 120
            )
        )

        try BuildInfoStore.write(configuration, to: project, format: format)
        let loaded = try BuildInfoStore.loadTemplate(from: project, requestedFormat: format)

        guard case let .appleID(appleID, teamID, password) = loaded.notarization?.authentication else {
            Issue.record("Expected Apple ID notarization credentials")
            return
        }
        #expect(appleID == "developer@example.com")
        #expect(teamID == "TEAMID1234")
        #expect(password == "app-specific-password")
        #expect(loaded.notarization?.staplingTimeout == 120)
    }

    @Test("draft validates required values and nested settings")
    func draftValidation() throws {
        let project = URL(fileURLWithPath: "/tmp/Project")
        var draft = PackageSettingsDraft.defaults(for: project)
        draft.signingEnabled = true
        draft.signingIdentity = "Developer ID Installer"
        draft.signingTimestampMode = .disabled
        draft.notarizationMode = .keychainProfile
        draft.notarizationKeychainProfile = "swiftpkg"

        let configuration = try draft.validatedConfiguration()
        #expect(configuration.signing?.identity == "Developer ID Installer")
        #expect(configuration.signing?.usesTimestamp == false)
        #expect(PackageSettingsDraft(configuration: configuration).signingTimestampMode == .disabled)
        guard case .keychainProfile("swiftpkg") = configuration.notarization?.authentication else {
            Issue.record("Expected keychain profile")
            return
        }

        draft.name = ""
        #expect(throws: (any Error).self) { try draft.validatedConfiguration() }
    }
}
