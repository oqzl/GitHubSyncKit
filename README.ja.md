# GitHubSyncKit — Swift向けGitHub API・OAuth・リポジトリ同期SDK

[English README](README.md)

GitHubSyncKitは、iOS／macOSアプリからGitHub REST APIを利用するためのSwift製GitHub SDKです。GitHub OAuth認証、書き込み可能なリポジトリの検索・選択、ファイル同期、単一ファイルのコミット、複数ファイルの原子的コミット、競合検知、Keychainへのトークン保存、SwiftUI製リポジトリ選択UIを提供します。

GitHubを保存先とするMarkdownノートアプリ、文書エディタ、設定ファイル同期ツール、静的サイト用コンテンツエディタ、GitHubへ生成ファイルをコミットするiOS／macOSアプリなどに利用できます。

## 主な機能

- Swift Package Manager対応
- Swift 6 Concurrencyと`async/await`対応
- Client Secretをアプリに埋め込まないGitHub OAuth Device Flow
- `ASWebAuthenticationSession`とPKCEを使ったGitHub OAuth Web Flow
- Web Flow用のバックエンドトークン交換抽象化
- Keychainへのアクセストークン保存
- GitHubユーザー情報の取得
- 書き込み可能なリポジトリの一覧、検索、選択
- ブランチ一覧の取得
- GitHub Repository Contents API対応
- ファイルの作成、更新、削除とGitコミット
- Git blob、tree、commit、refを使った複数ファイルの単一コミット
- SHAを使った楽観的ロックと競合検知
- 再利用可能なSwiftUIリポジトリ選択画面
- リファレンスiOSアプリとCloudflare Worker例
- 実行時の外部ライブラリ依存なし

## クイックスタート

```swift
import GitHubSyncKit

let tokenStore = KeychainTokenStore(service: "com.example.myapp")
let api = GitHubClient(tokenStore: tokenStore)

let repositories = try await api.repositories(writableOnly: true)
let repository = repositories[0]

let destination = GitHubSyncDestination(
    repositoryID: repository.id,
    owner: repository.owner.login,
    repository: repository.name,
    branch: repository.defaultBranch,
    directory: "notes"
)

let sync = GitHubSyncClient(api: api, destination: destination)

try await sync.commitFile(
    path: "hello.md",
    data: Data("# Hello from Swift".utf8),
    message: "Add hello.md",
    expectedSHA: nil
)
```

