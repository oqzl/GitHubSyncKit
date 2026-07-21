import XCTest
@testable import GitHubSyncKit

final class GitHubSyncKitTests: XCTestCase {
    func testDestinationResolvesDirectory() {
        let destination = GitHubSyncDestination(repositoryID: 1, owner: "o", repository: "r", branch: "main", directory: "/notes/")
        XCTAssertEqual(destination.resolvedPath("/a.md"), "notes/a.md")
    }

    func testContentDecodesBase64() throws {
        let json = #"{"type":"file","name":"a.md","path":"a.md","sha":"x","encoding":"base64","content":"aGVsbG8="}"#.data(using: .utf8)!
        let content = try JSONDecoder().decode(GitHubContent.self, from: json)
        XCTAssertEqual(String(data: content.decodedData!, encoding: .utf8), "hello")
    }

    func testCreateBranchPostsTheRefAndReturnsTheCreatedHead() async throws {
        let transport = MockTransport(
            data: #"{"ref":"refs/heads/notes/ios","object":{"sha":"created"}}"#.data(using: .utf8)!
        )
        let client = GitHubClient(tokenStore: EmptyTokenStore(), transport: transport)

        let branch = try await client.createBranch(
            owner: "octo",
            repository: "notes",
            name: "notes/ios",
            fromCommitSHA: "base"
        )

        XCTAssertEqual(branch.name, "notes/ios")
        XCTAssertEqual(branch.commit.sha, "created")
        let request = await transport.request
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.url?.path, "/repos/octo/notes/git/refs")
        let body = try XCTUnwrap(request?.httpBody)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String], [
            "ref": "refs/heads/notes/ios",
            "sha": "base"
        ])
    }

    func testPutFileOmitsOptionalFieldsWhenCreatingAFile() async throws {
        let transport = MockTransport(
            data: #"{"commit":{"sha":"commit"},"content":{"sha":"content"}}"#.data(using: .utf8)!
        )
        let client = GitHubClient(tokenStore: EmptyTokenStore(), transport: transport)

        _ = try await client.putFile(
            owner: "octo",
            repository: "notes",
            path: "notes/inbox/new.md",
            data: Data("hello".utf8),
            message: "Create note",
            branch: "main"
        )

        let request = await transport.request
        XCTAssertEqual(request?.httpMethod, "PUT")
        let body = try XCTUnwrap(request?.httpBody)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String], [
            "message": "Create note",
            "content": "aGVsbG8=",
            "branch": "main"
        ])
    }

    func testPutFileIncludesSHAWhenUpdatingAFile() async throws {
        let transport = MockTransport(
            data: #"{"commit":{"sha":"commit"},"content":{"sha":"content"}}"#.data(using: .utf8)!
        )
        let client = GitHubClient(tokenStore: EmptyTokenStore(), transport: transport)

        _ = try await client.putFile(
            owner: "octo",
            repository: "notes",
            path: "notes/inbox/existing.md",
            data: Data("hello".utf8),
            message: "Update note",
            branch: "main",
            expectedSHA: "old-sha"
        )

        let request = await transport.request
        let body = try XCTUnwrap(request?.httpBody)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String], [
            "message": "Update note",
            "content": "aGVsbG8=",
            "branch": "main",
            "sha": "old-sha"
        ])
    }
}

private actor MockTransport: GitHubHTTPTransport {
    let data: Data
    private(set) var request: URLRequest?

    init(data: Data) {
        self.data = data
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        let response = try XCTUnwrap(HTTPURLResponse(
            url: try XCTUnwrap(request.url),
            statusCode: 201,
            httpVersion: nil,
            headerFields: nil
        ))
        return (data, response)
    }
}

private struct EmptyTokenStore: GitHubTokenStore {
    func loadToken() async throws -> String? { nil }
    func saveToken(_ token: String) async throws {}
    func deleteToken() async throws {}
}
