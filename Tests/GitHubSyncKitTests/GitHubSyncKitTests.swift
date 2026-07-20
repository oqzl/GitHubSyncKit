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
}
