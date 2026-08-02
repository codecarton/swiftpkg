import Foundation

/// Editable, lossless settings used by graphical and other interactive frontends.
public struct PackageSettingsDraft: Equatable, Sendable {
    public var name: String
    public var identifier: String
    public var version: String
    public var ownership: PackageOwnership
    public var installLocation: String
    public var compression: PackageCompression?
    public var minimumOSVersion: String
    public var usesLargePayload: Bool
    public var postInstallAction: PostInstallAction
    public var preservesExtendedAttributes: Bool
    public var suppressesBundleRelocation: Bool
    public var usesDistributionStyle: Bool
    public var title: String
    public var productIdentifier: String
    public var signingEnabled: Bool
    public var signingIdentity: String
    public var signingKeychain: String
    public var additionalCertificateNamesText: String
    public var signingTimestampMode: SigningTimestampMode
    public var notarizationMode: NotarizationAuthenticationMode
    public var notarizationAppleID: String
    public var notarizationTeamID: String
    public var notarizationPassword: String
    public var notarizationKeychainProfile: String
    public var staplingTimeout: Int

    public init(configuration: PackageConfiguration) {
        name = configuration.name
        identifier = configuration.identifier
        version = configuration.version
        ownership = configuration.ownership
        installLocation = configuration.installLocation ?? ""
        compression = configuration.compression
        minimumOSVersion = configuration.minimumOSVersion ?? ""
        usesLargePayload = configuration.usesLargePayload
        postInstallAction = configuration.postInstallAction
        preservesExtendedAttributes = configuration.preservesExtendedAttributes
        suppressesBundleRelocation = configuration.suppressesBundleRelocation
        usesDistributionStyle = configuration.usesDistributionStyle
        title = configuration.title ?? ""
        productIdentifier = configuration.productIdentifier ?? ""
        signingEnabled = configuration.signing != nil
        signingIdentity = configuration.signing?.identity ?? ""
        signingKeychain = configuration.signing?.keychain ?? ""
        additionalCertificateNamesText = configuration.signing?.additionalCertificateNames.joined(separator: "\n") ?? ""
        signingTimestampMode = switch configuration.signing?.usesTimestamp {
        case .some(true): .enabled
        case .some(false): .disabled
        case .none: .automatic
        }
        staplingTimeout = configuration.notarization?.staplingTimeout ?? 300
        switch configuration.notarization?.authentication {
        case let .appleID(appleID, teamID, password):
            notarizationMode = .appleID
            notarizationAppleID = appleID
            notarizationTeamID = teamID
            notarizationPassword = password
            notarizationKeychainProfile = ""
        case let .keychainProfile(profile):
            notarizationMode = .keychainProfile
            notarizationAppleID = ""
            notarizationTeamID = ""
            notarizationPassword = ""
            notarizationKeychainProfile = profile
        case nil, .invalid?:
            notarizationMode = .none
            notarizationAppleID = ""
            notarizationTeamID = ""
            notarizationPassword = ""
            notarizationKeychainProfile = ""
        }
    }

    public static func defaults(for project: URL) -> PackageSettingsDraft {
        PackageSettingsDraft(configuration: .defaults(for: project))
    }

    public func validatedConfiguration() throws -> PackageConfiguration {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw MunkiPkgError.invalidConfiguration("Package name is required.") }
        guard !trimmedIdentifier.isEmpty else { throw MunkiPkgError.invalidConfiguration("Package identifier is required.") }
        guard !trimmedVersion.isEmpty else { throw MunkiPkgError.invalidConfiguration("Package version is required.") }

        let signing: SigningConfiguration?
        if signingEnabled {
            let identity = signingIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identity.isEmpty else { throw MunkiPkgError.invalidConfiguration("A signing identity is required when signing is enabled.") }
            let usesTimestamp: Bool? = switch signingTimestampMode {
            case .automatic: nil
            case .enabled: true
            case .disabled: false
            }
            signing = SigningConfiguration(
                identity: identity,
                keychain: optional(signingKeychain),
                additionalCertificateNames: additionalCertificateNamesText
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty },
                usesTimestamp: usesTimestamp
            )
        } else {
            signing = nil
        }

        let notarization: NotarizationConfiguration?
        switch notarizationMode {
        case .none:
            notarization = nil
        case .keychainProfile:
            guard let profile = optional(notarizationKeychainProfile) else {
                throw MunkiPkgError.invalidConfiguration("A keychain profile is required for notarization.")
            }
            guard staplingTimeout > 0 else { throw MunkiPkgError.invalidConfiguration("Stapling timeout must be greater than zero.") }
            notarization = NotarizationConfiguration(authentication: .keychainProfile(profile), staplingTimeout: staplingTimeout)
        case .appleID:
            guard let appleID = optional(notarizationAppleID),
                  let teamID = optional(notarizationTeamID) else {
                throw MunkiPkgError.invalidConfiguration("Apple ID and team ID are required for Apple ID notarization.")
            }
            guard staplingTimeout > 0 else { throw MunkiPkgError.invalidConfiguration("Stapling timeout must be greater than zero.") }
            let password = optional(notarizationPassword) ?? ""
            notarization = NotarizationConfiguration(
                authentication: .appleID(appleID: appleID, teamID: teamID, password: password),
                staplingTimeout: staplingTimeout
            )
        }

        return PackageConfiguration(
            name: trimmedName,
            identifier: trimmedIdentifier,
            version: trimmedVersion,
            ownership: ownership,
            installLocation: optional(installLocation),
            compression: compression,
            minimumOSVersion: optional(minimumOSVersion),
            usesLargePayload: usesLargePayload,
            postInstallAction: postInstallAction,
            preservesExtendedAttributes: preservesExtendedAttributes,
            suppressesBundleRelocation: suppressesBundleRelocation,
            usesDistributionStyle: usesDistributionStyle,
            title: optional(title),
            productIdentifier: optional(productIdentifier),
            signing: signing,
            notarization: notarization
        )
    }

    private func optional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
