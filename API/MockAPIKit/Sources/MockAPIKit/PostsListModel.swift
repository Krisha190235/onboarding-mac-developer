//
//  PostsListModel.swift  -  9.8 Display API Data in Swift
//
//  The state machine behind the list. It lives in the package rather than the
//  app for one reason: everything here is testable, and none of it needs
//  SwiftUI. The View in HelloApp is then thin enough to be obviously correct by
//  reading it.
//
//  @Observable rather than ObservableObject: SwiftUI tracks only the properties
//  a view actually reads, so typing in the search field doesn't redraw rows that
//  didn't change.
//

import Foundation
import Observation

@MainActor
@Observable
public final class PostsListModel {

    /// Four states, not a pile of booleans. `isLoading` + `error` + `items` as
    /// separate flags allows combinations that are nonsense - loading and failed
    /// at once, items alongside an error - and every one of them eventually
    /// shows up on screen.
    public enum State: Equatable {
        case idle
        case loading
        case loaded([Post])
        case failed(message: String, canRetry: Bool)
    }

    public private(set) var state: State = .idle
    public private(set) var isRefreshing = false
    public var searchText = ""

    private let api: PlaceholderAPI

    public init(api: PlaceholderAPI = PlaceholderAPI()) {
        self.api = api
    }

    public var posts: [Post] {
        if case .loaded(let posts) = state { return posts }
        return []
    }

    /// Filtering happens here rather than in the view so it can be tested, and
    /// so the view has no logic to get wrong.
    public var visiblePosts: [Post] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return posts }
        return posts.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.body.localizedCaseInsensitiveContains(query)
        }
    }

    /// For `.task`, which SwiftUI may run again when the view reappears.
    /// Without the guard, coming back to the list refetches everything and
    /// flashes a spinner over data that was already correct.
    public func loadIfNeeded() async {
        switch state {
        case .idle, .failed:
            await load()
        case .loading, .loaded:
            break
        }
    }

    public func load() async {
        state = .loading
        do {
            state = .loaded(try await api.posts())
        } catch {
            state = Self.failure(from: error)
        }
    }

    /// Pull-to-refresh. Deliberately *not* `load()`: it leaves the current rows
    /// on screen instead of replacing them with a spinner, and a failed refresh
    /// keeps what the user was already reading rather than blanking the view.
    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            state = .loaded(try await api.posts())
        } catch {
            if posts.isEmpty {
                state = Self.failure(from: error)
            }
        }
    }

    private static func failure(from error: Error) -> State {
        let mapped = APIError.map(error)
        // userMessage, never errorDescription: the screen gets a sentence, the
        // log gets the status code and the coding path (9.5).
        return .failed(message: mapped.userMessage, canRetry: mapped.isRetryable)
    }
}

/// The detail pane. Same shape, one resource down.
@MainActor
@Observable
public final class PostDetailModel {
    public enum State: Equatable {
        case loading
        case loaded([Comment])
        case failed(message: String, canRetry: Bool)
    }

    public private(set) var state: State = .loading

    private let api: PlaceholderAPI

    public init(api: PlaceholderAPI = PlaceholderAPI()) {
        self.api = api
    }

    public func load(postID: Int) async {
        state = .loading
        do {
            state = .loaded(try await api.comments(postID: postID))
        } catch {
            let mapped = APIError.map(error)
            state = .failed(message: mapped.userMessage, canRetry: mapped.isRetryable)
        }
    }
}
