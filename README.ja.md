# GitHubSyncKit — Swift向けGitHub API・OAuth・リポジトリ同期SDK

[English README](README.md)

GitHubSyncKitは、iOS／macOSアプリからGitHub REST APIを利用するためのSwift製SDKです。GitHub OAuth認証、書き込み可能なリポジトリの選択、ファイルの読み書き、単一ファイルのコミット、複数ファイルの原子的コミット、SHAによる競合検知、Keychainへのトークン保存、SwiftUI製リポジトリ選択UIを提供します。

GitHubを保存先にするMarkdownエディタ、ノートアプリ、設定同期ツール、静的サイト用コンテンツエディタ、バックアップ機能などに利用できます。

## 主な機能

- Swift Package Manager対応
- Swift 6 Concurrencyと`async/await`対応
- Client Secretを埋め込まないOAuth Device Flow
- `ASWebAuthenticationSession`とPKCEを使うOAuth Web Flow
- Web Flow用バックエンドトークン交換
- Keychainへのアクセストークン保存
- 書き込み可能なリポジトリとブランチの選択
- Repository Contents API対応
- Git blob、tree、commit、refによる複数ファイルの単一コミット
- ファイルSHAとブランチHEADによる競合検知
- SwiftUIリポジトリ選択画面
- リファレンスiOSアプリとCloudflare Worker例
- 実行時の外部ライブラリ依存なし

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

Core SDKと、必要に応じてSwiftUIターゲットを追加します。

```swift
.product(name: "GitHubSyncKit", package: "GitHubSyncKit")
.product(name: "GitHubSyncKitUI", package: "GitHubSyncKit")
```

## クイックスタート

先にOAuth認証を完了させます。次の例は、書き込み可能なリポジトリを選択し、新規ファイルを作成します。

```swift
import GitHubSyncKit

let tokenStore = KeychainTokenStore(service: "com.example.myapp")
let api = GitHubClient(tokenStore: tokenStore)

let repository = try await api.repositories(writableOnly: true)[0]
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

`expectedSHA: nil`は、対象ファイルが存在しないことを前提に新規作成するときに使用します。強制上書き指定ではありません。

## OAuth認証

GitHubSyncKitは、GitHub OAuth Appの2種類の認証方式に対応します。

| 認証方式 | バックエンド | Client Secretのアプリ内保持 | 主な用途 |
|---|---:|---:|---|
| Device Flow | 不要 | 不要 | サンプル、開発者向けツール、サーバーを持たない個人開発 |
| Web Flow | 必要 | 不要 | 一般利用者向けiOS／macOSアプリ |

### Client Secretの扱い

GitHub OAuth AppのWeb Flowでは、認可コードをアクセストークンへ交換するときにOAuth Client Secretが必要です。iOS／macOSアプリのバイナリへ埋め込まないでください。PKCEは認可コードを保護しますが、アプリ内に埋め込んだClient Secretを秘密にはできません。

バックエンドを用意しない場合はDevice Flowを使用します。Web Flowでは、Client Secretを保持してトークン交換を実行するバックエンドが必要です。

### Device Flow

```swift
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

Device FlowではCallback URLを使用しません。現在の設定型には共通項目として含まれています。

### Web Flow

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

最小構成のCloudflare Worker例を`Examples/TokenExchangeWorker`に収録しています。

### トークンの保存

OAuthトークンは広いリポジトリアクセス権を持つ場合があります。`KeychainTokenStore`へ保存し、`UserDefaults`、plist、ソースコード、ログ、クラッシュ情報、分析イベントへ保存しないでください。

サインアウト時にはローカルトークンを削除します。リモート側での失効も必要なアプリでは、GitHubの失効処理も実装してください。

## リポジトリの検索と同期先設定

```swift
let repositories = try await api.repositories(writableOnly: true)

let matches = repositories.filter {
    $0.fullName.localizedCaseInsensitiveContains("notes")
}
```

