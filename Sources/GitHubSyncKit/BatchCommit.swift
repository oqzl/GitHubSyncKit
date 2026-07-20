import Foundation

extension GitHubClient {
    public func commitBatch(owner: String, repository: String, branch: String, changes: [GitHubFileChange], message: String, expectedHeadSHA: String? = nil, author: GitHubCommitIdentity? = nil) async throws -> GitHubCommitResult {
        struct RefResponse: Decodable { struct Object: Decodable { let sha: String }; let object: Object }
        struct CommitResponse: Decodable { struct Tree: Decodable { let sha: String }; let sha: String; let tree: Tree }
        struct BlobBody: Encodable { let content: String; let encoding = "base64" }
        struct BlobResponse: Decodable { let sha: String }
        struct TreeEntry: Encodable {
            let path, mode, type: String
            let sha: String?
            enum CodingKeys: String, CodingKey { case path, mode, type, sha }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(path, forKey: .path)
                try container.encode(mode, forKey: .mode)
                try container.encode(type, forKey: .type)
                if let sha { try container.encode(sha, forKey: .sha) } else { try container.encodeNil(forKey: .sha) }
            }
        }
        struct TreeBody: Encodable { let base_tree: String; let tree: [TreeEntry] }
        struct TreeResponse: Decodable { let sha: String }
        struct CommitBody: Encodable { let message, tree: String; let parents: [String]; let author: GitHubCommitIdentity? }
        struct NewCommit: Decodable { let sha: String }
        struct UpdateRefBody: Encodable { let sha: String; let force = false }
        struct Empty: Decodable {}

        let (ref, rate1): (RefResponse, GitHubRateLimit) = try await http.request(path: "repos/\(owner)/\(repository)/git/ref/heads/\(branch)")
        lastRateLimit = rate1
        if let expectedHeadSHA, expectedHeadSHA != ref.object.sha { throw GitHubSyncError.conflict(message: "Branch HEAD changed") }
        let (parent, rate2): (CommitResponse, GitHubRateLimit) = try await http.request(path: "repos/\(owner)/\(repository)/git/commits/\(ref.object.sha)")
        lastRateLimit = rate2

        var entries: [TreeEntry] = []
        for change in changes {
            switch change {
            case .upsert(let path, let data):
                let (blob, rate): (BlobResponse, GitHubRateLimit) = try await http.request("POST", path: "repos/\(owner)/\(repository)/git/blobs", body: BlobBody(content: data.base64EncodedString()))
                lastRateLimit = rate
                entries.append(.init(path: path, mode: "100644", type: "blob", sha: blob.sha))
            case .delete(let path): entries.append(.init(path: path, mode: "100644", type: "blob", sha: nil))
            }
        }
        let (tree, rate3): (TreeResponse, GitHubRateLimit) = try await http.request("POST", path: "repos/\(owner)/\(repository)/git/trees", body: TreeBody(base_tree: parent.tree.sha, tree: entries))
        lastRateLimit = rate3
        let (commit, rate4): (NewCommit, GitHubRateLimit) = try await http.request("POST", path: "repos/\(owner)/\(repository)/git/commits", body: CommitBody(message: message, tree: tree.sha, parents: [parent.sha], author: author))
        lastRateLimit = rate4
        do {
            let (_, rate5): (Empty, GitHubRateLimit) = try await http.request("PATCH", path: "repos/\(owner)/\(repository)/git/refs/heads/\(branch)", body: UpdateRefBody(sha: commit.sha))
            lastRateLimit = rate5
        } catch GitHubSyncError.validationFailed(let message) {
            throw GitHubSyncError.conflict(message: message ?? "Branch changed before the ref update")
        }
        return .init(commitSHA: commit.sha, contentSHA: nil)
    }
}
