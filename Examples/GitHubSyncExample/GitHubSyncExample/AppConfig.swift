import Foundation

enum AppConfig {
    static let clientID = string(for: "GitHubClientID")
    static let callbackScheme = string(for: "GitHubCallbackScheme")

    static var callbackURL: URL {
        guard let url = URL(string: "\(callbackScheme)://oauth/callback") else {
            preconditionFailure("Invalid GitHubCallbackScheme in Info.plist")
        }
        return url
    }

    private static func string(for key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
}
