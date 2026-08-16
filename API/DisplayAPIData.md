# 9.8 Display API Data in Swift

**Deliverable:** Swift List showing API items.

A `List` of jsonplaceholder posts in HelloApp, fed by the tested layer from
9.6/9.7 with a detail pane, search, refresh, and the three states that aren't the
happy path.

| File | |
| --- | --- |
| [`XcodeDeepDive/HelloApp/HelloApp/PostsView.swift`](../XcodeDeepDive/HelloApp/HelloApp/PostsView.swift) | The SwiftUI views |
| [`API/MockAPIKit/Sources/MockAPIKit/PostsListModel.swift`](MockAPIKit/Sources/MockAPIKit/PostsListModel.swift) | The state machine |
| [`API/MockAPIKit/Sources/MockAPIKit/StaticHTTPClient.swift`](MockAPIKit/Sources/MockAPIKit/StaticHTTPClient.swift) | Canned client, for previews |
| [`API/MockAPIKit/Tests/MockAPIKitTests/PostsListModelTests.swift`](MockAPIKit/Tests/MockAPIKitTests/PostsListModelTests.swift) | 9 tests for the state machine |

Open it from the main window: **API Posts…**

## Two setup steps

**1. Link the package.** In Xcode: *File → Add Package Dependencies… → Add
Local…* → `API/MockAPIKit`, then add `MockAPIKit` to HelloApp's *Frameworks,
Libraries, and Embedded Content*. Same as `CounterKit` in 7.7. The view file
itself needs no project change — HelloApp uses Xcode 16 synchronized groups, so
anything dropped in the folder is compiled.

**2. The entitlement.** `HelloApp.entitlements` explicitly listed
`com.apple.security.network.client` under "deliberately NOT requested" (8.4).
It's requested now, because the app finally does the thing:

```xml
<key>com.apple.security.network.client</key>
<true/>
```

There is **no TCC prompt for the network** — the sandbox either allows the
connection or it doesn't. Without the key, every request fails with
`URLError.notConnectedToInternet` on a machine that is plainly online, and 9.5's
error mapping faithfully renders "You appear to be offline" over a working wifi
connection.

## One enum, four states

```swift
public enum State: Equatable {
    case idle
    case loading
    case loaded([Post])
    case failed(message: String, canRetry: Bool)
}
```

The alternative — `isLoading` plus `error` plus `items` — permits combinations
that are nonsense: loading *and* failed, items sitting alongside an error, an
empty array that could mean "no results" or "hasn't loaded yet". Every one of
those eventually renders. An enum makes them unrepresentable, and the view
becomes a `switch` with no `if` in it.

Two details the shape forces you to get right:

- **An empty list is a success.** `.loaded([])` renders "No posts" with a tray
  icon and no Retry button — different words and a different tone from a failure.
  Rendering "Something went wrong" because an array is empty is a very common bug.
- **`canRetry` comes from `APIError.isRetryable` (9.5).** The Try Again button
  only exists for failures where pressing it could plausibly help. On a 404 it
  isn't drawn at all, because the same request will fail identically.

The message on screen is `userMessage`, never `errorDescription` — the view never
sees a status code or a coding path. There's a test asserting exactly that.

## Where the logic lives

The model is in the **package**, not the app. It imports `Observation`, not
SwiftUI, and holds every decision worth testing: what `.task` should do on a
second appearance, what a failed refresh does to rows already on screen, how
search filters. That's 9 tests that need no window, no run loop and no
screenshot.

What's left in the view is a `switch` over four cases and some padding.

`@Observable` rather than `ObservableObject`: SwiftUI tracks only the properties
a view actually reads, so typing in the search field doesn't invalidate rows that
didn't change.

## Three SwiftUI details worth the space

**`.task` instead of `.onAppear` + `Task { }`.** `.task` is tied to the view's
lifetime and is cancelled when the view goes away; an unstructured `Task` in
`onAppear` outlives it and finishes a request nobody is waiting for.

**`.task(id: post.id)` in the detail pane.** It restarts when the selection
changes *and* cancels the request for the post the user just navigated away from.
Without the id, the detail pane shows the first post's comments forever.

**`.refreshable` is not enough on macOS.** There's no pull-to-refresh gesture, so
the modifier alone leaves the feature unreachable with a mouse. The same action
is also a toolbar button with ⌘R. This is the kind of thing an iOS tutorial won't
mention and a macOS app has to handle.

`loadIfNeeded()` exists because SwiftUI may run `.task` again when a view
reappears. It returns early when the state is already `.loaded`, and there's a
test that would catch it flashing a spinner over data that was already correct.

## Previews that show what running the app can't

`StaticHTTPClient` lives in the library rather than the test target so previews
can use it:

```swift
#Preview("Offline") { PostsView(api: .previewOffline) }
```

Four previews — Loaded, Loading, Empty, Offline. Three of those states are
unreachable while the API is working, so this is the only practical way to look
at the error screen and confirm it says something a person can act on. The
loading preview uses a 30-second delay, which is the cheapest way to hold a
spinner still.

Previews also run in a sandboxed process that may have no network at all, so a
preview depending on jsonplaceholder being up isn't a preview — it's a flaky
screenshot.

## Verification

```bash
cd API/MockAPIKit && swift test          # 31 tests, 6 skipped without RUN_INTEGRATION_TESTS=1
```

Then build and run HelloApp and press **API Posts…**. To see the failure path
without unplugging anything, comment the entitlement back out — the list will
show the offline message on a perfectly good connection, which is 9.5 and 8.4
meeting in the same screen.

## What I learned

Displaying API data is mostly not about displaying API data. The list itself is
about fifteen lines; everything else is deciding what the screen says when there
are no items, when the request failed in a way retrying can't fix, when the user
refreshes and *that* fails, and when they come back to a screen that already has
data.

Having the error type from 9.5 already carrying `userMessage` and `isRetryable`
made those decisions mechanical rather than inventive — the view asks the error
what to show and whether to offer a button, and the answers were settled three
issues ago.

## Sources

- [`ContentUnavailableView`](https://developer.apple.com/documentation/swiftui/contentunavailableview) — Apple
- [`View.task(id:priority:_:)`](https://developer.apple.com/documentation/swiftui/view/task(id:priority:_:)) — Apple
- [Observation](https://developer.apple.com/documentation/observation) — Apple
- [`refreshable`](https://developer.apple.com/documentation/swiftui/view/refreshable(action:)) — Apple
- [App Sandbox network entitlements](https://developer.apple.com/documentation/security/com_apple_security_network_client) — Apple
