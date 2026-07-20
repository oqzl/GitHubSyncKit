# GitHubSyncKit — GitHub API, OAuth, Repository Sync, and Git Commits for Swift

[日本語版 README](README.ja.md)

GitHubSyncKit is a Swift GitHub SDK for iOS and macOS. It connects Swift apps to the GitHub REST API and provides GitHub OAuth authentication, writable repository selection, file synchronization, single-file commits, atomic multi-file commits, conflict detection, Keychain token storage, and a SwiftUI repository picker.

Use GitHubSyncKit to build a Markdown note app backed by GitHub, a repository-based document editor, a configuration sync tool, a static-site content editor, or any iOS and macOS app that reads files from GitHub and commits changes back to a repository.

## Highlights

- Swift Package Manager support
- Swift 6 concurrency and `async/await`
- GitHub OAuth Device Flow without embedding a client secret
- GitHub OAuth Web Flow authorization with `ASWebAuthenticationSession` and PKCE
- Backend token-exchange abstraction for secure Web Flow deployments
- Keychain token storage
- Current GitHub user lookup
- Writable repository listing, search, and selection
- Branch listing
- GitHub Repository Contents API
- Create, update, and delete files through Git commits
- Atomic multi-file commits using Git blobs, trees, commits, and refs
- SHA-based optimistic concurrency and conflict detection
- Reusable SwiftUI repository picker
- Reference iOS app and Cloudflare Worker example
- No third-party runtime dependencies

## Quick start

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

