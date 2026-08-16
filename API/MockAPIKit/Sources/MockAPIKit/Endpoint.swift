//
//  Endpoint.swift
//
//  The generic endpoint from 9.6, trimmed. The generic parameter carries the
//  response type, so the call site never passes a `.self` and never casts.
//

import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"

    var isIdempotent: Bool { self != .post }
}

public struct Endpoint<Response>: Sendable {
    public var method: HTTPMethod = .get
    public var path: String
    public var query: [String: String] = [:]
    public var body: Data?
    /// Stored closure rather than a `Response: Decodable` constraint, so an
    /// endpoint can return Void for a 204 without a second send() overload.
    public var decode: @Sendable (Data) throws -> Response
}

public extension Endpoint where Response: Decodable {
    static func get(_ path: String, query: [String: String] = [:]) -> Endpoint {
        Endpoint(method: .get, path: path, query: query, body: nil) { data in
            try JSONDecoder().decode(Response.self, from: data)
        }
    }

    static func post(_ path: String, body: some Encodable) throws -> Endpoint {
        Endpoint(method: .post, path: path, body: try JSONEncoder().encode(body)) { data in
            try JSONDecoder().decode(Response.self, from: data)
        }
    }
}

public extension Endpoint where Response == Void {
    static func delete(_ path: String) -> Endpoint {
        Endpoint(method: .delete, path: path, body: nil) { _ in () }
    }
}

// MARK: - The calls this package makes

public extension Endpoint where Response == [Post] {
    static func posts(userID: Int? = nil) -> Endpoint {
        .get("posts", query: userID.map { ["userId": "\($0)"] } ?? [:])
    }
}

public extension Endpoint where Response == Post {
    static func post(id: Int) -> Endpoint {
        .get("posts/\(id)")
    }

    static func create(_ post: NewPost) throws -> Endpoint {
        try .post("posts", body: post)
    }
}

public extension Endpoint where Response == [Comment] {
    static func comments(postID: Int) -> Endpoint {
        .get("posts/\(postID)/comments")
    }
}

public extension Endpoint where Response == Void {
    static func deletePost(id: Int) -> Endpoint {
        .delete("posts/\(id)")
    }
}
