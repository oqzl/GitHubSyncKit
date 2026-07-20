import Foundation

public enum GitHubSyncError: Error, Sendable, LocalizedError {
    case invalidResponse
    case unauthorized
    case forbidden(String?)
    case notFound
    case conflict(message: String?)
    case validationFailed(String?)
    case rateLimited(reset: Date?)
    case api(status: Int, message: String?)
    case invalidOAuthState
    case oauthDenied(String?)
    case missingToken
    case invalidConfiguration(String)
    case unsupportedPlatform

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "GitHubから不正なレスポンスを受信しました。"
        case .unauthorized: "GitHubの認証が必要です。"
        case .forbidden(let message): message ?? "GitHub APIへのアクセスが拒否されました。"
        case .notFound: "対象が見つかりません。"
        case .conflict(let message): message ?? "リモート側に新しい変更があります。"
        case .validationFailed(let message): message ?? "GitHub APIの入力検証に失敗しました。"
        case .rateLimited(let reset): reset.map { "GitHub APIのレート制限に達しました。解除予定: \($0)" } ?? "GitHub APIのレート制限に達しました。"
        case .api(let status, let message): "GitHub APIエラー (\(status)): \(message ?? "詳細なし")"
        case .invalidOAuthState: "OAuth stateが一致しません。"
        case .oauthDenied(let message): message ?? "GitHub OAuth認証がキャンセルされました。"
        case .missingToken: "アクセストークンが保存されていません。"
        case .invalidConfiguration(let message): message
        case .unsupportedPlatform: "この機能は現在のプラットフォームでは利用できません。"
        }
    }
}

struct GitHubErrorEnvelope: Decodable { let message: String? }
