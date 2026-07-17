import SwiftPkgCore

extension SigningTimestampMode {
    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .enabled: "Enabled"
        case .disabled: "Disabled"
        }
    }
}
