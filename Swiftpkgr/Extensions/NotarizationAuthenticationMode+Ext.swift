import SwiftPkgCore

extension NotarizationAuthenticationMode {
    var displayName: String {
        switch self {
        case .none: "None"
        case .keychainProfile: "Keychain Profile"
        case .appleID: "Apple ID"
        }
    }
}
