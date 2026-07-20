import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct GitHubOAuthCode: Sendable, Equatable {
    public let code: String
    public let redirectURI: URL
    public let codeVerifier: String
}

public protocol GitHubOAuthTokenExchanger: Sendable {
    func exchange(_ code: GitHubOAuthCode) async throws -> String
}

public struct BackendOAuthTokenExchanger: GitHubOAuthTokenExchanger {
    private let endpoint: URL
    private let session: URLSession
    public init(endpoint: URL, session: URLSession = .shared) { self.endpoint = endpoint; self.session = session }

    public func exchange(_ code: GitHubOAuthCode) async throws -> String {
        struct Request: Encodable { let code: String; let redirectURI: String; let codeVerifier: String }
        struct Response: Decodable { let accessToken: String }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Request(code: code.code, redirectURI: code.redirectURI.absoluteString, codeVerifier: code.codeVerifier))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw GitHubSyncError.unauthorized }
        return try JSONDecoder().decode(Response.self, from: data).accessToken
    }
}

public struct GitHubDeviceCode: Decodable, Sendable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURI: URL
    public let expiresIn: Int
    public let interval: Int
    enum CodingKeys: String, CodingKey { case deviceCode = "device_code", userCode = "user_code", verificationURI = "verification_uri", expiresIn = "expires_in", interval }
}

public actor GitHubDeviceFlow {
    private let oauth: GitHubOAuthConfiguration
    private let configuration: GitHubConfiguration
    private let session: URLSession

    public init(oauth: GitHubOAuthConfiguration, configuration: GitHubConfiguration = .init(), session: URLSession = .shared) {
        self.oauth = oauth; self.configuration = configuration; self.session = session
    }

    public func requestCode() async throws -> GitHubDeviceCode {
        let url = configuration.webBaseURL.appendingPathComponent("login/device/code")
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = form(["client_id": oauth.clientID, "scope": oauth.scopes.joined(separator: " ")])
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw GitHubSyncError.unauthorized }
        return try JSONDecoder().decode(GitHubDeviceCode.self, from: data)
    }

    public func pollToken(deviceCode: GitHubDeviceCode) async throws -> String {
        struct TokenResponse: Decodable { let accessToken: String?; let error: String?; let interval: Int?; enum CodingKeys: String, CodingKey { case accessToken = "access_token", error, interval } }
        var wait = max(deviceCode.interval, 5)
        let deadline = Date().addingTimeInterval(TimeInterval(deviceCode.expiresIn))
        while Date() < deadline {
            try await Task.sleep(for: .seconds(wait))
            var request = URLRequest(url: configuration.webBaseURL.appendingPathComponent("login/oauth/access_token")); request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept"); request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = form(["client_id": oauth.clientID, "device_code": deviceCode.deviceCode, "grant_type": "urn:ietf:params:oauth:grant-type:device_code"])
            let (data, _) = try await session.data(for: request)
            let result = try JSONDecoder().decode(TokenResponse.self, from: data)
            if let token = result.accessToken { return token }
            switch result.error {
            case "authorization_pending": continue
            case "slow_down": wait += 5
            case "access_denied": throw GitHubSyncError.oauthDenied(nil)
            case "expired_token": throw GitHubSyncError.oauthDenied("Device code expired")
            default: throw GitHubSyncError.oauthDenied(result.error)
            }
        }
        throw GitHubSyncError.oauthDenied("Device code expired")
    }

    private func form(_ values: [String: String]) -> Data {
        Data(values.map { key, value in "\(key.urlEncoded)=\(value.urlEncoded)" }.joined(separator: "&").utf8)
    }
}

private extension String {
    var urlEncoded: String { addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))) ?? self }
}
