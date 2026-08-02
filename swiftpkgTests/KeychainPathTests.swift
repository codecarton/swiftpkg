import Foundation
import Testing
@testable import SwiftPkgCore

struct KeychainPathTests {

    @Test("expands ${HOME} to the user's home directory")
    func expandsHome() {
        let expanded = expandKeychainPath("${HOME}/Library/Keychains/signing.keychain")
        #expect(expanded == "\(NSHomeDirectory())/Library/Keychains/signing.keychain")
        #expect(!expanded.contains("${HOME}"))
    }

    @Test("expands a leading tilde")
    func expandsTilde() {
        let expanded = expandKeychainPath("~/Library/Keychains/signing.keychain")
        #expect(expanded == "\(NSHomeDirectory())/Library/Keychains/signing.keychain")
    }

    @Test("leaves an absolute path unchanged")
    func leavesAbsolutePathUnchanged() {
        let path = "/Library/Keychains/System.keychain"
        #expect(expandKeychainPath(path) == path)
    }

    @Test("leaves a bare keychain name unchanged")
    func leavesBareNameUnchanged() {
        #expect(expandKeychainPath("login.keychain") == "login.keychain")
    }
}
