import SwiftPkgCore

extension PackageOwnership {
    var displayName: String {
        switch self {
        case .recommended: "Recommended"
        case .preserve: "Preserve"
        case .preserveOther: "Preserve Other"
        }
    }
}
