//
//  PostsView.swift  -  9.8 Display API Data in Swift
//
//  A List of posts fetched from jsonplaceholder through MockAPIKit (9.6/9.7).
//  The view holds no networking and no logic worth testing: it renders one of
//  four states and hands user actions back to the model.
//
//  Requires com.apple.security.network.client in HelloApp.entitlements (8.4).
//  Without it, every request fails with URLError.notConnectedToInternet and
//  this screen shows "You appear to be offline" on a machine that plainly
//  isn't — which is the most confusing five minutes in macOS development.
//

import SwiftUI
import MockAPIKit

struct PostsView: View {
    @State private var model: PostsListModel
    @State private var detail: PostDetailModel
    @State private var selection: Post.ID?

    /// The API is injected so previews can run offline against canned data.
    init(api: PlaceholderAPI = PlaceholderAPI()) {
        _model = State(initialValue: PostsListModel(api: api))
        _detail = State(initialValue: PostDetailModel(api: api))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationTitle("Posts")
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            if let post = selectedPost {
                PostDetailView(post: post, model: detail)
            } else {
                ContentUnavailableView("No post selected",
                                       systemImage: "doc.text",
                                       description: Text("Pick one from the list."))
            }
        }
        // .task is tied to the view's lifetime: it starts when the view appears
        // and is cancelled automatically when it goes away. Kicking work off in
        // .onAppear with an unstructured Task leaks a request the view can no
        // longer use.
        .task { await model.loadIfNeeded() }
    }

    private var selectedPost: Post? {
        guard let selection else { return nil }
        return model.posts.first { $0.id == selection }
    }

    // MARK: - The four states

    @ViewBuilder
    private var sidebar: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Loading posts…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message, let canRetry):
            ContentUnavailableView {
                Label("Couldn't load posts", systemImage: "wifi.exclamationmark")
            } description: {
                // The model already turned the error into a sentence. The view
                // never sees a status code or a coding path.
                Text(message)
            } actions: {
                if canRetry {
                    Button("Try Again") {
                        Task { await model.load() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

        case .loaded:
            loadedList
        }
    }

    @ViewBuilder
    private var loadedList: some View {
        if model.posts.isEmpty {
            // An empty list is a success, not a failure — different words,
            // no Retry button, no alarming icon.
            ContentUnavailableView("No posts",
                                   systemImage: "tray",
                                   description: Text("The API returned an empty list."))
        } else if model.visiblePosts.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        } else {
            List(model.visiblePosts, selection: $selection) { post in
                PostRow(post: post)
            }
            .searchable(text: $model.searchText, prompt: "Filter posts")
            // On iOS this is the pull-to-refresh gesture. macOS has no pull, so
            // the same action is also on the toolbar with ⌘R — the modifier
            // alone would leave the feature unreachable with a mouse.
            .refreshable { await model.refresh() }
            .toolbar {
                ToolbarItem {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r")
                    .disabled(model.isRefreshing)
                }
            }
            .overlay(alignment: .top) {
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .padding(6)
                }
            }
        }
    }
}

// MARK: - Rows

private struct PostRow: View {
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(post.title)
                .font(.headline)
                .lineLimit(2)
            Text(post.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail

private struct PostDetailView: View {
    let post: Post
    let model: PostDetailModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(post.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(post.body)
                    .font(.body)

                Divider()

                Text("Comments")
                    .font(.headline)

                switch model.state {
                case .loading:
                    ProgressView().controlSize(.small)

                case .failed(let message, _):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)

                case .loaded(let comments) where comments.isEmpty:
                    Text("No comments yet.")
                        .foregroundStyle(.secondary)

                case .loaded(let comments):
                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(comment.name).font(.subheadline).fontWeight(.medium)
                            Text(comment.email).font(.caption).foregroundStyle(.secondary)
                            Text(comment.body).font(.callout)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        // task(id:) restarts when the selection changes and cancels the request
        // for the post the user just navigated away from. Without the id, the
        // detail pane keeps showing the first post's comments forever.
        .task(id: post.id) {
            await model.load(postID: post.id)
        }
    }
}

// MARK: - Previews
//
// Four previews, because three of these states are unreachable when the API is
// working — you cannot see your own error screen by running the app.

#Preview("Loaded") {
    PostsView(api: .previewLoaded)
        .frame(width: 900, height: 520)
}

#Preview("Loading") {
    PostsView(api: .previewLoading)
        .frame(width: 900, height: 520)
}

#Preview("Empty") {
    PostsView(api: .previewEmpty)
        .frame(width: 900, height: 520)
}

#Preview("Offline") {
    PostsView(api: .previewOffline)
        .frame(width: 900, height: 520)
}
