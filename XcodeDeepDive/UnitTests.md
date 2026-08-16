# 7.6 Unit Tests — Swift Testing

The `HelloApp` project has **6 unit tests** written with Apple's **Swift Testing**
framework (`@Test` / `#expect`). They live in `HelloAppTests/HelloAppTests.swift`
and cover the counter logic and a pure workload function.

## What's tested

The testable logic was extracted out of the View into a `Counter` struct and a
`Workload` enum in `ContentView.swift`, so it can be tested with no UI:

| # | Test | What it verifies |
| --- | --- | --- |
| 1 | `incrementIncreasesCount` | `increment()` raises `count` by 1 |
| 2 | `doubledIsTwiceCount` | `doubled` equals `count * 2` |
| 3 | `historyRecordsEachIncrement` | each increment is appended to `history` in order |
| 4 | `resetClearsCounter` | `reset()` returns count and history to empty |
| 5 | `sqrtSumIsCorrect` | `Workload.sqrtSum(upTo: 4)` ≈ 6.14626 |
| 6 | `sqrtSumOfZeroIsZero` | `Workload.sqrtSum(upTo: 0)` == 0 (edge case) |

That's well past the "at least 3 tests" requirement.

## How the test target is set up

The `HelloAppTests` unit test bundle is already wired into
`HelloApp.xcodeproj` — you don't need to add it in Xcode:

- **Target:** `HelloAppTests`, product type `com.apple.product-type.bundle.unit-test`,
  depending on `HelloApp`.
- **Host app:** `TEST_HOST = $(BUILT_PRODUCTS_DIR)/HelloApp.app/Contents/MacOS/HelloApp`
  with `BUNDLE_LOADER = $(TEST_HOST)`, so `@testable import HelloApp` resolves.
- **Sources:** the target uses a *synchronized folder group* pointing at
  `HelloAppTests/`, so every `.swift` file in that folder is compiled — no manual
  "Add to target" step when you add more tests later.
- **Scheme:** `HelloApp.xcscheme` is shared (in `xcshareddata/xcschemes/`) and its
  **Test** action lists `HelloAppTests`, so ⌘U runs them and the scheme is in git.
- `ENABLE_TESTABILITY = YES` is already on in the Debug configuration.

## Run the tests

- Press **⌘U** (Product → Test), or click the diamond ◇ next to each `@Test` in
  the gutter to run just that one.
- The **Test Navigator** (⌘6) lists all six with green checkmarks when they pass.
  → *Optional screenshot: the Test Navigator showing 6 passing tests.*

## Repo note — HelloApp is no longer a nested repo

`XcodeDeepDive/HelloApp` used to be its **own** git repository nested inside this
one, so its files showed up on GitHub as an unusable grey link and none of the
7.3–7.6 code was actually browsable. That's been fixed: the inner `.git` was
removed, the submodule-style link was untracked, and the project is now committed
as ordinary files. `.gitignore` also picks up Xcode's per-user cruft
(`xcuserdata/`, `*.xcuserstate`).

The 7.6 commit is made locally — run `git push` when you're ready, and include
`Closes #21` (already in the commit message) to close the issue.
