import SwiftPkgCore

extension BuildInfoFormat {
    var displayName: String {
        switch self {
        case .plist: "Property List"
        case .json: "JSON"
        case .yaml: "YAML"
        case .yml: "YAML (.yml)"
        }
    }
}

extension PackageOwnership {
    var displayName: String {
        switch self {
        case .recommended: "Recommended"
        case .preserve: "Preserve"
        case .preserveOther: "Preserve Other"
        }
    }
}

extension PackageCompression {
    var displayName: String {
        switch self {
        case .legacy: "Legacy"
        case .latest: "Latest"
        }
    }
}

extension PostInstallAction {
    var displayName: String {
        switch self {
        case .none: "None"
        case .logout: "Log Out"
        case .restart: "Restart"
        }
    }
}

extension SigningTimestampMode {
    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .enabled: "Enabled"
        case .disabled: "Disabled"
        }
    }
}

extension NotarizationAuthenticationMode {
    var displayName: String {
        switch self {
        case .none: "None"
        case .keychainProfile: "Keychain Profile"
        case .appleID: "Apple ID"
        }
    }
}
