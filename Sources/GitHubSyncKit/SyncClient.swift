import Foundation

public actor GitHubSyncClient {
    public let api: GitHubClient
    private var destination: GitHubSyncDestination?

    public init(api: GitHubClient, destination: GitHubSyncDestination? = nil) {
        self.api = api
        self.destination = destination
    }

    public func setDestination(_ destination: GitHubSyncDestination) { self.destination = destination }
    public func currentDestination() -> GitHubSyncDestination? { destination }

    public func getFile(path: String) async throws -> GitHubContent {
        let d = try requireDestination()
        return try await api.content(owner: d.owner, repository: d.repository, path: d.resolvedPath(path), ref: d.branch)
    }

    public func commitFile(path: String, data: Data, message: String, expectedSHA: String? = nil) async throws -> GitHubCommitResult {
        let d = try requireDestination()
        return try await api.putFile(owner: d.owner, repository: d.repository, path: d.resolvedPath(path), data: data, message: message, branch: d.branch, expectedSHA: expectedSHA)
    }

    public func commitBatch(changes: [GitHubFileChange], message: String, expectedHeadSHA: String? = nil) async throws -> GitHubCommitResult {
        let d = try requireDestination()
        let resolved = changes.map { change -> GitHubFileChange in
            switch change { case .upsert(let path, let data): .upsert(path: d.resolvedPath(path), data: data); case .delete(let path): .delete(path: d.resolvedPath(path)) }
        }
        return try await api.commitBatch(owner: d.owner, repository: d.repository, branch: d.branch, changes: resolved, message: message, expectedHeadSHA: expectedHeadSHA)
    }

    private func requireDestination() throws -> GitHubSyncDestination {
        guard let destination else { throw GitHubSyncError.invalidConfiguration("Sync destination is not configured") }
        return destination
    }
}
