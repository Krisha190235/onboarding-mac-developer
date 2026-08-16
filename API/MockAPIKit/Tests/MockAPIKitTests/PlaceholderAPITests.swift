//
//  PlaceholderAPITests.swift
//
//  Level 1: the API tested against a stub client. No network, no URLSession,
//  no timing. Every one of these runs in microseconds and cannot flake.
//
//  Two halves, and both matter:
//    - what the client SENDS  (URL, method, headers, body)
//    - what it does with what it GETS BACK (decode, errors, retries)
//
//  Most mock-API tests only do the second half and then ship a request with a
//  missing header.
//

import Foundation
import Testing
@testable import MockAPIKit

@Suite("PlaceholderAPI against a stub client")
struct PlaceholderAPITests {

    // MARK: - What goes out

    @Test("a list request builds the right URL and method")
    func listRequestIsCorrect() async throws {
        let client = MockHTTPClient(.ok(try Fixture.json("posts")))
        let api = PlaceholderAPI(baseURL: PlaceholderAPI.jsonplaceholder, client: client)

        _ = try await api.posts()

        let request = try #require(await client.lastRequest)
        #expect(request.url?.absoluteString == "https://jsonplaceholder.typicode.com/posts")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        // No body, so no Content-Type: it describes a body that isn't there.
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
    }

    @Test("query parameters are appended and sorted")
    func queryParametersAreSorted() async throws {
        let client = MockHTTPClient(.ok(try Fixture.json("posts")))
        let api = PlaceholderAPI(client: client)

        _ = try await api.posts(userID: 1)

        let request = try #require(await client.lastRequest)
        #expect(request.url?.query == "userId=1")
    }

    @Test("a create sends a JSON body, the right content type and an idempotency key")
    func createSendsJSONBody() async throws {
        let client = MockHTTPClient(.status(201, try Fixture.json("post")))
        let api = PlaceholderAPI(client: client)

        _ = try await api.create(NewPost(userId: 1, title: "Deep work", body: "50 minutes"))

        let request = try #require(await client.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        // POST isn't idempotent, so a retry needs the server to be able to spot
        // the duplicate (9.4).
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") != nil)

        // Assert on the decoded body, not on a string of JSON: key order isn't
        // guaranteed and a test that depends on it breaks for no reason.
        let body = try #require(request.httpBody)
        let sent = try JSONDecoder().decode(NewPost.self, from: body)
        #expect(sent == NewPost(userId: 1, title: "Deep work", body: "50 minutes"))
    }

    @Test("a 201 is a success, not just 200")
    func createdIsASuccess() async throws {
        let client = MockHTTPClient(.status(201, try Fixture.json("post")))
        let api = PlaceholderAPI(client: client)

        let post = try await api.create(NewPost(userId: 1, title: "t", body: "b"))
        #expect(post.id == 1)
    }

    // MARK: - What comes back

    @Test("a list response decodes into models")
    func listDecodes() async throws {
        let client = MockHTTPClient(.ok(try Fixture.json("posts")))
        let api = PlaceholderAPI(client: client)

        let posts = try await api.posts()

        #expect(posts.count == 3)
        #expect(posts.first?.id == 1)
        #expect(posts.first?.title.hasPrefix("sunt aut facere") == true)
        #expect(posts.allSatisfy { $0.userId == 1 })
    }

    @Test("comments decode, including the awkward fields")
    func commentsDecode() async throws {
        let client = MockHTTPClient(.ok(try Fixture.json("comments")))
        let api = PlaceholderAPI(client: client)

        let comments = try await api.comments(postID: 1)

        #expect(comments.count == 2)
        #expect(comments.first?.email == "Eliseo@gardner.biz")
        #expect(comments.allSatisfy { $0.postId == 1 })
    }

    @Test("an empty list is a success, not an error")
    func emptyListIsFine() async throws {
        let client = MockHTTPClient(.ok("[]"))
        let api = PlaceholderAPI(client: client)

        let posts = try await api.posts()
        #expect(posts.isEmpty)
    }

    @Test("a 204 with no body succeeds - Endpoint<Void> never reaches a decoder")
    func deleteSucceedsWithEmptyBody() async throws {
        // An empty body is the case that breaks any layer assuming every
        // response is JSON: JSONDecoder rejects zero bytes.
        let client = MockHTTPClient(.status(204, ""))
        let api = PlaceholderAPI(client: client)

        try await api.deletePost(id: 1)
        #expect(await client.callCount == 1)
    }

    // MARK: - Failures

    @Test("a 404 becomes a non-retryable error with a usable message")
    func notFoundIsNotRetried() async throws {
        let client = MockHTTPClient(.status(404, "{}"))
        let api = PlaceholderAPI(client: client, backoffScale: 0)

        do {
            _ = try await api.post(id: 9999)
            Issue.record("expected a 404 to throw")
        } catch let error as APIError {
            guard case .http(let status, _) = error else {
                Issue.record("expected .http, got \(error)")
                return
            }
            #expect(status == 404)
            #expect(error.isRetryable == false)
            #expect(error.userMessage == "That post no longer exists.")
            // The important assertion: it gave up immediately.
            #expect(await client.callCount == 1)
        }
    }

    @Test("a 200 carrying the wrong types is a decoding failure, not a success")
    func wrongTypesFailToDecode() async throws {
        let client = MockHTTPClient(.ok(try Fixture.json("post-wrong-types")))
        let api = PlaceholderAPI(client: client, backoffScale: 0)

        do {
            _ = try await api.post(id: 1)
            Issue.record("expected a decoding failure")
        } catch let error as APIError {
            guard case .malformedResponse = error else {
                Issue.record("expected .malformedResponse, got \(error)")
                return
            }
            #expect(error.isRetryable == false)
            // The same bytes will fail the same way, so one attempt only.
            #expect(await client.callCount == 1)
        }
    }

    @Test("a 5xx is retried and the call recovers")
    func serverErrorIsRetried() async throws {
        let client = MockHTTPClient(
            .status(503, "{}"),
            .status(503, "{}"),
            .ok(try Fixture.json("post"))
        )
        // backoffScale 0 - the retry policy is under test, not the sleeping.
        let api = PlaceholderAPI(client: client, maxAttempts: 3, backoffScale: 0)

        let post = try await api.post(id: 1)

        #expect(post.id == 1)
        #expect(await client.callCount == 3)
    }

    @Test("retries stop at maxAttempts and the last error is thrown")
    func retriesAreBounded() async throws {
        let client = MockHTTPClient(.status(500, "{}"))
        let api = PlaceholderAPI(client: client, maxAttempts: 3, backoffScale: 0)

        await #expect(throws: APIError.self) {
            _ = try await api.post(id: 1)
        }
        #expect(await client.callCount == 3)
    }

    @Test("a timeout is retried; a cancellation is not")
    func transportErrorsAreClassified() async throws {
        let timingOut = MockHTTPClient(.failure(URLError(.timedOut)))
        let timeoutAPI = PlaceholderAPI(client: timingOut, maxAttempts: 2, backoffScale: 0)
        await #expect(throws: APIError.self) { _ = try await timeoutAPI.post(id: 1) }
        #expect(await timingOut.callCount == 2)

        let cancelled = MockHTTPClient(.failure(URLError(.cancelled)))
        let cancelledAPI = PlaceholderAPI(client: cancelled, maxAttempts: 2, backoffScale: 0)
        await #expect(throws: APIError.self) { _ = try await cancelledAPI.post(id: 1) }
        #expect(await cancelled.callCount == 1)
    }
}
