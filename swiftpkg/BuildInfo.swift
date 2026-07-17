import Foundation
import Yams

/// Identifies a supported on-disk build configuration format.
public enum BuildInfoFormat: String, CaseIterable, Identifiable, Sendable {
    case plist, json, yaml, yml

    public var id: String { rawValue }
}

/// Controls the ownership mode passed to `pkgbuild`.
public enum PackageOwnership: String, CaseIterable, Identifiable, Sendable {
    case recommended, preserve, preserveOther = "preserve-other"

    public var id: String { rawValue }
}

/// Controls the compression mode passed to `pkgbuild`.
public enum PackageCompression: String, CaseIterable, Identifiable, Sendable {
    case legacy, latest

    public var id: String { rawValue }
}

/// Controls the post-install action recorded in package metadata.
public enum PostInstallAction: String, CaseIterable, Identifiable, Sendable {
    case none, logout, restart

    public var id: String { rawValue }
}

/// Contains optional package-signing credentials.
public struct SigningConfiguration: Sendable {
    public let identity: String
    public let keychain: String?
    public let additionalCertificateNames: [String]
    public let usesTimestamp: Bool?

    public init(identity: String, keychain: String?, additionalCertificateNames: [String], usesTimestamp: Bool?) {
        self.identity = identity
        self.keychain = keychain
        self.additionalCertificateNames = additionalCertificateNames
        self.usesTimestamp = usesTimestamp
    }
}

/// Contains credentials and timing options for Apple notarization.
public struct NotarizationConfiguration: Sendable {
    public enum Authentication: Sendable {
        case appleID(appleID: String, teamID: String, password: String)
        case keychainProfile(String)
    }

    public let authentication: Authentication
    public let staplingTimeout: Int

    public init(authentication: Authentication, staplingTimeout: Int) {
        self.authentication = authentication
        self.staplingTimeout = staplingTimeout
    }
}

/// Provides the typed settings needed to build a package.
public struct PackageConfiguration: Sendable {
    public let name: String
    public let identifier: String
    public let version: String
    public let ownership: PackageOwnership
    public let installLocation: String?
    public let compression: PackageCompression?
    public let minimumOSVersion: String?
    public let usesLargePayload: Bool
    public let postInstallAction: PostInstallAction
    public let preservesExtendedAttributes: Bool
    public let suppressesBundleRelocation: Bool
    public let usesDistributionStyle: Bool
    public let title: String?
    public let productIdentifier: String?
    public let signing: SigningConfiguration?
    public let notarization: NotarizationConfiguration?

    public init(
        name: String, identifier: String, version: String, ownership: PackageOwnership,
        installLocation: String?, compression: PackageCompression?, minimumOSVersion: String?, usesLargePayload: Bool,
        postInstallAction: PostInstallAction, preservesExtendedAttributes: Bool, suppressesBundleRelocation: Bool,
        usesDistributionStyle: Bool, title: String?, productIdentifier: String?, signing: SigningConfiguration?,
        notarization: NotarizationConfiguration?
    ) {
        self.name = name; self.identifier = identifier; self.version = version; self.ownership = ownership
        self.installLocation = installLocation; self.compression = compression; self.minimumOSVersion = minimumOSVersion
        self.usesLargePayload = usesLargePayload; self.postInstallAction = postInstallAction
        self.preservesExtendedAttributes = preservesExtendedAttributes; self.suppressesBundleRelocation = suppressesBundleRelocation
        self.usesDistributionStyle = usesDistributionStyle; self.title = title; self.productIdentifier = productIdentifier
        self.signing = signing; self.notarization = notarization
    }

    /// Creates default settings for a new project at the supplied location.
    public static func defaults(for project: URL) -> PackageConfiguration {
        let baseName = project.lastPathComponent.replacingOccurrences(of: " ", with: "")
        return PackageConfiguration(
            name: "\(baseName)-${version}.pkg", identifier: "com.github.munki.pkg.\(baseName)", version: "1.0",
            ownership: .recommended, installLocation: "/", compression: nil, minimumOSVersion: nil,
            usesLargePayload: false, postInstallAction: .none, preservesExtendedAttributes: false,
            suppressesBundleRelocation: true, usesDistributionStyle: false, title: nil,
            productIdentifier: nil, signing: nil, notarization: nil
        )
    }

