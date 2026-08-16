//
//  PlaceholderAPI.swift
//
//  A client for jsonplaceholder.typicode.com. Nothing in here knows what it's
//  talking to: baseURL and HTTPClient are both injected, which is why the same
//  type is used against the live API, against a stub, and against a
//  mocky.io URL without a line changing.
//

import Foundation

public struct PlaceholderAPI: Sendable {
    /// The public fake API used by demos-1..100 posts, 500 comments, and it
    /// accepts writes without persisting them.
    public static let jsonplaceholder = URL(string: "https://jsonplaceholder.typicode.com")!

    private let baseURL: URL
    private let client: any HTTPClient
    private let maxAttempts: Int
    private let timeout: TimeInterval
    /// Multiplies the retry backoff. Tests pass a tiny value so a retry case
    /// costs milliseconds; a suite that really sleeps for 3s stops being run.
    private let backoffScale: Double

    public init(baseURL: URL = PlaceholderAPI.jsonplaceholder,
                client: any HTTPClient = URLSession.shared,
                maxAttempts: Int = 3,
                timeout: TimeInterval = 15,
                backoffScale: Double = 1.0) {
        self.baseURL = baseURL
        self.client = client
        self.maxAttempts = maxAttempts
        self.timeout = timeout
        self.backoffScale = backoffScale
    }

    // MARK: - The calls

    public func posts(userID: Int? = nil) async throws -> [Post] {
        try await send(.posts(userID: userID))
    }

    public func post(id: Int) async throws -> Post {
        try await send(.post(id: id))
    }

    public func comments(postID: Int) async throws -> [Comment] {
        try await send(.comments(postID: postID))
    }

    public func create(_ post: NewPost) async throws -> Post {
        try await send(.create(post))
    }

    public func deletePost(id: Int) async throws {
        try await send(.deletePost(id: id))
    }

    // MARK: - The one method that talks to the network

    public func send<Response>(_ endpoint: Endpoint<Response>) async throws -> Response {
        let request = try makeRequest(for: endpoint)

        var attempt = 1
        while true {
            do {
                return try await attemptOnce(request, endpoint: endpoint)
            } catch {
                let mapped = APIError.map(error)
                guard mapped.isRetryable, attempt < maxAttempts else { throw mapped }

                let backoff = (pow(2.0, Double(attempt - 1)) + Double.random(in: 0...0.3)) * backoffScale
                try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                attempt += 1
            }
        }
    }

    private func makeRequest<Response>(for endpoint: Endpoint<Response>) throws -> URLRequest {
        let url = baseURL.appendingPathComponent(endpoint.path)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL(endpoint.path)
        }
        if !endpoint.query.isEmpty {
            // Sorted, so the URL is stable and a test can assert on it.
            components.queryItems = endpoint.query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let finalURL = components.url else {
            throw APIError.invalidURL(endpoint.path)
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if endpoint.body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if !endpoint.method.isIdempotent {
            // Built once, outside the retry loop, so every attempt carries the
            // same key and the server can collapse duplicates (9.4).
            request.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")
        }
        return request
    }

    private func attemptOnce<Response>(_ request: URLRequest,
                                       endpoint: Endpoint<Response>) async throws -> Response {
        let (data, response) = try await client.perform(request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown(URLError(.badServerResponse))
        }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode,
                                body: String(data: data, encoding: .utf8) ?? "")
        }

        do {
            return try endpoint.decode(data)
        } catch let error as DecodingError {
            throw APIError.malformedResponse(error)
        }
    }
}
