import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol GitHubHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionGitHubTransport: GitHubHTTPTransport {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubSyncError.invalidResponse }
        return (data, http)
    }
}

struct GitHubHTTPClient: Sendable {
    let configuration: GitHubConfiguration
    let tokenStore: any GitHubTokenStore
    let transport: any GitHubHTTPTransport

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func request<T: Decodable>(
        _ method: String = "GET",
        path: String,
        query: [URLQueryItem] = [],
        body: Encodable? = nil,
        accept: String = "application/vnd.github+json"
    ) async throws -> (T, GitHubRateLimit) {
        var components = URLComponents(url: configuration.apiBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw GitHubSyncError.invalidConfiguration("Invalid GitHub API URL") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(configuration.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        if let token = try await tokenStore.loadToken() { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        let (data, response) = try await transport.data(for: request)
        let rate = Self.rateLimit(from: response)
        guard (200..<300).contains(response.statusCode) else { throw Self.mapError(data: data, response: response, rate: rate) }
        return (try Self.decoder.decode(T.self, from: data), rate)
    }

    private static func rateLimit(from response: HTTPURLResponse) -> GitHubRateLimit {
        let limit = response.value(forHTTPHeaderField: "X-RateLimit-Limit").flatMap(Int.init)
        let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap(Int.init)
        let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
        return .init(limit: limit, remaining: remaining, reset: reset)
    }

    private static func mapError(data: Data, response: HTTPURLResponse, rate: GitHubRateLimit) -> Error {
        let message = try? decoder.decode(GitHubErrorEnvelope.self, from: data).message
        switch response.statusCode {
        case 401: return GitHubSyncError.unauthorized
        case 403 where rate.remaining == 0: return GitHubSyncError.rateLimited(reset: rate.reset)
        case 403: return GitHubSyncError.forbidden(message)
        case 404: return GitHubSyncError.notFound
        case 409: return GitHubSyncError.conflict(message: message)
        case 422: return GitHubSyncError.validationFailed(message)
        default: return GitHubSyncError.api(status: response.statusCode, message: message)
        }
    }
}

private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeValue = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
}
