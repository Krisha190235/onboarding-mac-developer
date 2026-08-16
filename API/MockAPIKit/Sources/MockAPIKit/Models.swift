//
//  Models.swift
//
//  The two resources this package reads from jsonplaceholder. Sendable because
//  the package builds in Swift 6 language mode and these cross concurrency
//  domains; Equatable because tests are much easier to write when a whole model
//  can be compared in one #expect.
//

import Foundation

public struct Post: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let userId: Int
    public let title: String
    public let body: String

    public init(id: Int, userId: Int, title: String, body: String) {
        self.id = id
        self.userId = userId
        self.title = title
        self.body = body
    }
}

public struct Comment: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let postId: Int
    public let name: String
    public let email: String
    public let body: String
}

/// What gets sent on a create. Separate from `Post` because the server assigns
/// the id — a model with `let id: Int` can't represent a post that doesn't have
/// one yet, and making it optional just to satisfy the encoder pushes the
/// problem into every call site.
public struct NewPost: Codable, Sendable, Equatable {
    public let userId: Int
    public let title: String
    public let body: String

    public init(userId: Int, title: String, body: String) {
        self.userId = userId
        self.title = title
        self.body = body
    }
}

// jsonplaceholder returns camelCase already (`userId`, `postId`), so there's no
// key decoding strategy here. Worth checking rather than assuming: adding
// .convertFromSnakeCase to an API that doesn't need it is harmless until the
// day one field is `user_id` and one is `userId`.
