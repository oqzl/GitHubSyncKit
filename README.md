# GitHubSyncKit — GitHub API, OAuth, Repository Sync, and Git Commits for Swift

[日本語版 README](README.ja.md)

GitHubSyncKit is a Swift GitHub SDK for iOS and macOS. It provides GitHub OAuth authentication, writable repository selection, file reads and writes, single-file commits, atomic multi-file commits, SHA-based conflict detection, Keychain token storage, and a reusable SwiftUI repository picker.

Use it to build GitHub-backed Markdown editors, note apps, configuration tools, static-site editors, backup features, and other applications that synchronize local data through Git commits.

## Highlights

- Swift Package Manager support
- Swift 6 concurrency and `async/await`
- OAuth Device Flow without embedding a client secret
- OAuth Web Flow with `ASWebAuthenticationSession` and PKCE
- Backend token-exchange abstraction for Web Flow
- Keychain token storage
- Writable repository and branch selection
- Repository Contents API support
- Atomic multi-file commits through Git blobs, trees, commits, and refs
- File-SHA and branch-HEAD conflict detection
- SwiftUI repository picker
- Reference iOS app and Cloudflare Worker example
- No third-party runtime dependencies

## Requirements

- Swift 6.0 or later
- iOS 17 or later
- macOS 14 or later
- A GitHub OAuth App

## Installation

Add the package URL in Xcode:

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

Add the core SDK and, optionally, the SwiftUI target:

```swift
.product(name: "GitHubSyncKit", package: "GitHubSyncKit")
.product(name: "GitHubSyncKitUI", package: "GitHubSyncKit")
```

## Quick start

Authentication must be completed first. The following example selects a writable repository and creates a new file:

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

`expectedSHA: nil` is appropriate when creating a file that is known not to exist. It is not an overwrite flag.

## OAuth authentication

GitHubSyncKit supports two OAuth App configurations.

| Flow | Backend required | Client secret in app | Recommended for |
|---|---:|---:|---|
| Device Flow | No | No | Samples, developer tools, and serverless personal projects |
| Web Flow | Yes | No | Consumer-facing iOS and macOS applications |

### Client-secret rule

GitHub OAuth App Web Flow requires the OAuth client secret during authorization-code exchange. Never embed that secret in an iOS or macOS binary. PKCE protects the authorization code, but it does not make an embedded client secret confidential.

Use Device Flow when a backend is not available. Use Web Flow only with a backend that stores the secret and performs token exchange.

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

// Display code.userCode and open code.verificationURI.
let token = try await flow.pollToken(deviceCode: code)

let tokenStore = KeychainTokenStore(service: "com.example.myapp")
try await tokenStore.saveToken(token)
```

Device Flow does not use the callback URL, although the configuration type currently contains it.

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

A minimal Cloudflare Worker example is included in `Examples/TokenExchangeWorker`.

### Token storage

An OAuth token may grant broad repository access. Store it in `KeychainTokenStore`; do not store it in `UserDefaults`, a plist, source code, logs, crash metadata, or analytics events.

Signing out should delete the local token. Applications that need remote revocation should also implement the appropriate GitHub revocation flow.

## Repository selection

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
```

OAuth App scopes cannot technically restrict a token to the selected repository. GitHubSyncKit limits its own operations to the configured destination, but the token retains all granted scopes. Use a GitHub App or fine-grained personal access token when repository-level token enforcement is required.

## Read, create, update, and delete files

Read the remote file before updating it:

```swift
let remote = try await sync.getFile(path: "example.md")
let data = remote.decodedData
```

Update using the SHA returned by that read:

```swift
let result = try await sync.commitFile(
    path: "example.md",
    data: Data("# Updated".utf8),
    message: "Update example note",
    expectedSHA: remote.sha
)
```

Delete using the current SHA:

```swift
let result = try await sync.deleteFile(
    path: "obsolete.md",
    message: "Remove obsolete note",
    expectedSHA: remote.sha
)
```

### Important SHA semantics

- `expectedSHA: nil` means “create a file expected not to exist.”
- Updating an existing file requires its current blob SHA.
- A missing SHA does not silently force-overwrite an existing file; GitHub rejects the request.
- A stale SHA indicates that the remote file changed after the last read and must be treated as a conflict.
- Do not automatically retry a conflict as an unconditional overwrite.

## Atomic multi-file commits

Calling the Contents API repeatedly creates one commit per file. Use `commitBatch` when a logical synchronization operation modifies multiple files:

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

The SDK creates blobs and one tree, creates one commit, and updates the branch ref without forcing. If the branch HEAD changed, the SDK throws `GitHubSyncError.conflict` before moving the ref.

## Production synchronization guidance

