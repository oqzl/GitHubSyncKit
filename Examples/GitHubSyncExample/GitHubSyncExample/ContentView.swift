import SwiftUI
import GitHubSyncKit
import GitHubSyncKitUI

struct ContentView: View {
    @State private var tokenStore: KeychainTokenStore?
    @State private var client: GitHubClient?
    @State private var user: GitHubUser?
    @State private var selectedRepository: GitHubRepository?
    @State private var branch = "main"
    @State private var directory = "notes"
    @State private var status = "未接続"
    @State private var deviceCode: GitHubDeviceCode?
    @State private var showingRepositories = false

    var body: some View {
        NavigationStack {
            Form {
                Section("GitHub") {
                    Text(user.map { "@\($0.login)" } ?? "未接続")
                    Button("Device Flowで接続") { Task { await signIn() } }.disabled(AppConfig.clientID.isEmpty)
                    if AppConfig.clientID.isEmpty { Text("GitHubClientIDを設定してください").foregroundStyle(.red) }
                    if let code = deviceCode {
                        Text("コード: \(code.userCode)").font(.title3.monospaced()).textSelection(.enabled)
                        Link("GitHubで認証", destination: code.verificationURI)
                    }
                }
                Section("同期先") {
                    Button(selectedRepository?.fullName ?? "リポジトリを選択") { showingRepositories = true }.disabled(client == nil)
                    TextField("ブランチ", text: $branch)
                    TextField("ディレクトリ", text: $directory)
                }
                Section("動作確認") {
                    Button("README相当をコミット") { Task { await commitSample() } }.disabled(selectedRepository == nil)
                    Text(status).font(.caption).textSelection(.enabled)
                }
            }
            .navigationTitle("GitHubSyncKit")
            .sheet(isPresented: $showingRepositories) {
                NavigationStack {
                    if let client { GitHubRepositoryPicker(client: client, selection: $selectedRepository) }
                }
            }
            .task { await restore() }
        }
    }

    @MainActor private func restore() async {
        let store = KeychainTokenStore(service: Bundle.main.bundleIdentifier ?? "GitHubSyncExample")
        tokenStore = store
        guard (try? await store.loadToken()) != nil else { return }
        let api = GitHubClient(tokenStore: store); client = api
        user = try? await api.currentUser()
    }

    @MainActor private func signIn() async {
        guard !AppConfig.clientID.isEmpty else { return }
        do {
            let oauth = GitHubOAuthConfiguration(clientID: AppConfig.clientID, callbackURL: AppConfig.callbackURL)
            let flow = GitHubDeviceFlow(oauth: oauth)
            let code = try await flow.requestCode(); deviceCode = code
            status = "ブラウザでコードを入力してください"
            let token = try await flow.pollToken(deviceCode: code)
            let store = tokenStore ?? KeychainTokenStore(service: Bundle.main.bundleIdentifier ?? "GitHubSyncExample")
            try await store.saveToken(token)
            let api = GitHubClient(tokenStore: store); client = api
            user = try await api.currentUser(); deviceCode = nil; status = "接続しました"
        } catch { status = error.localizedDescription }
    }

    @MainActor private func commitSample() async {
        guard let repository = selectedRepository, let client else { return }
        do {
            let destination = GitHubSyncDestination(repositoryID: repository.id, owner: repository.owner.login, repository: repository.name, branch: branch, directory: directory)
            let sync = GitHubSyncClient(api: client, destination: destination)
            let text = "# GitHubSyncKit Sample\n\nUpdated at \(Date().formatted(.iso8601))\n"
            let result = try await sync.commitFile(path: "sample.md", data: Data(text.utf8), message: "Update GitHubSyncKit sample")
            status = "Committed: \(result.commitSHA)"
        } catch { status = error.localizedDescription }
    }
}
