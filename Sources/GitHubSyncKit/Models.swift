import Foundation

public struct GitHubUser: Codable, Sendable, Identifiable, Equatable {
    public let id: Int64
    public let login: String
    public let name: String?
    public let avatarURL: URL?

    enum CodingKeys: String, CodingKey { case id, login, name; case avatarURL = "avatar_url" }
}

public struct GitHubRepositoryPermissions: Codable, Sendable, Equatable {
    public let admin: Bool?
    public let maintain: Bool?
    public let push: Bool?
    public let triage: Bool?
    public let pull: Bool?
}

public struct GitHubRepositoryOwner: Codable, Sendable, Equatable {
    public let login: String
}

public struct GitHubRepository: Codable, Sendable, Identifiable, Equatable {
    public let id: Int64
    public let name: String
    public let fullName: String
    public let owner: GitHubRepositoryOwner
    public let isPrivate: Bool
    public let defaultBranch: String
    public let description: String?
    public let permissions: GitHubRepositoryPermissions?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, owner, description, permissions
        case fullName = "full_name"
        case isPrivate = "private"
        case defaultBranch = "default_branch"
        case updatedAt = "updated_at"
    }

    public var canPush: Bool { permissions?.push == true || permissions?.admin == true || permissions?.maintain == true }
}

public struct GitHubBranch: Codable, Sendable, Equatable {
    public struct Commit: Codable, Sendable, Equatable { public let sha: String }
    public let name: String
    public let commit: Commit
}

public struct GitHubContent: Codable, Sendable, Equatable {
    public let type: String
    public let name: String
    public let path: String
    public let sha: String
    public let size: Int?
    public let encoding: String?
    public let content: String?
    public let downloadURL: URL?

    enum CodingKeys: String, CodingKey { case type, name, path, sha, size, encoding, content; case downloadURL = "download_url" }

    public var decodedData: Data? {
        guard encoding == "base64", let content else { return nil }
        return Data(base64Encoded: content.replacingOccurrences(of: "\n", with: ""))
    }
}

public struct GitHubCommitIdentity: Codable, Sendable, Equatable {
    public let name: String
    public let email: String
    public init(name: String, email: String) { self.name = name; self.email = email }
}

public struct GitHubCommitResult: Sendable, Equatable {
    public let commitSHA: String
    public let contentSHA: String?
    public init(commitSHA: String, contentSHA: String?) { self.commitSHA = commitSHA; self.contentSHA = contentSHA }
}

public struct GitHubSyncDestination: Codable, Sendable, Equatable {
    public let repositoryID: Int64
    public let owner: String
    public let repository: String
    public let branch: String
    public let directory: String?

    public init(repositoryID: Int64, owner: String, repository: String, branch: String, directory: String? = nil) {
        self.repositoryID = repositoryID
        self.owner = owner
        self.repository = repository
        self.branch = branch
        self.directory = directory?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    public func resolvedPath(_ path: String) -> String {
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let directory, !directory.isEmpty else { return clean }
        return directory + "/" + clean
    }
}

public enum GitHubFileChange: Sendable, Equatable {
    case upsert(path: String, data: Data)
    case delete(path: String)
}

public struct GitHubRateLimit: Sendable, Equatable {
    public let limit: Int?
    public let remaining: Int?
    public let reset: Date?
}