同期先のリポジトリ、ブランチ、任意のディレクトリを設定します。

```swift
let destination = GitHubSyncDestination(
    repositoryID: repository.id,
    owner: repository.owner.login,
    repository: repository.name,
    branch: repository.defaultBranch,
    directory: "notes"
)
```

OAuth Appのスコープでは、トークン権限を選択した1リポジトリだけに制限できません。GitHubSyncKitはSDK自身の操作対象を設定済み同期先に限定しますが、トークン自体は許可されたスコープを保持します。トークンレベルで限定する場合は、GitHub AppまたはFine-grained Personal Access Tokenを使用してください。

## ファイルの読み取り・作成・更新・削除

更新前にリモートファイルを取得します。

```swift
let remote = try await sync.getFile(path: "example.md")
let data = remote.decodedData
```

取得したSHAを指定して更新します。

```swift
let result = try await sync.commitFile(
    path: "example.md",
    data: Data("# Updated".utf8),
    message: "Update example note",
    expectedSHA: remote.sha
)
```

現在のSHAを指定して削除します。

```swift
let result = try await sync.deleteFile(
    path: "obsolete.md",
    message: "Remove obsolete note",
    expectedSHA: remote.sha
)
```

### `expectedSHA`の重要な意味

- `expectedSHA: nil`は「存在しない想定のファイルを新規作成する」という意味です。
- 既存ファイルの更新には現在のblob SHAが必要です。
- SHAを省略しても、既存ファイルが警告なしに強制上書きされることはありません。GitHubがリクエストを拒否します。
- SHAが古い場合、前回取得後にリモートが変更された競合として扱います。
- 競合を無条件上書きとして自動再試行しないでください。

## 複数ファイルを1コミットで更新する

Contents APIを連続して呼ぶと、ファイルごとにコミットが作成されます。1回の同期操作で複数ファイルを変更する場合は`commitBatch`を使用します。

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

SDKはblobとtreeを作成し、1つのcommitを作成して、forceなしでブランチrefを更新します。ブランチHEADが変わっている場合は、refを動かす前に`GitHubSyncError.conflict`を送出します。

## 本番同期を設計するときの注意点

GitHubSyncKitが提供するのはGitHub操作です。ローカル永続化、同期タイミング、再試行方針、競合解決UIはアプリ側の責務です。

### ローカルファーストで保存する

ネットワーク同期を試す前に、編集内容をローカルDBへ保存してください。SwiftData、SQLite、Core Dataなどを利用できます。通信失敗でユーザーの編集内容を失ってはいけません。

実装例：

1. 編集内容をローカルへ保存する。
2. 未同期操作をキューへ追加する。
3. GitHub同期を試行する。
4. 成功した場合だけ未同期操作を削除する。
5. 競合や認証エラーは明示的な解決対象として残す。