    /// Decodes a configuration dictionary, applying defaults for missing keys.
    public init(values: [String: Any], defaults: PackageConfiguration) throws {
        name = try Self.stringValue(for: "name", in: values) ?? defaults.name
        identifier = try Self.stringValue(for: "identifier", in: values) ?? defaults.identifier
        version = try Self.stringValue(for: "version", in: values) ?? defaults.version
        ownership = try Self.enumValue(PackageOwnership.self, key: "ownership", values: values) ?? defaults.ownership
        installLocation = try Self.stringValue(for: "install_location", in: values) ?? defaults.installLocation
        compression = try Self.enumValue(PackageCompression.self, key: "compression", values: values)
        minimumOSVersion = try Self.stringValue(for: "min-os-version", in: values)
        usesLargePayload = try Self.boolValue(for: "large-payload", in: values) ?? defaults.usesLargePayload
        postInstallAction = try Self.enumValue(PostInstallAction.self, key: "postinstall_action", values: values) ?? defaults.postInstallAction
        preservesExtendedAttributes = try Self.boolValue(for: "preserve_xattr", in: values) ?? defaults.preservesExtendedAttributes
        suppressesBundleRelocation = try Self.boolValue(for: "suppress_bundle_relocation", in: values) ?? defaults.suppressesBundleRelocation
        usesDistributionStyle = try Self.boolValue(for: "distribution_style", in: values) ?? defaults.usesDistributionStyle
        title = try Self.stringValue(for: "title", in: values)
        productIdentifier = try Self.stringValue(for: "product id", in: values)
        signing = try Self.signingConfiguration(in: values)
        notarization = try Self.notarizationConfiguration(in: values)
    }

    /// Returns a copy with `${version}` substituted in user-facing name fields.
    public func substitutingVersion() -> PackageConfiguration {
        func replacingVersion(in value: String?) -> String? {
            value?.replacingOccurrences(of: "${version}", with: version)
        }
        return PackageConfiguration(
            name: replacingVersion(in: name)!, identifier: identifier, version: version, ownership: ownership,
            installLocation: installLocation, compression: compression, minimumOSVersion: minimumOSVersion,
            usesLargePayload: usesLargePayload, postInstallAction: postInstallAction,
            preservesExtendedAttributes: preservesExtendedAttributes, suppressesBundleRelocation: suppressesBundleRelocation,
            usesDistributionStyle: usesDistributionStyle, title: replacingVersion(in: title), productIdentifier: productIdentifier,
            signing: signing, notarization: notarization
        )
    }

    /// Encodes this configuration using the stable, legacy on-disk keys.
    public var encodedValues: [String: Any] {
        var values: [String: Any] = [
            "name": name, "identifier": identifier, "version": version, "ownership": ownership.rawValue,
            "postinstall_action": postInstallAction.rawValue, "preserve_xattr": preservesExtendedAttributes,
            "suppress_bundle_relocation": suppressesBundleRelocation, "distribution_style": usesDistributionStyle
        ]
        if let installLocation { values["install_location"] = installLocation }
        if let compression { values["compression"] = compression.rawValue }
        if let minimumOSVersion { values["min-os-version"] = minimumOSVersion }
        if usesLargePayload { values["large-payload"] = true }
        if let title { values["title"] = title }
        if let productIdentifier { values["product id"] = productIdentifier }
        if let signing { values["signing_info"] = signing.encodedValues }
        if let notarization { values["notarization_info"] = notarization.encodedValues }
        return values
    }

    private static func stringValue(for key: String, in values: [String: Any]) throws -> String? {
        guard let value = values[key] else { return nil }
        guard let string = scalarString(value) else { throw MunkiPkgError.invalidConfiguration("build-info key '\(key)' must be a string") }
        return string
    }

    private static func boolValue(for key: String, in values: [String: Any]) throws -> Bool? {
        guard let value = values[key] else { return nil }
        guard let bool = value as? Bool else { throw MunkiPkgError.invalidConfiguration("build-info key '\(key)' must be a Boolean") }
        return bool
    }

    private static func enumValue<T: RawRepresentable>(_ type: T.Type, key: String, values: [String: Any]) throws -> T? where T.RawValue == String {
        guard let string = try stringValue(for: key, in: values) else { return nil }
        guard let value = T(rawValue: string) else { throw MunkiPkgError.invalidConfiguration("build-info key '\(key)' has illegal value: \(string)") }
        return value
    }

    private static func signingConfiguration(in values: [String: Any]) throws -> SigningConfiguration? {
        guard let value = values["signing_info"] else { return nil }
        guard let signing = value as? [String: Any], let identity = signing["identity"] as? String else {
            throw MunkiPkgError.invalidConfiguration("signing_info must contain a string identity")
        }
        let certificates: [String]
        if let certificate = signing["additional_cert_names"] as? String { certificates = [certificate] }
        else if let values = signing["additional_cert_names"] as? [String] { certificates = values }
        else if signing["additional_cert_names"] == nil { certificates = [] }
        else { throw MunkiPkgError.invalidConfiguration("signing_info additional_cert_names must be a string or string array") }
        return SigningConfiguration(identity: identity, keychain: signing["keychain"] as? String, additionalCertificateNames: certificates, usesTimestamp: signing["timestamp"] as? Bool)
    }

    private static func notarizationConfiguration(in values: [String: Any]) throws -> NotarizationConfiguration? {
        guard let value = values["notarization_info"] else { return nil }
        guard let notary = value as? [String: Any] else { throw MunkiPkgError.invalidConfiguration("notarization_info must be a dictionary") }
        let authentication: NotarizationConfiguration.Authentication
        if let appleID = notary["apple_id"] as? String, let teamID = notary["team_id"] as? String, let password = notary["password"] as? String {
            authentication = .appleID(appleID: appleID, teamID: teamID, password: password)
        } else if let profile = notary["keychain_profile"] as? String {
            authentication = .keychainProfile(profile)
        } else {
            throw MunkiPkgError.invalidConfiguration("notarization_info must specify apple_id + team_id + password or keychain_profile")
        }
        let timeout = (notary["staple_timeout"] as? NSNumber)?.intValue ?? 300
        return NotarizationConfiguration(authentication: authentication, staplingTimeout: timeout)
    }
}