GitHubSyncKit provides GitHub operations. Local persistence, scheduling, retry policy, and conflict UX remain application-level responsibilities.

### Use a local-first data model

Save edits to a local database before attempting network synchronization. SwiftData, SQLite, Core Data, or another durable store can be used. A network failure must not discard the user's edit.

A practical flow is:

1. Save the edit locally.
2. Add a pending synchronization operation.
3. Attempt GitHub synchronization.
4. Remove the pending operation only after success.
5. Keep conflict and authentication failures for explicit resolution.

Offline queue work is tracked in [#2](https://github.com/oqzl/GitHubSyncKit/issues/2).

### Design an explicit conflict UI

The SDK detects conflicts but does not merge file contents automatically. Applications should offer choices appropriate to their data model, such as:

- keep the local version and perform an explicit replacement after confirmation
- keep the remote version
- save the local version under another path
- run an application-specific three-way merge

The reference conflict UI is tracked in [#1](https://github.com/oqzl/GitHubSyncKit/issues/1).

### Do not synchronize on every keystroke

Prefer one or more of these triggers:

- explicit save
- leaving the editor
- a debounced idle interval
- a manual sync button
- a coalesced background retry when the operating system permits it

Coalesce related changes into one `commitBatch` where possible. This reduces request volume and avoids noisy history.

Rate-limit and scheduling helpers are tracked in [#3](https://github.com/oqzl/GitHubSyncKit/issues/3).

### Handle rate limits as runtime state

The client exposes the latest observed rate-limit headers through `lastRateLimit`. Treat the response headers as authoritative rather than hard-coding one request quota for every endpoint and authentication mode.

Applications should:

- stop nonessential requests when remaining quota is low
- respect reset information and retry guidance
- use bounded exponential backoff with jitter for retryable failures
- avoid automatically retrying authentication, validation, and conflict errors
- handle secondary-rate-limit responses separately from the primary hourly quota

### Validate file sizes before upload

GitHub limits vary by endpoint and operation. Large images and binary files can fail after Base64 expansion or request construction. Prefer text-first synchronization, compress images, and validate payload size before sending.

For large assets, evaluate Git LFS or external object storage instead of treating the Repository Contents API as a general-purpose blob store.

Preflight validation is tracked in [#4](https://github.com/oqzl/GitHubSyncKit/issues/4).

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
2. Select your Development Team.
3. Change the sample Bundle ID to a unique value.
4. Enable Device Flow in the GitHub OAuth App settings.
5. Run on iOS 17 or later.
6. Sign in, select a writable repository, and commit `notes/sample.md`.

Checked-in sample Bundle ID:

```text
io.github.oqzl.GitHubSyncKitExample
```

OAuth callback scheme:

```text
io.github.oqzl.githubsynckit.example
```

For Web Flow, register:

```text
io.github.oqzl.githubsynckit.example://oauth/callback
```

The callback scheme is intentionally independent of the Bundle ID. Replace both with identifiers you control in a production application.

## Error handling

Common errors are represented by `GitHubSyncError`:

- `unauthorized`
- `forbidden`
- `notFound`
- `conflict`
- `validationFailed`
- `rateLimited`
- `api`

Classify failures before retrying. Network and some server failures may be retryable. Authentication, validation, and conflict failures normally require user action or new state.

## Scope and limitations

- OAuth App `repo` scope is broad and cannot be restricted to one repository.
- The package detects conflicts but does not automatically merge content.
- The core SDK does not provide a durable offline queue.
- Background execution is constrained by iOS and cannot be guaranteed on demand.
- Contents API operations create one commit per file operation.
- Batch commits do not create pull requests.
- File and payload limits depend on the selected GitHub endpoint.
- GitHub Enterprise Server base URLs are configurable but have not been validated by the reference app.

## Roadmap

- [#1 Conflict-resolution sample UI and merge policy hooks](https://github.com/oqzl/GitHubSyncKit/issues/1)
- [#2 Offline-first sync queue reference implementation](https://github.com/oqzl/GitHubSyncKit/issues/2)
- [#3 Sync scheduling and rate-limit-aware helpers](https://github.com/oqzl/GitHubSyncKit/issues/3)
- [#4 File-size validation and large-file guidance](https://github.com/oqzl/GitHubSyncKit/issues/4)

## Testing

```shell
swift test
```

Network behavior is abstracted by `GitHubHTTPTransport`, allowing applications and tests to inject a mock transport.

## Contributing

Issues and pull requests are welcome. Run `swift test`, avoid committing credentials, and add tests for behavioral changes. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Security

Do not report vulnerabilities through public issues. See [SECURITY.md](SECURITY.md).

## License

GitHubSyncKit is available under the MIT License. See [LICENSE](LICENSE).
