import Foundation

public protocol GitHubTokenStore: Sendable {
    func loadToken() async throws -> String?
    func saveToken(_ token: String) async throws
    func deleteToken() async throws
}

public actor InMemoryTokenStore: GitHubTokenStore {
    private var token: String?
    public init(token: String? = nil) { self.token = token }
    public func loadToken() async throws -> String? { token }
    public func saveToken(_ token: String) async throws { self.token = token }
    public func deleteToken() async throws { token = nil }
}

#if canImport(Security)
import Security

public actor KeychainTokenStore: GitHubTokenStore {
    private let service: String
    private let account: String

    public init(service: String, account: String = "github-oauth-token") {
        self.service = service
        self.account = account
    }

    public func loadToken() async throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw GitHubSyncError.api(status: Int(status), message: "Keychain read failed")
        }
        return value
    }

    public func saveToken(_ token: String) async throws {
        try await deleteToken()
        let status = SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(token.utf8)
        ] as CFDictionary, nil)
        guard status == errSecSuccess else { throw GitHubSyncError.api(status: Int(status), message: "Keychain save failed") }
    }

    public func deleteToken() async throws {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitHubSyncError.api(status: Int(status), message: "Keychain delete failed")
        }
    }
}
#endif
