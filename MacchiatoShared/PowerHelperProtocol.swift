import Foundation
import Security

enum PowerHelperConstants {
    static let appBundleIdentifier = "app.macchiato.Macchiato"
    static let helperBundleIdentifier = "app.macchiato.Macchiato.PowerHelper"
    static let machServiceName = "app.macchiato.Macchiato.PowerHelper"
    static let launchDaemonPlistName = "\(machServiceName).plist"

    static var appCodeSigningRequirement: String {
        codeSigningRequirement(for: appBundleIdentifier)
    }

    static var helperCodeSigningRequirement: String {
        codeSigningRequirement(for: helperBundleIdentifier)
    }

    private static func codeSigningRequirement(for bundleIdentifier: String) -> String {
        var requirement = #"identifier "\#(bundleIdentifier)""#

        if let teamIdentifier = currentTeamIdentifier() {
            requirement += #" and anchor apple generic and certificate leaf[subject.OU] = "\#(teamIdentifier)""#
        }

        return requirement
    }

    private static func currentTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }

        var signingInformation: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &signingInformation) == errSecSuccess,
              let information = signingInformation as? [String: Any],
              let teamIdentifier = information[kSecCodeInfoTeamIdentifier as String] as? String,
              !teamIdentifier.isEmpty else {
            return nil
        }

        return teamIdentifier
    }
}

@objc(PowerHelperProtocol)
protocol PowerHelperProtocol {
    func setSleepDisabled(_ disabled: Bool, withReply reply: @escaping (Bool, String?) -> Void)
    func getSleepDisabled(withReply reply: @escaping (Bool, String?) -> Void)
}
