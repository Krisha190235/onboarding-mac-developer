//
//  StaticHTTPClient.swift
//
//  A canned client that ships in the library rather than the test target, so
//  SwiftUI previews can use it. Previews run in a sandboxed process that may
//  have no network at all, and a preview that depends on jsonplaceholder being
//  up isn't a preview — it's a flaky screenshot.
//
//  This is also the only honest way to preview a loading spinner or an error
//  state: both are unreachable when the real API is working.
//

import Foundation

public struct StaticHTTPClient: HTTPClient {
    /// Path fragment -> response body. The longest matching key wins, so
    /// "comments" beats "posts" for /posts/1/comments regardless of the order
    /// a dictionary happens to iterate in.
    let routes: [String: String]
    let status: Int
    let delay: Duration
    let failure: URLError?

    public init(status: Int = 200, json: String, delay: Duration = .zero) {
        self.routes = ["": json]
        self.status = status
        self.delay = delay
        self.failure = nil
    }

    public init(routes: [String: String], status: Int = 200, delay: Duration = .zero) {
        self.routes = routes
        self.status = status
        self.delay = delay
        self.failure = nil
    }

    public init(failure: URLError, delay: Duration = .zero) {
        self.routes = [:]
        self.status = 0
        self.delay = delay
        self.failure = failure
    }

    public func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        if let failure {
            throw failure
        }

        let path = request.url?.path ?? ""
        let body = routes
            .filter { path.contains($0.key) }
            .max { $0.key.count < $1.key.count }?
            .value ?? "{}"

        let response = HTTPURLResponse(url: request.url!,
                                       statusCode: status,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

// MARK: - Ready-made APIs for previews

public extension PlaceholderAPI {
    /// Posts and comments, immediately — enough for the list and the detail
    /// pane in the same preview.
    static var previewLoaded: PlaceholderAPI {
        PlaceholderAPI(client: StaticHTTPClient(routes: [
            "comments": SampleJSON.comments,
            "posts": SampleJSON.posts
        ]))
    }

    /// A successful response with nothing in it — the empty state, which is a
    /// success and not an error.
    static var previewEmpty: PlaceholderAPI {
        PlaceholderAPI(client: StaticHTTPClient(json: "[]"))
    }

    /// Never finishes quickly, so the spinner is visible in a preview.
    static var previewLoading: PlaceholderAPI {
        PlaceholderAPI(client: StaticHTTPClient(json: SampleJSON.posts, delay: .seconds(30)))
    }

    /// Offline. maxAttempts 1 so the preview fails immediately instead of
    /// spending its backoff retrying a client that will never succeed.
    static var previewOffline: PlaceholderAPI {
        PlaceholderAPI(client: StaticHTTPClient(failure: URLError(.notConnectedToInternet)),
                       maxAttempts: 1)
    }

    static var previewComments: PlaceholderAPI {
        PlaceholderAPI(client: StaticHTTPClient(json: SampleJSON.comments))
    }
}

enum SampleJSON {
    static let posts = """
    [
      { "userId": 1, "id": 1,
        "title": "sunt aut facere repellat provident occaecati excepturi optio",
        "body": "quia et suscipit\\nsuscipit recusandae consequuntur expedita et cum" },
      { "userId": 1, "id": 2,
        "title": "qui est esse",
        "body": "est rerum tempore vitae\\nsequi sint nihil reprehenderit dolor beatae" },
      { "userId": 2, "id": 3,
        "title": "ea molestias quasi exercitationem repellat qui ipsa sit aut",
        "body": "et iusto sed quo iure\\nvoluptatem occaecati omnis eligendi aut ad" }
    ]
    """

    static let comments = """
    [
      { "postId": 1, "id": 1, "name": "id labore ex et quam laborum",
        "email": "Eliseo@gardner.biz",
        "body": "laudantium enim quasi est quidem magnam voluptate ipsam eos" },
      { "postId": 1, "id": 2, "name": "quo vero reiciendis velit similique earum",
        "email": "Jayne_Kuhic@sydney.com",
        "body": "est natus enim nihil est dolore omnis voluptatem numquam" }
    ]
    """
}