Authentication must be completed before creating the API client. See [OAuth authentication](#oauth-authentication).

## Use cases

GitHubSyncKit is designed for applications such as:

- Markdown note apps backed by a GitHub repository
- GitHub-connected document editors
- Repository-based backup and synchronization features
- Static-site and documentation content editors
- Configuration file managers
- Apps that generate and commit files to GitHub
- Lightweight GitHub clients for iOS and macOS

## Requirements

- Swift 6.0 or later
- iOS 17 or later
- macOS 14 or later
- A GitHub OAuth App

## Installation

Add GitHubSyncKit through Xcode's Package Dependencies UI:

```text
https://github.com/oqzl/GitHubSyncKit.git
```

Or add it to `Package.swift`:

```swift
dependencies: [
    .package(
        url: "https://github.com/oqzl/GitHubSyncKit.git",
        from: "0.1.0"
    )
]
```

Add the core SDK or the optional SwiftUI components:

```swift
.product(name: "GitHubSyncKit", package: "GitHubSyncKit")
.product(name: "GitHubSyncKitUI", package: "GitHubSyncKit")
```

## OAuth authentication

GitHubSyncKit supports two OAuth App configurations.

| Flow | Backend required | Client secret in app | Recommended for |
|---|---:|---:|---|
| Device Flow | No | No | Samples, developer tools, apps where device-code UX is acceptable |
| Web Flow | Yes | No | Consumer-facing iOS and macOS apps |

GitHub's OAuth App Web Flow requires the OAuth client secret when exchanging an authorization code for an access token. PKCE does not remove that GitHub requirement. Never embed a GitHub OAuth client secret in an iOS or macOS application.

### Create a GitHub OAuth App

1. Open GitHub Settings.
2. Open Developer settings.
3. Open OAuth Apps and select New OAuth App.
4. Enter an application name and homepage URL.
5. Enable Device Flow when using the reference app.
6. Copy the Client ID into the app configuration.
7. For Web Flow, register the callback URL used by your app and backend.

### Device Flow

Device Flow runs directly in the application and requires only the OAuth Client ID.

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

// Display code.userCode and open code.verificationURI.
let token = try await flow.pollToken(deviceCode: code)

let tokenStore = KeychainTokenStore(service: "com.example.myapp")
try await tokenStore.saveToken(token)
```

### Web Flow with `ASWebAuthenticationSession`

The SDK obtains an authorization code using `ASWebAuthenticationSession` and PKCE. Your backend then exchanges the temporary code while securely storing the GitHub OAuth Client Secret.

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

Expected backend request:

```json
{
  "code": "temporary-code",
  "redirectURI": "myapp://github/oauth",
  "codeVerifier": "pkce-code-verifier"
}
```

Expected backend response:

```json
{
  "accessToken": "gho_..."
}
```

The backend must validate requests, avoid logging codes and tokens, and append its GitHub OAuth Client Secret when calling GitHub's token endpoint.

A minimal Cloudflare Worker implementation is included in `Examples/TokenExchangeWorker`.

## Create a GitHub API client

```swift
let api = GitHubClient(tokenStore: tokenStore)
let user = try await api.currentUser()
let repositories = try await api.repositories(writableOnly: true)
```

`writableOnly` filters using permissions returned by GitHub. Always handle a later `403 Forbidden` response because repository permissions can change.

## Search and select a repository

```swift
let repositories = try await api.repositories(writableOnly: true)

let matches = repositories.filter {
    $0.fullName.localizedCaseInsensitiveContains("notes")
}
```

Configure one repository, branch, and optional directory as the sync destination:

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

OAuth App scopes cannot technically restrict the access token to one selected repository. GitHubSyncKit restricts its own operations to the configured destination, but the token retains all scopes granted by GitHub. Use a GitHub App or fine-grained personal access token when repository-level token enforcement is required.

## Read a file from GitHub

```swift
let remote = try await sync.getFile(path: "example.md")
let data = remote.decodedData
```

## Create or update a file and commit it

```swift
let result = try await sync.commitFile(
    path: "example.md",
    data: Data("# Example".utf8),
    message: "Update example note",
    expectedSHA: remote.sha
)
```

Pass the previously fetched blob SHA when updating. GitHub rejects a stale SHA, allowing the caller to detect concurrent remote changes.

## Delete a file and commit the deletion

```swift
let result = try await sync.deleteFile(
    path: "obsolete.md",
    message: "Remove obsolete note",
    expectedSHA: remote.sha
)
```

## Commit multiple files atomically

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

Batch commits create Git blobs and a tree, create one Git commit, and update the branch ref without forcing. If `expectedHeadSHA` no longer matches, the SDK throws `GitHubSyncError.conflict` before changing the branch.

## SwiftUI repository picker

```swift
import GitHubSyncKitUI

GitHubRepositoryPicker(
    client: api,
    selection: $selectedRepository
)
```

The picker loads repositories from `/user/repos`, filters them locally, and displays writable repositories.

## Reference iOS app

Open:

```text
Examples/GitHubSyncExample/GitHubSyncExample.xcodeproj
```

Then:

1. Replace `YOUR_GITHUB_OAUTH_CLIENT_ID` in `Examples/GitHubSyncExample/Config.xcconfig`.
2. Select your Development Team in Xcode.
3. Change the sample Bundle ID to a unique value for your account.
4. Enable Device Flow in the GitHub OAuth App settings.
5. Run the app on iOS 17 or later.
6. Sign in, select a writable repository, and commit `notes/sample.md`.

The checked-in sample Bundle ID is:

```text
io.github.oqzl.GitHubSyncKitExample
```

Before running on a physical device, change it to a unique identifier such as:

```text
com.example.yourname.GitHubSyncKitExample
```

The OAuth callback scheme is configured separately:

```text
io.github.oqzl.githubsynckit.example
```

It is intentionally not derived from the Bundle ID. Developers can therefore change signing identifiers without silently changing OAuth callback behavior. Device Flow does not use the callback URL.

For Web Flow, register:

```text
io.github.oqzl.githubsynckit.example://oauth/callback
```

For a production app, replace this with a reverse-DNS scheme or universal link that you control.

## Error handling

Common errors are represented by `GitHubSyncError`:

- `unauthorized`
- `forbidden`
- `notFound`
- `conflict`
- `validationFailed`
- `rateLimited`
- `api`

The client exposes the most recently observed GitHub API rate-limit headers through `lastRateLimit`.

## API version

The default GitHub REST API version is `2022-11-28`. Override `GitHubConfiguration.apiVersion` only when intentionally targeting another supported version.

## Scope and limitations

- OAuth App `repo` scope is broad and cannot be restricted to one repository.
- Repository search responses may omit permission details; the picker uses `/user/repos` for writable selection.
- The Repository Contents API creates one commit per file operation.
- Batch commits use Git database endpoints and do not create pull requests.
- Binary files are supported subject to GitHub API size limits.
- The package detects conflicts but does not automatically merge content.
- GitHub Enterprise Server base URLs are configurable but have not been validated by the reference app.

## Why GitHubSyncKit?

| Capability | GitHubSyncKit | Raw `URLSession` implementation |
|---|---:|---:|
| OAuth Device Flow | Included | Manual |
| Web Flow integration | Included | Manual |
| Keychain token storage | Included | Manual |
| Writable repository picker | Included | Manual |
| Contents API commits | Included | Manual |
| Atomic multi-file commits | Included | Complex |
| SHA conflict detection | Included | Manual |
| SwiftUI components | Included | Manual |
| Swift concurrency | Native | Application-defined |

## Testing

```shell
swift test
```

Network behavior is abstracted by `GitHubHTTPTransport`, allowing applications and tests to inject a mock transport.

## Contributing

Issues and pull requests are welcome. Before submitting a change:

1. Run `swift test`.
2. Keep public APIs `Sendable` where practical.
3. Never commit secrets, access tokens, or local configuration files.
4. Add tests for API decoding, authentication, and conflict behavior.

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Security

Do not report security vulnerabilities through public issues. See [SECURITY.md](SECURITY.md).

## License

GitHubSyncKit is available under the MIT License. See [LICENSE](LICENSE).
