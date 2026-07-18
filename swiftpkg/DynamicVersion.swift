import Foundation

/// Resolves dynamic date/time tokens in a build-info version string.
///
///   ${TIMESTAMP} -> yyyy.MM.dd.HHmm   (e.g. 2026.07.18.1405)
///   ${DATE}      -> yyyy.MM.dd        (e.g. 2026.07.18)
///   ${DATETIME}  -> yyyy.MM.dd.HHmmss (e.g. 2026.07.18.140530)
///
/// Tokens are distinct (none is a substring of another), so replacement order is
/// irrelevant. Matches munki-pkg's behavior.
public enum DynamicVersion {
    public static func resolve(_ version: String, now: Date = Date()) -> String {
        guard version.contains("${") else { return version }
        func stamp(_ format: String) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            return formatter.string(from: now)
        }
        return version
            .replacingOccurrences(of: "${TIMESTAMP}", with: stamp("yyyy.MM.dd.HHmm"))
            .replacingOccurrences(of: "${DATE}", with: stamp("yyyy.MM.dd"))
            .replacingOccurrences(of: "${DATETIME}", with: stamp("yyyy.MM.dd.HHmmss"))
    }
}