オフライン同期キューは[#2](https://github.com/oqzl/GitHubSyncKit/issues/2)で管理しています。

### 競合解決UIを用意する

SDKは競合を検知しますが、ファイル内容を自動マージしません。アプリのデータモデルに応じて、次のような選択肢を提示してください。

- 確認後にローカル内容で明示的に置き換える
- リモート内容を採用する
- ローカル内容を別パスへ保存する
- アプリ固有の3-way mergeを実行する

リファレンス競合UIは[#1](https://github.com/oqzl/GitHubSyncKit/issues/1)で管理しています。

### タイピングごとに同期しない

同期トリガーは次のように限定してください。

- 明示的な保存
- 編集画面を閉じた時点
- 編集停止後のデバウンス
- 手動同期ボタン
- OSが許可した場合のまとめたバックグラウンド再試行

関連する変更は可能な範囲で`commitBatch`へまとめます。API呼び出し回数を減らし、コミット履歴のノイズも抑えられます。

同期スケジューリングとレート制限対応は[#3](https://github.com/oqzl/GitHubSyncKit/issues/3)で管理しています。

### レート制限を実行時状態として扱う

直近のレート制限ヘッダーは`lastRateLimit`から取得できます。すべてのエンドポイントや認証方式に対して固定の呼び出し回数をハードコードせず、レスポンスヘッダーを正としてください。

アプリ側では次を実装します。

- 残量が少ない場合は不要な通信を停止する
- Reset情報とRetry指示に従う
- 再試行可能な失敗には上限付き指数バックオフとjitterを使う
- 認証、入力検証、競合エラーを自動再試行しない
- Primary rate limitとSecondary rate limitを分けて扱う

### アップロード前にファイルサイズを検証する

GitHubの制限はエンドポイントや操作によって異なります。大きな画像やバイナリは、Base64展開やリクエスト構築後に失敗する場合があります。テキスト中心の同期を基本とし、画像は圧縮し、送信前にペイロードサイズを検証してください。

大容量アセットには、Repository Contents APIを汎用オブジェクトストレージとして使わず、Git LFSや外部ストレージを検討してください。

事前サイズ検証は[#4](https://github.com/oqzl/GitHubSyncKit/issues/4)で管理しています。

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
3. サンプルのBundle IDを一意な値へ変更します。
4. GitHub OAuth AppでDevice Flowを有効にします。
5. iOS 17以降で実行します。
6. GitHubへログインし、リポジトリを選択して`notes/sample.md`をコミットします。

サンプルBundle ID：

```text
io.github.oqzl.GitHubSyncKitExample
```

OAuth Callback Scheme：

```text
io.github.oqzl.githubsynckit.example
```

Web Flowで登録するCallback URL：

```text
io.github.oqzl.githubsynckit.example://oauth/callback
```

Callback SchemeはBundle IDから独立しています。本番アプリでは、両方を自分が管理する識別子へ置き換えてください。

## エラー処理

主なエラーは`GitHubSyncError`で表現されます。

- `unauthorized`
- `forbidden`
- `notFound`
- `conflict`
- `validationFailed`
- `rateLimited`
- `api`

再試行前にエラーを分類してください。ネットワークエラーや一部サーバーエラーは再試行可能ですが、認証、入力検証、競合エラーは通常、ユーザー操作または新しい状態が必要です。

## 制限事項

- OAuth Appの`repo`スコープは広く、1リポジトリだけには限定できません。
- 競合は検知しますが、自動マージは行いません。
- Core SDKは永続的なオフライン同期キューを提供しません。
- iOSのバックグラウンド実行は制約され、任意の時刻に保証できません。
- Contents APIではファイル操作ごとに1コミット作成されます。
- バッチコミットはPull Requestを作成しません。
- ファイルとペイロードの制限は使用するGitHub APIによって異なります。
- GitHub Enterprise Server用Base URLは設定できますが、リファレンスアプリでは未検証です。

## ロードマップ

- [#1 競合解決UIとマージポリシー](https://github.com/oqzl/GitHubSyncKit/issues/1)
- [#2 オフラインファースト同期キュー](https://github.com/oqzl/GitHubSyncKit/issues/2)
- [#3 同期スケジューリングとレート制限対応](https://github.com/oqzl/GitHubSyncKit/issues/3)
- [#4 ファイルサイズ事前検証と大容量ファイル指針](https://github.com/oqzl/GitHubSyncKit/issues/4)

## テスト

```shell
swift test
```

通信処理は`GitHubHTTPTransport`で抽象化され、モック通信を注入できます。

## コントリビューション

IssueとPull Requestを歓迎します。`swift test`を実行し、認証情報をコミットせず、挙動変更にはテストを追加してください。詳細は[CONTRIBUTING.md](CONTRIBUTING.md)を参照してください。

## セキュリティ

脆弱性を公開Issueへ投稿しないでください。[SECURITY.md](SECURITY.md)を参照してください。

## ライセンス

GitHubSyncKitはMIT Licenseで提供されます。[LICENSE](LICENSE)を参照してください。
