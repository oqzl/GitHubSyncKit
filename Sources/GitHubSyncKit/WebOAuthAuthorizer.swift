#if canImport(AuthenticationServices)
import AuthenticationServices
import CryptoKit
import Foundation

@MainActor
public final class GitHubWebOAuthAuthorizer: NSObject {
    private let oauth: GitHubOAuthConfiguration
    private let configuration: GitHubConfiguration
    private let presentationAnchor: @MainActor () -> ASPresentationAnchor
    private var session: ASWebAuthenticationSession?

    public init(oauth: GitHubOAuthConfiguration, configuration: GitHubConfiguration = .init(), presentationAnchor: @escaping @MainActor () -> ASPresentationAnchor) {
        self.oauth = oauth; self.configuration = configuration; self.presentationAnchor = presentationAnchor
    }

    public func authorize(using exchanger: any GitHubOAuthTokenExchanger) async throws -> String {
        let verifier = Self.randomURLSafe(length: 64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        let state = Self.randomURLSafe(length: 32)
        var components = URLComponents(url: configuration.webBaseURL.appendingPathComponent("login/oauth/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "client_id", value: oauth.clientID), .init(name: "redirect_uri", value: oauth.callbackURL.absoluteString),
            .init(name: "scope", value: oauth.scopes.joined(separator: " ")), .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components.url, let callbackScheme = oauth.callbackURL.scheme else { throw GitHubSyncError.invalidConfiguration("Invalid OAuth callback URL") }
        let callbackURL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { url, error in
                if let error { continuation.resume(throwing: error); return }
                guard let url else { continuation.resume(throwing: GitHubSyncError.invalidResponse); return }
                continuation.resume(returning: url)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            guard session.start() else { continuation.resume(throwing: GitHubSyncError.invalidResponse); return }
        }
        let params = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let error = params.first(where: { $0.name == "error" })?.value { throw GitHubSyncError.oauthDenied(error) }
        guard params.first(where: { $0.name == "state" })?.value == state else { throw GitHubSyncError.invalidOAuthState }
        guard let code = params.first(where: { $0.name == "code" })?.value else { throw GitHubSyncError.invalidResponse }
        return try await exchanger.exchange(.init(code: code, redirectURI: oauth.callbackURL, codeVerifier: verifier))
    }

    private static func randomURLSafe(length: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }
}

extension GitHubWebOAuthAuthorizer: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { presentationAnchor() }
}

private extension Data {
    func base64URLEncodedString() -> String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}
#endif
