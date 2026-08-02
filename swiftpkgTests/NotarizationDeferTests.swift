import Foundation
import Testing
@testable import SwiftPkgCore

struct NotarizationDeferTests {
    private var defaults: PackageConfiguration { .defaults(for: URL(fileURLWithPath: "/tmp/Proj")) }

    @Test("incomplete notarization_info loads as .invalid instead of throwing")
    func incompleteLoadsAsInvalid() throws {
        let values: [String: Any] = [
            "name": "Proj.pkg", "identifier": "com.example.proj", "version": "1.0",
            "notarization_info": ["password": "abcd-efgh-ijkl-mnop"]
        ]
        let config = try PackageConfiguration(values: values, defaults: defaults)
        guard case .invalid = try #require(config.notarization?.authentication) else {
            Issue.record("Expected .invalid authentication")
            return
        }
    }

    @Test("complete notarization_info still parses to a usable authentication")
    func completeParses() throws {
        let profileValues: [String: Any] = [
            "name": "Proj.pkg", "identifier": "com.example.proj", "version": "1.0",
            "notarization_info": ["keychain_profile": "notary"]
        ]
        let profile = try PackageConfiguration(values: profileValues, defaults: defaults)
        guard case .keychainProfile("notary") = try #require(profile.notarization?.authentication) else {
            Issue.record("Expected .keychainProfile")
            return
        }

        let appleValues: [String: Any] = [
            "name": "Proj.pkg", "identifier": "com.example.proj", "version": "1.0",
            "notarization_info": ["apple_id": "a@b.com", "team_id": "TEAM"]
        ]
        let apple = try PackageConfiguration(values: appleValues, defaults: defaults)
        guard case .appleID = try #require(apple.notarization?.authentication) else {
            Issue.record("Expected .appleID")
            return
        }
    }
}
