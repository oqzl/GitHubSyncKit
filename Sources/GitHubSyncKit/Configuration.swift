import Foundation

public struct GitHubConfiguration: Sendable {
    public var apiBaseURL: URL
    public var webBaseURL: URL
    public var apiVersion: String
    public var userAgent: String

    public init(
        apiBaseURL: URL = URL(string: "https://api.github.com")!,
        webBaseURL: URL = URL(string: "https://github.com")!,
        apiVersion: String = "2022-11-28",
        userAgent: String = "GitHubSyncKit/0.1.0"
    ) {
        self.apiBaseURL = apiBaseURL
        self.webBaseURL = webBaseURL
        self.apiVersion = apiVersion
        self.userAgent = userAgent
    }
}

public struct GitHubOAuthConfiguration: Sendable {
    public let clientID: String
    public let callbackURL: URL
    public let scopes: [String]

    public init(clientID: String, callbackURL: URL, scopes: [String] = ["repo"]) {
        self.clientID = clientID
        self.callbackURL = callbackURL
        self.scopes = scopes
    }
}
