import SwiftPkgCore

extension PostInstallAction {
    var displayName: String {
        switch self {
        case .none: "None"
        case .logout: "Log Out"
        case .restart: "Restart"
        }
    }
}
