import Foundation

public actor GitHubClient {
    let http: GitHubHTTPClient
    public internal(set) var lastRateLimit: GitHubRateLimit?

    public init(
        configuration: GitHubConfiguration = .init(),
        tokenStore: any GitHubTokenStore,
        transport: any GitHubHTTPTransport = URLSessionGitHubTransport()
    ) {
        self.http = .init(configuration: configuration, tokenStore: tokenStore, transport: transport)
    }

    public func currentUser() async throws -> GitHubUser {
        let (value, rate): (GitHubUser, GitHubRateLimit) = try await http.request(path: "user")
        lastRateLimit = rate
        return value
    }

    public func repositories(page: Int = 1, perPage: Int = 50, writableOnly: Bool = false) async throws -> [GitHubRepository] {
        let (items, rate): ([GitHubRepository], GitHubRateLimit) = try await http.request(
            path: "user/repos",
            query: [
                .init(name: "affiliation", value: "owner,collaborator,organization_member"),
                .init(name: "sort", value: "updated"), .init(name: "direction", value: "desc"),
                .init(name: "per_page", value: String(min(perPage, 100))), .init(name: "page", value: String(page))
            ]
        )
        lastRateLimit = rate
        return writableOnly ? items.filter(\.canPush) : items
    }

    public func searchRepositories(query: String, page: Int = 1, perPage: Int = 30, writableOnly: Bool = false) async throws -> [GitHubRepository] {
        struct SearchResponse: Decodable { let items: [GitHubRepository] }
        let (response, rate): (SearchResponse, GitHubRateLimit) = try await http.request(
            path: "search/repositories",
            query: [.init(name: "q", value: query), .init(name: "sort", value: "updated"), .init(name: "per_page", value: String(min(perPage, 100))), .init(name: "page", value: String(page))]
        )
        lastRateLimit = rate
        return writableOnly ? response.items.filter(\.canPush) : response.items
    }

    public func branches(owner: String, repository: String, page: Int = 1) async throws -> [GitHubBranch] {
        let (items, rate): ([GitHubBranch], GitHubRateLimit) = try await http.request(path: "repos/\(owner)/\(repository)/branches", query: [.init(name: "per_page", value: "100"), .init(name: "page", value: String(page))])
        lastRateLimit = rate
        return items
    }

    /// Returns the branch's current HEAD, including when the name contains `/`.
    public func branch(owner: String, repository: String, name: String) async throws -> GitHubBranch {
        struct Response: Decodable {
            struct Object: Decodable { let sha: String }
            let object: Object
        }

        let (response, rate): (Response, GitHubRateLimit) = try await http.request(
            path: "repos/\(owner)/\(repository)/git/ref/heads/\(name)"
        )
        lastRateLimit = rate
        return GitHubBranch(name: name, commit: .init(sha: response.object.sha))
    }

    /// Creates `name` from the supplied commit SHA and returns its initial HEAD.
    public func createBranch(
        owner: String,
        repository: String,
        name: String,
        fromCommitSHA: String
    ) async throws -> GitHubBranch {
        struct Body: Encodable { let ref: String; let sha: String }
        struct Response: Decodable {
            struct Object: Decodable { let sha: String }
            let ref: String
            let object: Object
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            throw GitHubSyncError.invalidConfiguration("ブランチ名を入力してください。")
        }

        let (response, rate): (Response, GitHubRateLimit) = try await http.request(
            "POST",
            path: "repos/\(owner)/\(repository)/git/refs",
            body: Body(ref: "refs/heads/\(cleanName)", sha: fromCommitSHA)
        )
        lastRateLimit = rate
        let createdName = response.ref.replacingOccurrences(of: "refs/heads/", with: "")
        return GitHubBranch(name: createdName, commit: .init(sha: response.object.sha))
    }

    public func content(owner: String, repository: String, path: String, ref: String? = nil) async throws -> GitHubContent {
        let query = ref.map { [URLQueryItem(name: "ref", value: $0)] } ?? []
        let (value, rate): (GitHubContent, GitHubRateLimit) = try await http.request(path: "repos/\(owner)/\(repository)/contents/\(path)", query: query)
        lastRateLimit = rate
        return value
    }

    public func listDirectory(owner: String, repository: String, path: String = "", ref: String? = nil) async throws -> [GitHubContent] {
        let query = ref.map { [URLQueryItem(name: "ref", value: $0)] } ?? []
        let (value, rate): ([GitHubContent], GitHubRateLimit) = try await http.request(path: "repos/\(owner)/\(repository)/contents/\(path)", query: query)
        lastRateLimit = rate
        return value
    }

    public func putFile(owner: String, repository: String, path: String, data: Data, message: String, branch: String, expectedSHA: String? = nil, author: GitHubCommitIdentity? = nil) async throws -> GitHubCommitResult {
        struct Body: Encodable { let message, content, branch: String; let sha: String?; let author: GitHubCommitIdentity? }
        struct Response: Decodable { struct Commit: Decodable { let sha: String }; struct Content: Decodable { let sha: String }; let commit: Commit; let content: Content? }
        let body = Body(message: message, content: data.base64EncodedString(), branch: branch, sha: expectedSHA, author: author)
        let (value, rate): (Response, GitHubRateLimit) = try await http.request("PUT", path: "repos/\(owner)/\(repository)/contents/\(path)", body: body)
        lastRateLimit = rate
        return .init(commitSHA: value.commit.sha, contentSHA: value.content?.sha)
    }

    public func deleteFile(owner: String, repository: String, path: String, message: String, branch: String, expectedSHA: String, author: GitHubCommitIdentity? = nil) async throws -> GitHubCommitResult {
        struct Body: Encodable { let message, sha, branch: String; let author: GitHubCommitIdentity? }
        struct Response: Decodable { struct Commit: Decodable { let sha: String }; let commit: Commit }
        let (value, rate): (Response, GitHubRateLimit) = try await http.request("DELETE", path: "repos/\(owner)/\(repository)/contents/\(path)", body: Body(message: message, sha: expectedSHA, branch: branch, author: author))
        lastRateLimit = rate
        return .init(commitSHA: value.commit.sha, contentSHA: nil)
    }
}