private extension SigningConfiguration {
    var encodedValues: [String: Any] {
        var values: [String: Any] = ["identity": identity]
        if let keychain { values["keychain"] = keychain }
        if additionalCertificateNames.count == 1 { values["additional_cert_names"] = additionalCertificateNames[0] }
        else if !additionalCertificateNames.isEmpty { values["additional_cert_names"] = additionalCertificateNames }
        if let usesTimestamp { values["timestamp"] = usesTimestamp }
        return values
    }
}

private extension NotarizationConfiguration {
    var encodedValues: [String: Any] {
        var values: [String: Any] = ["staple_timeout": staplingTimeout]
        switch authentication {
        case let .appleID(appleID, teamID, password): values.merge(["apple_id": appleID, "team_id": teamID, "password": password]) { _, new in new }
        case let .keychainProfile(profile): values["keychain_profile"] = profile
        }
        return values
    }
}

/// Loads and saves package configuration files in plist, JSON, or YAML form.
public enum BuildInfoStore {
    public static func load(from project: URL, requestedFormat: BuildInfoFormat?, fileManager: FileManager = .default) throws -> PackageConfiguration {
        let document = try discover(in: project, requestedFormat: requestedFormat, fileManager: fileManager)
        return try loadTemplate(from: document.url, defaultsFor: project).substitutingVersion()
    }

    public static func loadTemplate(from project: URL, requestedFormat: BuildInfoFormat? = nil, fileManager: FileManager = .default) throws -> PackageConfiguration {
        let document = try discover(in: project, requestedFormat: requestedFormat, fileManager: fileManager)
        return try loadTemplate(from: document.url, defaultsFor: project)
    }

    public static func loadTemplate(from url: URL, defaultsFor project: URL) throws -> PackageConfiguration {
        let format = try format(for: url)
        let data = try Data(contentsOf: url)
        let object: Any
        do {
            switch format {
            case .plist: object = try PropertyListSerialization.propertyList(from: data, format: nil)
            case .json: object = try JSONSerialization.jsonObject(with: data)
            case .yaml, .yml: object = try Yams.load(yaml: String(decoding: data, as: UTF8.self)) as Any
            }
        } catch { throw MunkiPkgError.invalidConfiguration("\(url.path) is not a valid \(format.rawValue) file: \(error.localizedDescription)") }
        guard let values = object as? [String: Any] else { throw MunkiPkgError.invalidConfiguration("\(url.path) must contain a dictionary") }
        return try PackageConfiguration(values: values, defaults: .defaults(for: project))
    }

    public static func write(_ configuration: PackageConfiguration, to project: URL, format: BuildInfoFormat) throws {
        let url = project.appendingPathComponent("build-info").appendingPathExtension(format.rawValue)
        try write(configuration, toFile: url, format: format)
    }

    public static func write(_ configuration: PackageConfiguration, toFile url: URL, format: BuildInfoFormat) throws {
        let data: Data
        switch format {
        case .plist: data = try PropertyListSerialization.data(fromPropertyList: configuration.encodedValues, format: .xml, options: 0)
        case .json: data = try JSONSerialization.data(withJSONObject: configuration.encodedValues, options: [.prettyPrinted, .sortedKeys])
        case .yaml, .yml: data = Data(try Yams.dump(object: configuration.encodedValues, sortKeys: true).utf8)
        }
        try data.write(to: url, options: .atomic)
    }

    public static func discover(in project: URL, requestedFormat: BuildInfoFormat? = nil, fileManager: FileManager = .default) throws -> BuildInfoDocument {
        if let requestedFormat {
            let url = project.appendingPathComponent("build-info").appendingPathExtension(requestedFormat.rawValue)
            guard fileManager.itemExists(at: url) else { throw MunkiPkgError.invalidConfiguration("No build-info file found!") }
            return BuildInfoDocument(url: url, format: requestedFormat)
        }
        let baseURL = project.appendingPathComponent("build-info")
        let formats = BuildInfoFormat.allCases.filter { fileManager.itemExists(at: baseURL.appendingPathExtension($0.rawValue)) }
        guard formats.count <= 1 else { throw MunkiPkgError.invalidConfiguration("Multiple build-info files found!") }
        guard let format = formats.first else { throw MunkiPkgError.invalidConfiguration("No build-info file found!") }
        return BuildInfoDocument(url: baseURL.appendingPathExtension(format.rawValue), format: format)
    }

    private static func format(for url: URL) throws -> BuildInfoFormat {
        guard let format = BuildInfoFormat(rawValue: url.pathExtension.lowercased()) else {
            throw MunkiPkgError.invalidConfiguration("Unsupported build-info format: \(url.pathExtension)")
        }
        return format
    }
}
