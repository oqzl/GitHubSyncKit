#if canImport(SwiftUI)
import SwiftUI
import GitHubSyncKit

public struct GitHubRepositoryPicker: View {
    private let client: GitHubClient
    @Binding private var selection: GitHubRepository?
    @State private var repositories: [GitHubRepository] = []
    @State private var query = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    public init(client: GitHubClient, selection: Binding<GitHubRepository?>) { self.client = client; self._selection = selection }

    public var body: some View {
        List(repositories) { repository in
            Button { selection = repository } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(repository.fullName); if repository.isPrivate { Image(systemName: "lock.fill").font(.caption) }; Spacer(); if selection?.id == repository.id { Image(systemName: "checkmark") } }
                    if let description = repository.description { Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
            }.buttonStyle(.plain)
        }
        .overlay { if isLoading { ProgressView() } else if repositories.isEmpty { ContentUnavailableView("リポジトリなし", systemImage: "shippingbox", description: Text(errorMessage ?? "検索条件を変更してください")) } }
        .searchable(text: $query, prompt: "リポジトリを検索")
        .navigationTitle("同期先リポジトリ")
        .task { await load() }
        .onSubmit(of: .search) { Task { await load() } }
        .refreshable { await load() }
    }

    @MainActor private func load() async {
        isLoading = true; defer { isLoading = false }
        do {
            let all = try await client.repositories(perPage: 100, writableOnly: true)
            repositories = query.isEmpty ? all : all.filter { $0.fullName.localizedCaseInsensitiveContains(query) || ($0.description?.localizedCaseInsensitiveContains(query) == true) }
            errorMessage = nil
        } catch { repositories = []; errorMessage = error.localizedDescription }
    }
}
#endif