APIクライアントを利用する前にOAuth認証が必要です。詳細は[OAuth認証](#oauth認証)を参照してください。

## 想定用途

- GitHubリポジトリを保存先にするMarkdownノートアプリ
- GitHub連携文書エディタ
- リポジトリベースのバックアップ・同期機能
- 静的サイトやドキュメントのコンテンツ編集アプリ
- 設定ファイル管理ツール
- 生成したファイルをGitHubへコミットするアプリ
- iOS／macOS向けの軽量GitHubクライアント

## 動作要件

- Swift 6.0以降
- iOS 17以降
- macOS 14以降
- GitHub OAuth App

## インストール

XcodeのPackage Dependenciesに次のURLを追加します。

```text
https://github.com/oqzl/GitHubSyncKit.git
```

または`Package.swift`へ追加します。

```swift
dependencies: [
    .package(
        url: "https://github.com/oqzl/GitHubSyncKit.git",
        from: "0.1.0"
    )
]
```

Core SDKまたはSwiftUIコンポーネントをターゲットへ追加します。

```swift
.product(name: "GitHubSyncKit", package: "GitHubSyncKit")
.product(name: "GitHubSyncKitUI", package: "GitHubSyncKit")
```

## OAuth認証

GitHubSyncKitは、GitHub OAuth Appの2種類の認証方式に対応します。

| 認証方式 | バックエンド | Client Secretのアプリ内保持 | 主な用途 |
|---|---:|---:|---|
| Device Flow | 不要 | 不要 | サンプル、開発者向けツール、デバイスコード方式を許容できるアプリ |
| Web Flow | 必要 | 不要 | 一般利用者向けiOS／macOSアプリ |

GitHub OAuth AppのWeb Flowでは、認可コードをアクセストークンへ交換するときにOAuth Client Secretが必要です。PKCEを使用しても、このGitHub側の要件はなくなりません。iOS／macOSアプリへClient Secretを埋め込まないでください。

### GitHub OAuth Appの作成

1. GitHubのSettingsを開きます。
2. Developer settingsを開きます。
3. OAuth AppsからNew OAuth Appを選択します。
4. Application nameとHomepage URLを入力します。
5. リファレンスアプリを使う場合はDevice Flowを有効にします。
6. Client IDをアプリの設定へコピーします。
7. Web Flowを使う場合は、アプリとバックエンドで使用するCallback URLを登録します。

### Device Flow

Device Flowはアプリ内で完結し、OAuth Client IDだけで利用できます。

```swift
import GitHubSyncKit

let oauth = GitHubOAuthConfiguration(
    clientID: "YOUR_CLIENT_ID",
    callbackURL: URL(
        string: "io.github.oqzl.githubsynckit.example://oauth/callback"
    )!,
    scopes: ["repo"]
)

let flow = GitHubDeviceFlow(oauth: oauth)
let code = try await flow.requestCode()

// code.userCodeを表示し、code.verificationURIを開きます。
let token = try await flow.pollToken(deviceCode: code)

let tokenStore = KeychainTokenStore(service: "com.example.myapp")
try await tokenStore.saveToken(token)
```

### `ASWebAuthenticationSession`を使うWeb Flow

SDKは`ASWebAuthenticationSession`とPKCEを使って認可コードを取得します。その後、GitHub OAuth Client Secretを安全に保持するバックエンドでアクセストークンへ交換します。

```swift
let exchanger = BackendOAuthTokenExchanger(
    endpoint: URL(string: "https://example.com/oauth/github/exchange")!
)

let authorizer = GitHubWebOAuthAuthorizer(
    oauth: oauth,
    presentationAnchor: { window }
)

let token = try await authorizer.authorize(using: exchanger)
try await tokenStore.saveToken(token)
```

バックエンドへのリクエスト例：

```json
{
  "code": "temporary-code",
  "redirectURI": "myapp://github/oauth",
  "codeVerifier": "pkce-code-verifier"
}
```

バックエンドからのレスポンス例：

```json
{
  "accessToken": "gho_..."
}
```

バックエンドではリクエストを検証し、認可コードやトークンをログへ出力しないでください。GitHubのトークンエンドポイントを呼ぶときに、バックエンドが保持するOAuth Client Secretを追加します。

最小構成のCloudflare Worker例を`Examples/TokenExchangeWorker`に収録しています。

## GitHub APIクライアントの作成

```swift
let api = GitHubClient(tokenStore: tokenStore)
let user = try await api.currentUser()
let repositories = try await api.repositories(writableOnly: true)
```

`writableOnly`はGitHubのレスポンスに含まれる権限情報を使って絞り込みます。権限は後から変更される可能性があるため、実際の操作時に返される`403 Forbidden`も処理してください。

## リポジトリの検索と同期先設定

```swift
let repositories = try await api.repositories(writableOnly: true)

let matches = repositories.filter {
    $0.fullName.localizedCaseInsensitiveContains("notes")
}
```

同期先として、リポジトリ、ブランチ、任意のディレクトリを設定します。

```swift
let destination = GitHubSyncDestination(
    repositoryID: repository.id,
    owner: repository.owner.login,
    repository: repository.name,
    branch: repository.defaultBranch,
    directory: "notes"
)

let sync = GitHubSyncClient(api: api, destination: destination)
```

OAuth Appのスコープでは、アクセストークンの権限を選択した1リポジトリだけに制限できません。GitHubSyncKitはSDK自身の操作対象を設定済みの同期先に限定しますが、トークン自体はGitHubで許可されたスコープを保持します。トークンレベルでリポジトリを限定する必要がある場合は、GitHub AppまたはFine-grained Personal Access Tokenを使用してください。

## GitHub上のファイルを読む

```swift
let remote = try await sync.getFile(path: "example.md")
let data = remote.decodedData
```

## ファイルを作成・更新してコミットする

```swift
let result = try await sync.commitFile(
    path: "example.md",
    data: Data("# Example".utf8),
    message: "Update example note",
    expectedSHA: remote.sha
)
```

更新時には、事前に取得したblob SHAを渡します。リモート側で変更されてSHAが古くなっている場合、GitHubが更新を拒否するため競合を検知できます。

## ファイルを削除してコミットする

```swift
let result = try await sync.deleteFile(
    path: "obsolete.md",
    message: "Remove obsolete note",
    expectedSHA: remote.sha
)
```

## 複数ファイルを1コミットで更新する

```swift
let result = try await sync.commitBatch(
    changes: [
        .upsert(path: "a.md", data: Data("A".utf8)),
        .upsert(path: "b.md", data: Data("B".utf8)),
        .delete(path: "old.md")
    ],
    message: "Synchronize notes",
    expectedHeadSHA: lastKnownBranchHead
)
```

バッチコミットではGit blobとtreeを作成し、1つのGit commitを作成して、forceなしでブランチrefを更新します。`expectedHeadSHA`が現在のHEADと一致しない場合、ブランチを変更する前に`GitHubSyncError.conflict`を送出します。

## SwiftUIリポジトリ選択画面

```swift
import GitHubSyncKitUI

GitHubRepositoryPicker(
    client: api,
    selection: $selectedRepository
)
```

`/user/repos`からリポジトリを取得し、ローカル検索と書き込み可能なリポジトリの表示を行います。

## リファレンスiOSアプリ

次のXcodeプロジェクトを開きます。

```text
Examples/GitHubSyncExample/GitHubSyncExample.xcodeproj
```

実行手順：

1. `Examples/GitHubSyncExample/Config.xcconfig`の`YOUR_GITHUB_OAUTH_CLIENT_ID`を置き換えます。
2. XcodeでDevelopment Teamを設定します。
3. サンプルのBundle IDを自分のアカウント用の一意な値へ変更します。
4. GitHub OAuth Appの設定でDevice Flowを有効にします。
5. iOS 17以降の端末またはSimulatorで実行します。
6. GitHubへログインし、書き込み可能なリポジトリを選択して`notes/sample.md`をコミットします。

リポジトリに含まれるサンプルBundle ID：

```text
io.github.oqzl.GitHubSyncKitExample
```

実機で実行する前に、次のような一意な値へ変更してください。

```text
com.example.yourname.GitHubSyncKitExample
```

OAuth Callback SchemeはBundle IDとは別に設定されています。

```text
io.github.oqzl.githubsynckit.example
```

Bundle IDから自動生成しないため、署名用Bundle IDを変更してもOAuth Callbackが暗黙に変化しません。Device FlowではCallback URLを使用しません。

Web Flowで利用する場合は、次のCallback URLをGitHub OAuth Appへ登録します。

```text
io.github.oqzl.githubsynckit.example://oauth/callback
```

本番アプリでは、自分が管理する逆DNS形式のURL SchemeまたはUniversal Linkへ置き換えてください。

## エラー処理

主なエラーは`GitHubSyncError`で表現されます。

- `unauthorized`
- `forbidden`
- `notFound`
- `conflict`
- `validationFailed`
- `rateLimited`
- `api`

直近のGitHub APIレート制限ヘッダーは`lastRateLimit`から取得できます。

## APIバージョン

既定のGitHub REST APIバージョンは`2022-11-28`です。別の対応バージョンを意図的に使用するときだけ、`GitHubConfiguration.apiVersion`を変更してください。

## 制限事項

- OAuth Appの`repo`スコープは広く、1リポジトリだけには限定できません。
- Repository Search APIのレスポンスには権限情報が含まれない場合があります。リポジトリ選択画面は`/user/repos`を使用します。
- Repository Contents APIでは、ファイル操作ごとに1コミット作成されます。
- バッチコミットはGit database APIを使用し、Pull Requestは作成しません。
- バイナリファイルはGitHub APIのサイズ制限内で扱えます。
- 競合は検知しますが、自動マージは行いません。
- GitHub Enterprise Server用のBase URLは設定できますが、リファレンスアプリでは未検証です。

## GitHubSyncKitを使う理由

| 機能 | GitHubSyncKit | `URLSession`で自作 |
|---|---:|---:|
| OAuth Device Flow | 対応済み | 個別実装 |
| Web Flow連携 | 対応済み | 個別実装 |
| Keychainトークン保存 | 対応済み | 個別実装 |
| 書き込み可能なリポジトリ選択 | 対応済み | 個別実装 |
| Contents APIによるコミット | 対応済み | 個別実装 |
| 複数ファイルの原子的コミット | 対応済み | 実装が複雑 |
| SHA競合検知 | 対応済み | 個別実装 |
| SwiftUIコンポーネント | 対応済み | 個別実装 |
| Swift Concurrency | ネイティブ対応 | アプリ側設計次第 |

## テスト

```shell
swift test
```

通信処理は`GitHubHTTPTransport`で抽象化されており、アプリやテストからモック通信を注入できます。

## コントリビューション

IssueとPull Requestを歓迎します。変更を送る前に次を確認してください。

1. `swift test`を実行します。
2. 可能な範囲で公開APIを`Sendable`にします。
3. Secret、アクセストークン、ローカル設定ファイルをコミットしません。
4. APIデコード、認証、競合処理のテストを追加します。

詳細は[CONTRIBUTING.md](CONTRIBUTING.md)を参照してください。

## セキュリティ

脆弱性を公開Issueへ投稿しないでください。[SECURITY.md](SECURITY.md)を参照してください。

## ライセンス

GitHubSyncKitはMIT Licenseで提供されます。[LICENSE](LICENSE)を参照してください。
