//
//  HTTPClient.swift
//
//  The seam. PlaceholderAPI talks to this, never to URLSession directly, which
//  is what makes the mocked tests possible at all.
//
//  `: Sendable` because the package builds in Swift 6 language mode and the
//  client is held across suspension points.
//

import Foundation

public protocol HTTPClient: Sendable {
    func perform(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClient {
    public func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}
