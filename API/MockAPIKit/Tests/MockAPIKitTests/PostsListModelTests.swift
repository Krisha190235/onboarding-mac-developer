//
//  PostsListModelTests.swift  -  9.8
//
//  The state machine behind the list, tested without SwiftUI and without a
//  network. This is the argument for keeping the model out of the view: none of
//  these need a window, a run loop or a screenshot.
//
//  @MainActor on the suite because the model is main-actor isolated — the tests
//  have to run there to touch it at all.
//

import Foundation
import Testing
@testable import MockAPIKit

@Suite("PostsListModel state machine")
@MainActor
struct PostsListModelTests {

    private func makeModel(_ stubs: MockHTTPClient.Stub...) -> PostsListModel {
        let client = MockHTTPClient(stubs)
        return PostsListModel(api: PlaceholderAPI(client: client,
                                                  maxAttempts: 1,
                                                  backoffScale: 0))
    }

    @Test("starts idle, ends loaded")
    func loadsSuccessfully() async throws {
        let model = makeModel(.ok(try Fixture.json("posts")))
        #expect(model.state == .idle)

        await model.load()

        guard case .loaded(let posts) = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
        #expect(posts.count == 3)
    }

    @Test("an empty response is loaded-and-empty, not an error")
    func emptyIsNotAnError() async throws {
        let model = makeModel(.ok("[]"))

        await model.load()

        #expect(model.state == .loaded([]))
        #expect(model.posts.isEmpty)
    }

    @Test("a failure carries a user-facing message and whether retrying helps")
    func failureIsUserReady() async throws {
        let model = makeModel(.failure(URLError(.notConnectedToInternet)))

        await model.load()

        guard case .failed(let message, let canRetry) = model.state else {
            Issue.record("expected .failed, got \(model.state)")
            return
        }
        #expect(message == "You appear to be offline. Check your connection and try again.")
        #expect(canRetry)
        // No status codes or coding paths leaking to the screen.
        #expect(!message.contains("URLError"))
    }

    @Test("a 404 is a failure the user can't fix by pressing Retry")
    func notFoundIsNotRetryable() async throws {
        let model = makeModel(.status(404, "{}"))

        await model.load()

        guard case .failed(_, let canRetry) = model.state else {
            Issue.record("expected .failed, got \(model.state)")
            return
        }
        #expect(canRetry == false)
    }

    @Test("loadIfNeeded doesn't refetch when data is already on screen")
    func loadIfNeededIsIdempotent() async throws {
        let client = MockHTTPClient(.ok(try Fixture.json("posts")))
        let model = PostsListModel(api: PlaceholderAPI(client: client, backoffScale: 0))

        await model.loadIfNeeded()
        await model.loadIfNeeded()
        await model.loadIfNeeded()

        // SwiftUI can run .task again when a view reappears. If this were 3,
        // returning to the list would flash a spinner over correct data.
        #expect(await client.callCount == 1)
    }

    @Test("loadIfNeeded does try again after a failure")
    func loadIfNeededRetriesAfterFailure() async throws {
        let client = MockHTTPClient(
            .failure(URLError(.timedOut)),
            .ok(try Fixture.json("posts"))
        )
        let model = PostsListModel(api: PlaceholderAPI(client: client,
                                                       maxAttempts: 1,
                                                       backoffScale: 0))

        await model.loadIfNeeded()
        await model.loadIfNeeded()

        #expect(model.posts.count == 3)
        #expect(await client.callCount == 2)
    }

    @Test("a failed refresh keeps what's already on screen")
    func failedRefreshDoesNotBlankTheList() async throws {
        let client = MockHTTPClient(
            .ok(try Fixture.json("posts")),
            .failure(URLError(.networkConnectionLost))
        )
        let model = PostsListModel(api: PlaceholderAPI(client: client,
                                                       maxAttempts: 1,
                                                       backoffScale: 0))

        await model.load()
        await model.refresh()

        // Still showing the posts, not an error screen: the user was reading
        // them and losing a refresh isn't a reason to take them away.
        #expect(model.posts.count == 3)
        #expect(model.isRefreshing == false)
    }

    @Test("search filters on title and body, and ignores case")
    func searchFilters() async throws {
        let model = makeModel(.ok(try Fixture.json("posts")))
        await model.load()

        model.searchText = "QUI EST"
        #expect(model.visiblePosts.count == 1)
        #expect(model.visiblePosts.first?.id == 2)

        model.searchText = "iusto sed quo"          // matches a body, not a title
        #expect(model.visiblePosts.first?.id == 3)

        model.searchText = "   "                     // whitespace isn't a query
        #expect(model.visiblePosts.count == 3)

        model.searchText = "zzz no such thing"
        #expect(model.visiblePosts.isEmpty)
        #expect(model.posts.count == 3)              // filtered, not reloaded
    }

    @Test("the detail model loads comments for the selected post")
    func detailLoadsComments() async throws {
        let client = MockHTTPClient(.ok(try Fixture.json("comments")))
        let model = PostDetailModel(api: PlaceholderAPI(client: client, backoffScale: 0))

        await model.load(postID: 1)

        guard case .loaded(let comments) = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
        #expect(comments.count == 2)

        let request = try #require(await client.lastRequest)
        #expect(request.url?.path == "/posts/1/comments")
    }
}
